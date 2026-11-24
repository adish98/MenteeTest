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

`.github/workflows/ci-cd.yaml`: **test → build → terraform → deploy**

- **Pull requests:** tests, image build, and container smoke test only.
- **Push to `main`:** pushes the image to GHCR tagged with `APP_VERSION`, then
  runs the Terraform sub-workflow (`terraform.yaml`: lint → plan → **manual
  approval** → apply), then deploys to ECS.
- **Manual run:** uncheck **terraform** to skip infrastructure and deploy only
  the newly built image.

Setup (**Settings > Environments**):

- `menteeTest`: variables `AWS_REGION`, `APP_VERSION`, `TF_STATE_BUCKET`, and
  optionally `TF_APP_NAME`.
- `menteeTest-approval`: add yourself under **Required reviewers**. Runs pause
  before `apply` until you click **Review deployments > Approve**.
