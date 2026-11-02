# Policies

All policy documents for Lab 1 are in this folder. The console walkthrough and Terraform use the same files:
- [`guardrails`](../terraform/guardrails) reads `scp/`, `tag/` and `declarative/` directly.
- [`logging`](../terraform/logging) builds the same `logging/` statements with `aws_iam_policy_document`.

Each `Sid` starts with the control ID it implements (C2, C3 …). See the [controls table](../README.md#-compliance-controls).

| File | Type | Attached to | Controls | What it does |
|---|---|---|---|---|
| [`scp/deny-leave-org.json`](scp/deny-leave-org.json) | SCP | Root | C6 | Accounts can't leave the org or close themselves |
| [`scp/protect-baseline.json`](scp/protect-baseline.json) | SCP | Root | C3 C4 C7 C15 | Blocks root use; locks account BPA; security services can't be stopped; log bucket is immutable |
| [`scp/region-restriction.json`](scp/region-restriction.json) | SCP | Root | C5 | Denies everything outside `us-east-1` and `ap-south-1`, except global services |
| [`scp/workload-guardrails.json`](scp/workload-guardrails.json) | SCP | Workloads OU | C2 C8 C9 C10 | No IAM users or keys; encrypted EBS; IMDSv2; required tags |
| [`scp/deny-all.json`](scp/deny-all.json) | SCP | Suspended OU | — | Parked accounts can do nothing |
| [`tag/workload-tags.json`](tag/workload-tags.json) | Tag policy | Workloads OU | C10 | Allowed values for `Project` and `Environment` |
| [`declarative/ec2-baseline.json`](declarative/ec2-baseline.json) | EC2 (declarative) policy | Root | C9 | IMDSv2 default, no public AMI or snapshot sharing, no serial console |
| [`logging/kms-key-policy.json`](logging/kms-key-policy.json) | KMS key policy | Log key (security account) | C11 | CloudTrail may encrypt; org members may decrypt |
| [`logging/log-bucket-policy.json`](logging/log-bucket-policy.json) | S3 bucket policy | Log bucket (security account) | C11 | Only *your* org trail may write; TLS only |

## Exempt principal

The SCPs exempt **`OrganizationAccountAccessRole`** from C4, C5, C7 and C15. Only management-account admins can assume this role, and they could detach SCPs anyway, so the exemption gives away nothing. It serves as:
- the **break-glass** path (see [Phase 6 field notes](../docs/06-security-services.md#-field-notes))
- the **Terraform** path into member accounts

## Fill in the logging templates

```bash
sed -e 's/<MGMT_ID>/111111111111/g' -e 's/<SECURITY_ID>/222222222222/g' -e 's/<ORG_ID>/o-abc123defg/g' \
  logging/kms-key-policy.json > /tmp/kms-key-policy.json
```

## Validate before attaching

```bash
aws accessanalyzer validate-policy --policy-type SERVICE_CONTROL_POLICY --policy-document file://scp/protect-baseline.json
```
Zero findings means the policy is valid. Access Analyzer caught a non-existent action (`s3:DeleteAccountPublicAccessBlock`) in this lab before it reached AWS.
