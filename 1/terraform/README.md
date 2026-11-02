# Lab 1 — Terraform

This builds the whole Lab 1 landing zone (Phases 0–6) in a **fresh AWS account**, which becomes the management account. The result has **2 accounts**: management and security.

```
terraform/
├── bootstrap/         S3 bucket for remote state (local state, run once)
├── organization/      Org, OUs (Security, Workloads, Suspended), security account, root access mgmt, budget
├── identity-center/   Groups, users, permission sets, account assignments
├── logging/           Org CloudTrail (management) + log bucket & KMS key (security)
├── security/          Delegated admins, GuardDuty, Security Hub central config, Config, Access Analyzer
├── guardrails/        SCPs, tag policy, EC2 policy — documents read from ../policies
└── modules/
    └── config-recorder/   Config recorder + delivery bucket for one account (used twice by security/)
```

Each folder is a separate **stack** with its own state file. Stacks are kept small so that a mistake in one cannot destroy resources in another. Each stack's configuration lives in `terraform.tfvars`, not in the code. Real values (emails, names, IDs) stay out of git: only the `*.example` files are committed.

## Design choices

| Choice | Why |
|---|---|
| Remote state in S3 with `use_lockfile = true` | Native S3 locking (Terraform ≥ 1.10), so no DynamoDB table is needed |
| Partial backend config (`backend.hcl`) | The same code works for any account or bucket |
| `prevent_destroy` on the org, accounts, state bucket and log bucket | A stray `terraform destroy` cannot delete the landing zone or the audit trail |
| `close_on_deletion = false` | Removing an account from tfvars never closes it. Closing an account is always a deliberate manual step |
| SSE-S3 instead of a KMS key for state and Config buckets | No monthly KMS charge on a free-credit account |
| Assignments to missing accounts are skipped | Adding a workload account later only needs `organization` + `identity-center` re-applied |
| `default_tags` on every stack | `Lab`, `Stack`, `Owner` and `ManagedBy` are applied everywhere automatically |
| Two providers in `logging` and `security` (default + `aws.security` via `OrganizationAccountAccessRole`) | One stack owns both sides of a cross-account setup. The role is exempt from the SCPs (C5, C7, C15), so Terraform can manage protected resources. |
| Policies built from known names, not resource attributes | Bucket and key policies are fully visible in `terraform plan` for review |
| `guardrails` reads `../policies/*.json` | The console walkthrough and Terraform use the same policy files. The JSON is minified on the way in, to fit the 5,120-character SCP limit. |
| Targets referenced by name (`Root`, OU or account name) | tfvars reads like the architecture diagram. A validation rule enforces the 5-SCPs-per-target limit. |
| GuardDuty paid plans pinned `DISABLED` / `NONE` | Cost control is in code, not only in the console |
| Security Hub **central configuration** with `NO_REGIONS` aggregator | One policy on Root decides for every account. Home region only. |
| `config-recorder` module | Config has no org-wide auto-enable, so every account needs a recorder. One module, called once per account. |

## What Terraform can't do (manual steps)

| Step | When | How |
|---|---|---|
| Root user MFA on the management account | Before anything else | Console, signed in as root |
| Enable IAM Identity Center | After `organization`, before `identity-center` | Console → IAM Identity Center → Enable (it uses the organization instance) |
| Enforce MFA in Identity Center (C1) | Same time | Settings → Authentication → MFA: *Every time they sign in* + *Require them to register an MFA device at sign in* |
| Account-level S3 Block Public Access + EBS default encryption | Before `guardrails` | Must be ON before the SCPs lock them (or add `aws_s3_account_public_access_block` / `aws_ebs_encryption_by_default` per account) |
| Account quota increase | Only for workload accounts beyond the 2-account design | `aws service-quotas request-service-quota-increase --service-code organizations --quota-code L-E619E033 --desired-value 10 --region us-east-1` |

## Prerequisites

- Terraform ≥ 1.10 and AWS CLI v2.
- Admin credentials for the management account. After Identity Center is set up, switch to an SSO profile.

## Apply order

```bash
# 1. Bootstrap — creates the state bucket
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # edit values
terraform init && terraform apply
terraform output state_bucket_name

# 2. Organization (also grants trusted access to every service used later)
cd ../organization
cp terraform.tfvars.example terraform.tfvars   # set real emails
cp backend.hcl.example backend.hcl             # set bucket name
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan && terraform apply tfplan
terraform output account_ids                   # security account ID for later stacks

# 3. Manual: enable Identity Center + MFA setting (see table above)

# 4–6. Same pattern for each stack: copy the examples, init, plan, apply
for stack in identity-center logging security; do
  cd ../$stack
  cp terraform.tfvars.example terraform.tfvars  # logging & security: set security_account_id
  cp backend.hcl.example backend.hcl
  terraform init -backend-config=backend.hcl
  terraform plan -out=tfplan && terraform apply tfplan
done

# 7. Manual: account-level S3 BPA + EBS default encryption in every account

# 8. Guardrails — apply LAST, because protect-baseline (C7, C15) protects what the earlier stacks built
cd ../guardrails
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan && terraform apply tfplan
```

