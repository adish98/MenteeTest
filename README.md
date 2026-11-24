# Hello World service

Install dependencies (Python 3.9 or later):

```sh
python -m pip install -r requirements.txt
```

Run locally:

```sh
python hello_world.py
```

Run in production on Linux, macOS, or WSL using Gunicorn:

```sh
gunicorn --bind 0.0.0.0:8080 hello_world:app
```

Both commands listen on `0.0.0.0:8080`. Set `APP_VERSION` in the
process environment to the application's SemVer (for example, `1.2.3`).
When unset, it defaults to `0.0.0`.

- `GET /` returns `{"message":"Hello World","version":"0.0.0"}` by default.
- `GET /health` returns HTTP 200 with `{"status":"ok"}`.

Run the unit tests:

```sh
python -m unittest discover -v
```

Build and run with Docker:

```sh
docker build -t hello-world .
docker run --rm -p 8080:8080 -e APP_VERSION=1.2.3 hello-world
```

The container uses Python slim and runs `python hello_world.py` as a non-root user.
This starts Flask's development server; use the Gunicorn command above for production.
Omit `-e APP_VERSION=1.2.3` to use the default version `0.0.0`.

## GitHub Actions deployment

Pull requests to `main` build the image. Pushes to `main` and manual runs on
`main` build and push directly to ECR, call Terraform, then deploy only after
Terraform checks, plan, apply, and variable publication succeed.
The deploy job reads cluster, service, task family, container name, and URL
directly from the called Terraform workflow's outputs.
Tests can be run locally using the command above.
Images use `<commit-sha>-<run_number>` tags. Retries reuse the same image;
new manual runs produce a new tag and rebuild without cached layers.
AWS authentication uses OIDC. No version-management token is required.

Set these GitHub repository variables:

| Variable | Value |
| --- | --- |
| `AWS_REGION` | AWS region containing ECR and ECS |
| `AWS_ROLE_ARN` | IAM role assumed through GitHub OIDC |
| `ECR_REPOSITORY` | Existing ECR repository name, with tag immutability set to `IMMUTABLE` |
| `ECS_CLUSTER` | Automatically published from Terraform |
| `ECS_SERVICE` | Automatically published from Terraform |
| `ECS_TASK_DEFINITION` | Automatically published task definition family |
| `ECS_CONTAINER_NAME` | Automatically published from Terraform |
| `APP_URL` | Automatically published application URL |

The task definition must support Linux AMD64 and expose container port 8080.
The workflow registers a revision, deploys the ECR digest, waits for service
stability, then checks `/health`. It enables ECS rolling
deployment with automatic rollback and keeps the existing tasks healthy while
starting replacements (100% minimum healthy, 200% maximum). The service must
use the ECS rolling deployment controller and have capacity to start replacement
tasks. Configure container or load balancer health checks against `/health`.
Rollback requires an earlier successfully completed deployment. This is a rolling
update, not an atomic blue/green traffic switch.

Configure the IAM role's OIDC trust for this repository's `main` branch with
audience `sts.amazonaws.com`. Give it ECR read/push permissions, ECS task
definition read/register and service read/update permissions, and `iam:PassRole`
for the task and execution roles. The ECS execution role must be able to pull
from ECR. ECR, the state bucket, and OIDC roles must already exist. The app
workflow calls Terraform to provision application resources before deployment.
Production pipelines run one at a time.

## Terraform application infrastructure

Terraform in `terraform/app` creates the VPC, two public subnets, Internet
Gateway, HTTP ALB, ECS cluster and Fargate service, CloudWatch logs, and task
execution role in `eu-west-2`. ECR and GitHub authentication are managed separately.

Requires Terraform 1.10+ and AWS credentials with provisioning permissions.
Push the initial Linux AMD64 image to an existing ECR repository first.
From the repository root (PowerShell):

```powershell
Copy-Item terraform/app/terraform.tfvars.example terraform/app/terraform.tfvars
```

Edit `image_uri` to the full URI of the existing image, preferably pinned by
digest. Set `name` if desired, then deploy:

```powershell
terraform -chdir=terraform/app init -backend-config="bucket=YOUR_STATE_BUCKET" -backend-config="region=YOUR_BUCKET_REGION"
terraform fmt -recursive -check terraform
terraform -chdir=terraform/app validate
terraform -chdir=terraform/app plan
terraform -chdir=terraform/app apply
terraform -chdir=terraform/app output
$applicationUrl = terraform -chdir=terraform/app output -raw application_url
Invoke-RestMethod "$applicationUrl/health"
```

The service runs one task with 256 CPU units and 512 MB RAM. Tasks use public
IPs for outbound access without a NAT Gateway. Only the ALB can reach task port
8080; the ALB accepts public HTTP on port 80. Logs are retained for seven days.
ECS deployment circuit breaker and automatic rollback are enabled. Rollback
requires a previous healthy deployment.

