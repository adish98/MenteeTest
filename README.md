# Hello World service

A small Flask API, packaged as a Docker image and deployed to AWS ECS Fargate
behind an ALB. Infrastructure is managed with Terraform; GitHub Actions tests,
builds, provisions, and deploys.

- `GET /` → `{"message":"Hello World","version":"<APP_VERSION>"}` (default `0.0.0`)
- `GET /health` → `{"status":"ok"}`

## Quick start

```sh
python -m pip install -r requirements-dev.txt
python -m pytest -v          # unit tests
python hello_world.py        # runs on http://localhost:8080
```

With Docker:

```sh
docker build -t exam-adi-shmul .
docker run --rm -p 8080:8080 -e APP_VERSION=1.2.3 exam-adi-shmul
```

## CI/CD

`.github/workflows/ci-cd.yaml`: **test + version → build → terraform → deploy**

- **Pull requests:** tests, image build, and container smoke test only. The
  run summary shows the version that merging would release.
- **Push to `main`:** works out the new version, tags the commit `vX.Y.Z`,
  pushes the image to GHCR with that tag, runs the Terraform sub-workflow
  (`terraform.yaml`: lint → plan → **manual approval** → apply), deploys to
  ECS, checks that the app serves the new version, and updates `APP_VERSION`.
- **Manual run:** choose a **bump** (`auto` redeploys this commit's version),
  and uncheck **terraform** to deploy only the new image.

### Versioning (SemVer)

Each merge to `main` releases a new version. Choose the bump with a label on
the PR (the labels are created automatically on the first release):

| PR label (or text in the commit message) | 1.2.3 becomes |
| --- | --- |
| `major` (`#major`) | 2.0.0 |
| `minor` (`#minor`) | 1.3.0 |
| `patch` (`#patch`), or nothing | 1.2.4 |

The latest `vX.Y.Z` git tag is the current version. Setting `APP_VERSION`
higher makes the next release continue from there. Re-running a release reuses
its version instead of bumping again.

Setup (**Settings > Environments > menteeTest**):

- Variables: `AWS_REGION`, `APP_VERSION`, `TF_STATE_BUCKET`, and optionally
  `TF_APP_NAME`.
- Secret `APP_VERSION_TOKEN`: lets the pipeline update `APP_VERSION` after each
  release. Use a fine-grained personal access token for this repository with
  **Environments: Read and write**. Without it, releases still work but
  `APP_VERSION` isn't updated.

**Approving Terraform:** after `plan`, the run opens an issue titled
*Approve Terraform apply* and waits for the repository owner. Read the plan in
the run summary, then comment **approve** to apply or **deny** to cancel. With
no answer within 2 hours, the run stops without applying.

## Security

- **State bucket (S3):** public access blocked, ACLs disabled, versioning,
  AES256 encryption, HTTPS/TLS 1.2+ only, and old versions expire after
  90 days. CI re-applies these settings on every run.
- **ECS tasks:** non-root user, read-only root filesystem, all Linux capabilities dropped, and ECS Exec disabled.
- **Network:** tasks accept traffic only from the ALB on port 8080 and can
  send only HTTPS out. The VPC's default security group has no rules. The ALB
  drops invalid headers and uses the strictest request-smuggling (desync)
  protection.