**Adding a workload account later** (after a quota increase):
1. Add it to `organization/terraform.tfvars` with `ou = "Workloads"` and apply. It immediately inherits `workload-guardrails` and `workload-tags`. GuardDuty (auto-enable ALL) and Security Hub (policy on Root) enroll it automatically.
2. Add a Config recorder for it: a third `module "config_..."` block in `security/config.tf` with its own provider.
3. Add its assignments (e.g. `Payments-Devs` → `PowerUserAccess`) in `identity-center` and apply.

## Verify

```bash
aws organizations list-accounts --query 'Accounts[].[Name,Id,Status]' --output table
aws organizations list-delegated-administrators --query 'DelegatedAdministrators[].Id'
aws cloudtrail get-trail-status --name org-trail --query '[IsLogging,LatestDeliveryError]'
terraform -chdir=guardrails output attachments
terraform -chdir=security output
```

Then run the [Phase 7 test matrix](../docs/07-validation.md) as an SSO user in the security account.

## Cleanup

`prevent_destroy` blocks `terraform destroy` on the org, accounts, state bucket and log bucket. This is intentional. Destroy in **reverse order**:

1. `guardrails`: removes C7/C15 first, so nothing blocks the rest.
2. `security`: Terraform runs as the break-glass role, so it can remove the delegation and services. Set `force_destroy_bucket = true` in the module calls first if the Config buckets aren't empty.
3. `logging`: `terraform destroy -target=aws_cloudtrail.org`. Wait for Object Lock retention, empty the bucket (all versions and delete markers), remove `prevent_destroy`, then destroy the rest. The KMS key is deleted after a 7-day waiting period.
4. `identity-center`.
5. Close the security account in the console, then `terraform state rm 'aws_organizations_account.this["security"]'`.
6. `organization` (remove `prevent_destroy`), then `bootstrap` (empty the bucket, remove `prevent_destroy`).

See [Phase 8](../docs/08-cleanup.md) for why the order matters.

## Adopting the manually-built setup

If you built Lab 1 by hand, don't recreate anything. Add `import` blocks to each stack and run `terraform plan` until it shows no changes:

```hcl
# organization
import {
  to = aws_organizations_organization.this
  id = "o-xxxxxxxxxx"
}
import {
  to = aws_organizations_organizational_unit.top_level["Security"] # also Workloads, Suspended
  id = "ou-xxxx-xxxxxxxx"
}
import {
  to = aws_organizations_account.this["security"]
  id = "<SECURITY_ID>"
}

# logging
import {
  to = aws_cloudtrail.org
  id = "arn:aws:cloudtrail:us-east-1:<MGMT_ID>:trail/org-trail"
}
import {
  to = aws_s3_bucket.logs # repeat for each aws_s3_bucket_* resource, same id
  id = "acme-org-cloudtrail-<SECURITY_ID>"
}
import {
  to = aws_kms_key.cloudtrail
  id = "<KEY_ID>"
}

# security — set create_config_service_linked_roles = false (the console already created them)
import {
  to = aws_guardduty_detector.security
  id = "<DETECTOR_ID>"
}
import {
  to = aws_guardduty_organization_admin_account.security
  id = "<SECURITY_ID>"
}
import {
  to = aws_securityhub_account.security
  id = "<SECURITY_ID>"
}
import {
  to = aws_securityhub_configuration_policy.baseline # console name differs; Terraform renames it
  id = "<POLICY_ID>"
}
import {
  to = aws_organizations_delegated_administrator.config["config.amazonaws.com"]
  id = "<SECURITY_ID>/config.amazonaws.com"
}
import {
  to = module.config_management.aws_config_configuration_recorder.this
  id = "default"
}
import {
  to = aws_accessanalyzer_analyzer.org
  id = "org-external-access"
}

# guardrails — the console-created policy keeps its ID; Terraform renames it in place
import {
  to = aws_organizations_policy.this["deny-leave-org"]
  id = "p-xxxxxxxx" # DenyLeaveAndCloseAccount
}
import {
  to = aws_organizations_policy_attachment.this["deny-leave-org/Root"]
  id = "r-xxxx:p-xxxxxxxx"
}
```

The pattern is the same for every resource. A read-only `plan` of each stack against the live lab environment resolves every target and assumes the cross-account role correctly.
