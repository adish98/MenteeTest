terraform {
  backend "s3" {
    # Bucket and bucket region are supplied to terraform init.
    key          = "exam-adi-shmul/app/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