For the existing workflow, set `AWS_REGION=eu-west-2`. Terraform returns
`ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_DEFINITION` (the family),
`ECS_CONTAINER_NAME`, and `APP_URL` to the deploy job and publishes them as
repository variables. Configure `ECR_REPOSITORY` and
`AWS_ROLE_ARN` using your separately managed ECR repository and GitHub OIDC role.
Terraform ignores service task definition revisions changed by CI/CD.
Changes to Terraform task settings require a subsequent service deployment.

State is stored in an existing S3 bucket with native locking. Keep state out of
Git and commit `.terraform.lock.hcl`. The bucket must exist before initialization;
enable bucket versioning and block public access. See the Terraform CI setup below.

To remove the app, stop CI/CD runs and execute:

```powershell
terraform -chdir=terraform/app destroy
```

This removes app resources and logs. Separately managed ECR images and GitHub
roles are retained. CI/CD-created task definition revisions are outside
Terraform state; deregister any remaining revisions separately if desired.

## Terraform CI/CD

`.github/workflows/terraform.yaml` is reusable and also checks PRs when app
Terraform files or the Terraform workflow change. PRs run formatting, validation,
TFLint, and an AWS-backed plan. The app workflow calls it after building and
pushing an image on `main`, passing the image digest as the initial task image.
The called workflow runs checks, plans, applies the saved plan, and returns
deployment outputs. Any failure prevents the app deploy job from starting.
Protect `main` with required PR reviews and checks if changes must go through
merges; direct main pushes and manual app runs on `main` also apply Terraform.
Fork PRs run lint checks only and receive no AWS credentials.

Set these repository Actions variables:

| Variable | Value |
| --- | --- |
| `AWS_REGION` | `eu-west-2`, matching the provider configuration |
| `TF_STATE_BUCKET` | Existing S3 state bucket name |
| `TF_STATE_REGION` | AWS region of the state bucket |
| `TF_PLAN_ROLE_ARN` | OIDC role for PR plans with infrastructure read permissions |
| `TF_APPLY_ROLE_ARN` | OIDC role with permissions to provision app resources |
| `TF_IMAGE_URI` | Existing image URI for standalone PR plans; app runs pass their built image |
| `TF_APP_NAME` | Optional app name; defaults to `hello-world` |

The roles are separate from the application deployment role. Configure the PR
role's OIDC trust subject as `repo:OWNER/REPO:pull_request`, and the apply role's
subject as `repo:OWNER/REPO:ref:refs/heads/main`; both use audience
`sts.amazonaws.com`. Treat branches in this repository as trusted: PR code runs
with the plan role. Its infrastructure permissions should only allow reads.
The apply role needs VPC/EC2, ELB, ECS, CloudWatch Logs, and task execution IAM
role provisioning permissions, including `iam:PassRole` for that execution role.

Both roles need `s3:ListBucket` on the state bucket, `s3:GetObject` on
`hello-world/app/terraform.tfstate`, and `s3:GetObject`, `s3:PutObject`, and
`s3:DeleteObject` on `hello-world/app/terraform.tfstate.tflock`. The apply role
also needs `s3:PutObject` on the state object. Add KMS access if the bucket uses
a customer-managed KMS key. The bucket and OIDC roles are managed separately.

If you already deployed using local state, migrate it once **before enabling
the workflow**, from the machine holding the existing state:

```powershell
terraform -chdir=terraform/app init -migrate-state -backend-config="bucket=YOUR_STATE_BUCKET" -backend-config="region=YOUR_BUCKET_REGION"
```

Confirm the migration prompt to copy the existing state. Starting CI with an
empty remote state would attempt to create duplicate infrastructure. Keep the
same app name and initial image URI used by the existing state. All local
plan/apply/destroy commands must use this same backend.

The workflow serializes Terraform operations and uses S3 state locks. It
recalculates the plan after merge and applies that exact plan in the same job.
The application deploy job then updates the ECS service with the built image.

After a successful apply on `main`, Terraform CI automatically creates or updates
`ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_DEFINITION`, `ECS_CONTAINER_NAME`, and
`APP_URL` repository variables from the Terraform outputs.

Add the repository **secret** `TF_VARIABLES_TOKEN`: a fine-grained GitHub token
restricted to this repository with **Variables: read and write** permission.
The default `GITHUB_TOKEN` does not provide this permission. The publishing step
uses this token only after apply on `main`; PR runs do not publish variables.

The current app deployment uses the reusable workflow outputs immediately;
it does not depend on GitHub refreshing repository variables mid-run. Published
repository variables are also available to subsequent workflows.
