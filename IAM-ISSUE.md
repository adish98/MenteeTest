# Terraform ECS execution role permission issue

## Error

Terraform failed to create `exam-adi-shmul-execution`:

```text
AccessDenied: assumed-role/exam-adi-shmul/GitHubActions
is not authorized to perform iam:CreateRole
on role/exam-adi-shmul-execution
```

## Cause

The GitHub Actions role provisions infrastructure. ECS needs a task execution
role to pull images from ECR and write logs to CloudWatch. These roles serve
different purposes.

The supplied IAM policy allows creating roles named `exam-*` only when the
creation request includes this permissions boundary:

```text
arn:aws:iam::030454160336:policy/candidate-exam-boundary
```

The original Terraform role resource did not specify that boundary, so its
creation request did not satisfy the policy condition. This explains the
failure if that policy is attached to the GitHub Actions role.

## Additional policy restriction

The supplied London-only policy allows operations when `aws:RequestedRegion`
is `eu-west-2`. IAM uses a global endpoint evaluated as `us-east-1`.
If this document is the permissions boundary attached to the GitHub Actions
role, it does not allow IAM role creation, even if an identity policy does.
Adding the required boundary to a newly created role alone would not solve
that separate restriction on the caller.

The supplied policy also explicitly denies `iam:PassRole` for roles outside
`arn:aws:iam::030454160336:role/exam-*`. That Deny does not grant permission
to pass matching roles; an effective Allow is still required.

Policy attachments and the caller's effective permissions have not been
verified in AWS.

## Confirmed cause

The pipeline error after adding the role boundary was:

```text
not authorized to perform: iam:CreateRole on resource:
arn:aws:iam::030454160336:role/exam-adi-shmul-execution because no
permissions boundary allows the iam:CreateRole action
```

The only broad Allow in the caller's boundary requires
`aws:RequestedRegion = eu-west-2`. IAM requests are evaluated as `us-east-1`,
so the boundary blocks every IAM call (create, attach, and even list/get),
whatever the identity policy allows. The execution role cannot be created by
the pipeline or by a user with the same boundary.

## Resolution

The app now runs without an ECS task execution role. Fargate only needs one to
pull private images and to send logs with the `awslogs` driver, so:

- Images are pushed to GitHub Container Registry (`ghcr.io/adish98/menteetest`)
  using the workflow's `GITHUB_TOKEN`, and the package is public.
- The task definition has no `execution_role_arn` and no `logConfiguration`.
- Terraform creates no IAM resources and no CloudWatch log group.

Trade-offs: the image is publicly pullable, and container logs are not
collected. ECS service events and ALB health checks remain available.

If an administrator later provides an `exam-*` execution role, private ECR and
CloudWatch logging can be restored by setting `execution_role_arn` and the
`awslogs` configuration on the task definition again.

## References

- [ECS task execution roles](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html)
- [IAM permissions boundary condition](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html)
- [Requested region and global endpoints](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html)
- [Permissions boundary evaluation](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html)
- [Passing a role to an AWS service](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html)
