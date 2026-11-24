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
docker build -t exam-adi-shmul .
docker run --rm -p 8080:8080 -e APP_VERSION=1.2.3 exam-adi-shmul
```

The container uses Python slim and runs `python hello_world.py` as a non-root user.
This starts Flask's development server; use the Gunicorn command above for production.
Omit `-e APP_VERSION=1.2.3` to use the default version `0.0.0`.

## GitHub Actions deployment

Pull requests to `main` build the image. Pushes to `main` and manual runs on
`main` build and push to GitHub Container Registry (GHCR), call Terraform, then deploy only after
Terraform checks, plan, apply, and variable publication succeed.
The deploy job reads cluster, service, task family, container name, and URL
directly from the called Terraform workflow's outputs.
Tests can be run locally using the command above.
Images use the `APP_VERSION` GitHub environment variable as their tag (for
example, `1.2.3`). The same value is baked into the container's `APP_VERSION`
environment variable, which the API returns. Set a new version before each
release; an existing version tag reuses its published image, including on
manual runs and retries. Do not overwrite published version tags.
Images are pushed to `ghcr.io/<owner>/<repo>` (lowercase) using the workflow's
`GITHUB_TOKEN`. After the first push, set the package visibility to **Public**
(**Packages > package settings > Change visibility**) so Fargate can pull it
without credentials. AWS authentication uses OIDC.

Set these variables under **Settings > Environments > menteeTest > Environment variables**:

| Variable | Value |
| --- | --- |
| `AWS_REGION` | AWS region containing ECS |
| `APP_VERSION` | Application and image version, for example `1.2.3` |

The task definition must support Linux AMD64 and expose container port 8080.
The workflow registers a revision, deploys the GHCR digest, waits for service
stability, then checks `/health`. It enables ECS rolling
deployment with automatic rollback and keeps the existing tasks healthy while
starting replacements (100% minimum healthy, 200% maximum). The service must
use the ECS rolling deployment controller and have capacity to start replacement
tasks. Configure container or load balancer health checks against `/health`.
Rollback requires an earlier successfully completed deployment. This is a rolling
update, not an atomic blue/green traffic switch.

Configure the IAM role's OIDC trust for the `menteeTest` environment with
audience `sts.amazonaws.com`. Give it ECS task definition read/register and
service read/update permissions. No ECS task execution role is used (the
permissions boundary blocks IAM role creation), so `iam:PassRole` is not required. The OIDC role must already
exist. The state bucket is created
automatically if missing. The app
workflow calls Terraform to provision application resources before deployment.
Production pipelines run one at a time.

## Terraform application infrastructure

### Automatic state bucket creation

Before backend initialization, the pipeline creates `TF_STATE_BUCKET` in
`AWS_REGION` if missing, with versioning, AES256 encryption, and public access
blocked. An existing bucket owned by the current AWS account is reused without
changes. Permission errors stop the pipeline. Choose a globally unique bucket
name. No manual bootstrap is required for CI.

The pipeline uses the AWS CLI so bootstrap state does not need to persist on
temporary runners. The apply role additionally needs `s3:CreateBucket`,
`s3:PutBucketPublicAccessBlock`, `s3:PutBucketVersioning`, and
`s3:PutEncryptionConfiguration` on the chosen bucket. Existing buckets should
already have those protections.

### Optional manual bucket creation

Before initializing the application, use AWS credentials with S3 provisioning
permissions to run this from the repository root:

```powershell
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply
terraform -chdir=terraform/bootstrap output
```

This creates `exam-adi-shmul-tfstate-<AWS-account-ID>-eu-west-2` with versioning,
AES256 encryption, blocked public access, and Terraform deletion protection.
Use `-var="region=YOUR_REGION"` on apply to select another bucket region.
Set the GitHub environment variables `TF_STATE_BUCKET` and `AWS_REGION`
to the `state_bucket` and `state_region` outputs before running the app workflow.
Use these same values in the application's `init` command below.

Bootstrap uses local state because the bucket does not exist yet. Keep
`terraform/bootstrap/terraform.tfstate` securely backed up and reuse it for
future bootstrap operations; it is ignored by Git. Run bootstrap from a
persistent machine, not an ephemeral CI runner. The application workflow reuses
the created bucket. Commit the generated bootstrap
`.terraform.lock.hcl` when initializing with your chosen provider version.

Terraform in `terraform/app` creates the VPC, two public subnets, Internet
Gateway, HTTP ALB, and ECS cluster and Fargate service in `eu-west-2`. It creates
no IAM resources: the exam permissions boundary blocks all IAM writes, so tasks
run without an execution role. They therefore pull a public image and do not
send container logs to CloudWatch. GitHub authentication is managed separately.

Requires Terraform 1.10+ and AWS credentials with provisioning permissions.
Push the initial Linux AMD64 image to a public GHCR package first.
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
8080; the ALB accepts public HTTP on port 80. Container logs are not collected;
use ECS service events and ALB health checks for troubleshooting.
ECS deployment circuit breaker and automatic rollback are enabled. Rollback
requires a previous healthy deployment.

For the existing workflow, set `AWS_REGION=eu-west-2`. Terraform returns
`ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_DEFINITION` (the family),
`ECS_CONTAINER_NAME`, and `APP_URL` to the deploy job as reusable workflow
outputs. Configure `AWS_ROLE_ARN` using your separately managed
GitHub OIDC role.
Terraform ignores service task definition revisions changed by CI/CD.
Changes to Terraform task settings require a subsequent service deployment.

State is stored in an existing S3 bucket with native locking. Keep state out of
Git and commit `.terraform.lock.hcl`. The bucket must exist before initialization;
enable bucket versioning and block public access. See the Terraform CI setup below.

To remove the app, stop CI/CD runs and execute:

```powershell
terraform -chdir=terraform/app destroy
```

This removes app resources. GHCR images and GitHub roles are retained. CI/CD-created task definition revisions are outside
Terraform state; deregister any remaining revisions separately if desired.

## Terraform CI/CD

`.github/workflows/terraform.yaml` is reusable and also checks PRs when app
Terraform files or the Terraform workflow change. PRs run formatting, validation,
and TFLint only, without AWS access. The app workflow calls it after building and
pushing an image on `main`, passing the image digest as the initial task image.
The called workflow runs checks, plans, applies the saved plan, and returns
deployment outputs. Any failure prevents the app deploy job from starting.
Protect `main` with required PR reviews and checks if changes must go through
merges; direct main pushes and manual app runs on `main` also apply Terraform.
Plan and apply run only through the app pipeline on `main`.

Set these variables under **Settings > Environments > menteeTest > Environment variables**:

| Variable | Value |
| --- | --- |
| `AWS_REGION` | `eu-west-2`, matching the provider configuration |
| `TF_STATE_BUCKET` | S3 state bucket name; created automatically if missing |
| `TF_APP_NAME` | Optional app name; defaults to `exam-adi-shmul` |

The Terraform apply role is separate from the application deployment role.
Configure its OIDC trust subject as `repo:OWNER/REPO:environment:menteeTest` with
audience `sts.amazonaws.com`. A PR plan role is no longer needed.
The apply role needs VPC/EC2, ELB, and ECS provisioning permissions. No IAM
permissions are needed because Terraform creates no IAM resources.

The apply role needs `s3:ListBucket` on the state bucket, `s3:GetObject` on
`exam-adi-shmul/app/terraform.tfstate`, and `s3:GetObject`, `s3:PutObject`, and
`s3:DeleteObject` on `exam-adi-shmul/app/terraform.tfstate.tflock`. The apply role
also needs `s3:PutObject` on the state object. Add KMS access if the bucket uses
a customer-managed KMS key. OIDC roles are managed separately.

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

Set `AWS_ROLE_ARN` and `TF_APPLY_ROLE_ARN` as **environment secrets** under
**Settings > Environments > menteeTest**. The workflows read role ARNs using
the `secrets` context.

The app deployment reads Terraform outputs directly from the reusable workflow,
so no GitHub token or repository variables are needed to pass them along.

The release build, Terraform plan/apply, and ECS deploy jobs use `menteeTest`.
The shared build job uses no environment for PRs and uses `menteeTest` for
releases. PR builds skip AWS authentication and image pushing. Terraform lint
jobs do not use the environment. Configure
the environment's deployment branch rules to allow only `main`, and add required
reviewers if approval is desired. Both AWS OIDC roles must trust the subject
`repo:adish98/MenteeTest:environment:menteeTest` with audience `sts.amazonaws.com`.
Environment secrets are read inside the Terraform job rather than passed through
the reusable workflow caller.
