# Phase 8 — Cleanup: Tear It Down in the Right Order

> **Mission:** remove everything that costs money, without getting stuck on your own guardrails.

[⬅ Phase 7](07-validation.md) · [Lab overview](../README.md)

---

## Why order matters

Everything you built protects itself:
- **C7** blocks disabling security services.
- **C15** blocks changing the log bucket.
- **Object Lock** blocks deleting logs.
- A **delegated admin** can't disable its own service.

Do the cleanup **as the break-glass role** (`OrganizationAccountAccessRole`, through *Switch role* from an SSO admin session in management), or detach the SCPs first.

> [!TIP]
> **Want to keep the foundation for Lab 2?** Do only step 1. Organizations, Identity Center and SCPs are free; the org trail costs nothing; the KMS key is about $1/month.

## Steps

### 1 · Security services: the ones that cost money

| Order | Where | Action |
|---|---|---|
| a | security | Security Hub CSPM → Configuration → set the policy to *Security Hub disabled* (or disassociate Root); then *stop central configuration* |
| b | management | Remove the **Security Hub** delegated admin (all regions at once) |
| c | security (break-glass) | Disable Security Hub CSPM in **every** region. Check them all; the admin had hubs in 17. |
| d | security | GuardDuty → Accounts → disassociate members; auto-enable → off |
| e | management | Remove the **GuardDuty** delegated admin |
| f | security (break-glass) | GuardDuty → Settings → Disable |
| g | management | Disable GuardDuty if it's still enabled as a member |
| h | security | Delete the Config aggregator and the Access Analyzer |
| i | both accounts | Config → stop the recorder, delete the delivery channel and the bucket |
| j | management | Deregister the Config and Access Analyzer delegated admins |

### 2 · Logging
1. Management → CloudTrail → delete `org-trail`.
2. **Detach `protect-baseline`** from Root (C15 would block the bucket changes), or use the break-glass role.
3. Wait for Object Lock retention to pass (1 day), then empty the bucket (all versions and delete markers) and delete it.
4. KMS → schedule key deletion (7-day minimum waiting period).

### 3 · Guardrails and accounts
1. Detach the SCPs, tag policy and EC2 policy.
2. Close the security account (Organizations → account → *Close*). Closed accounts stay **suspended for 90 days**, and only a limited number can be closed per 30 days.
3. Optional: delete the Identity Center users, groups and permission sets, then the organization.

## Verify nothing is left running

```bash
for r in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  echo "$r GD=$(aws guardduty list-detectors --region $r --query 'length(DetectorIds)') \
SH=$(aws securityhub describe-hub --region $r >/dev/null 2>&1 && echo on || echo off)"
done
```
Run it in **both** accounts. The break-glass role can see every region; your SSO role can't, because of C5.

---

**Terraform:** destroy in reverse order: `guardrails` → `security` → `logging` → `identity-center` → `organization` → `bootstrap`. See [terraform/README.md](../terraform/README.md#cleanup).

[⬅ Phase 7](07-validation.md) · [Lab overview](../README.md)
