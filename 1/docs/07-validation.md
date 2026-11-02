# Phase 7 — Validate: A Control You Haven't Tested Is a Hope

> **Mission:** prove every control works, from the point of view of the people it's meant to constrain.

[⬅ Phase 6](06-security-services.md) · [Lab overview](../README.md) · [Phase 8 ➡](08-cleanup.md)

---

## The three rules of testing guardrails

1. **Right principal.** Test as an **SSO user in the security account** (`--profile acme-security`). The management account and `OrganizationAccountAccessRole` aren't subject to the SCPs.
2. **Safe calls.** If the guardrail failed, the test should change nothing. Re-apply current values, target fake resources, or use `--dry-run`.
3. **Read the error.** A real SCP denial says **"…with an explicit deny in a service control policy"**. Validation errors (`InvalidArgument`, `NoSuchKey`) mean the permission check never ran.

Temporarily attach `workload-guardrails` to the security account for the rows marked **\***, then move it back to Workloads.

## Test matrix

| # | Control | Command / action | Expected |
|---|---|---|---|
| 1 | C1 | Sign in to the access portal as a brand-new user | Forced to register MFA |
| 2 | Least privilege | Sign in as `payments-dev1` | Portal shows **no accounts** |
| 3 | C3 | Organizations → IAM → Root access management | Member root credentials: *Not present* |
| 4 | C4 | `aws s3control put-public-access-block --account-id <SECURITY_ID> --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true` | Explicit deny (SCP) |
| 5 | C5 | `aws ec2 describe-vpcs --region eu-west-1` | Explicit deny (SCP) |
| 6 | C6 | `aws organizations leave-organization` | Explicit deny (SCP) |
| 7 | C7 | `aws guardduty delete-detector --detector-id 00000000000000000000000000000000` | Explicit deny (SCP) |
| 8 | C7 | `aws cloudtrail stop-logging --name arn:aws:cloudtrail:us-east-1:<MGMT_ID>:trail/org-trail` | Access denied: member accounts can't touch an org trail |
| 9 | C15 | Console: log bucket → *Show versions* → permanently delete a version | Access denied |
| 10 | C15 | `aws s3api put-bucket-versioning --bucket <LOG_BUCKET> --versioning-configuration Status=Enabled` | Explicit deny (SCP) |
| 11 | C2 \* | `aws iam create-access-key --user-name scp-test-nonexistent` | Explicit deny (SCP) |
| 12 | C10 \* | `aws ec2 run-instances --dry-run --instance-type t3.micro --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64` | Explicit deny (SCP) |
| 13 | C9 \* | #12 + tags + `--metadata-options HttpTokens=optional` | Explicit deny (SCP) |
| 14 | C8 \* | `aws ec2 create-volume --dry-run --availability-zone us-east-1a --size 1 --no-encrypted --tag-specifications …` | Explicit deny (SCP) |
| 15 | ✅ \* | #12 + tags + `HttpTokens=required` + `Ebs={Encrypted=true}` | `DryRunOperation` (would succeed) |
| 16 | C9 | `aws ec2 get-instance-metadata-defaults` / `get-snapshot-block-public-access-state` | `ManagedBy: declarative-policy` |
| 17 | C11 | `aws cloudtrail validate-logs --trail-arn … --start-time … --account-id <SECURITY_ID>` | All digests and log files valid* |
| 18 | C12 | `aws configservice get-aggregate-discovered-resource-counts --configuration-aggregator-name org-aggregator --group-by-key ACCOUNT_ID` | Both accounts listed |
| 19 | C13 | Security Hub CSPM → Findings (security) | GuardDuty and FSBP findings from both accounts |
| 20 | C13 | Access Analyzer → active findings | 0 (SSO roles archived) |
| 21 | C14 | Billing → Budgets | Budget with alerts |

\* *If you did the Phase 4 deletion experiment, validation will keep reporting those two files as `INVALID: not found`. That's your evidence that the detection works.*

Tag commands for #13–15:
```bash
TI='ResourceType=instance,Tags=[{Key=Project,Value=payments},{Key=Environment,Value=dev},{Key=Owner,Value=you}]'
TV='ResourceType=volume,Tags=[{Key=Project,Value=payments},{Key=Environment,Value=dev},{Key=Owner,Value=you}]'
aws ec2 run-instances --dry-run --instance-type t3.micro \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --metadata-options HttpTokens=required --block-device-mappings 'DeviceName=/dev/xvda,Ebs={Encrypted=true}' \
  --tag-specifications "$TI" "$TV"
```
In zsh, **quote** tag specifications. Unquoted `[...]` is treated as a glob pattern.

---

## Results so far

| Area | Status |
|---|---|
| C2–C10, C15 (SCP tests) | ✅ All passed during Phase 5 |
| C11 | ✅ Validated: 77/77 digests and 1538/1540 logs valid; the 2 invalid are the Phase 4 experiment |
| C12, C13 | ✅ Aggregator covers both accounts; findings from both accounts in Security Hub |
| Full end-to-end run (#1–21) | ⏳ To do |

[⬅ Phase 6](06-security-services.md) · [Lab overview](../README.md) · [Phase 8 ➡](08-cleanup.md)
