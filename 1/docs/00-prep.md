# Phase 0 — Prep: Lock the Front Door

> **Mission:** make the account that will become your management account safe *before* it controls anything else.

[⬅ Lab overview](../README.md) · [Phase 1 ➡](01-organization.md)

---

## Why this matters

The management account will be able to create accounts, attach guardrails, and sign people into every account. If someone takes over its **root user**, they control the whole organization, and **SCPs never apply to the management account**. So we secure it first.

## What you'll set up

| Item | Why |
|---|---|
| Root MFA | The root user can do anything, including closing the account |
| No root access keys | Keys can leak; a root key leaking is game over |
| Budget alerts (C14) | A forgotten resource shouldn't surprise you at month end |
| Alternate contacts | AWS can reach security and billing contacts during an incident |
| AWS CLI | Every phase ends with CLI checks |
| Paid plan check | The newer AWS **Free plan** may block Organizations |

---

## Steps

1. **Check the account plan.** Billing → *Plan*, or:
   ```bash
   aws freetier get-account-plan-state   # want accountPlanType = PAID
   ```
   On the Free plan, upgrade to Paid. Your free credits still apply.
2. **Root MFA.** Sign in as root → IAM → *Assign MFA device* (passkey or authenticator app).
3. **Check that root has no access keys:**
   ```bash
   aws iam get-account-summary --query 'SummaryMap.{RootMFA:AccountMFAEnabled,RootKeys:AccountAccessKeysPresent}'
   # want RootMFA = 1, RootKeys = 0
   ```
4. **Budget.** Billing → Budgets → *Create budget* → monthly cost budget of **$10**, with email alerts at 50%, 80% and 100%, plus 100% *forecasted*. A budget in the management account covers **every** account in the org through consolidated billing.
5. **Alternate contacts.** Account → *Alternate contacts* → Security and Billing.
6. **CLI.** Configure admin credentials for the management account. From Phase 2 on, you'll switch to SSO.

## Verify

```bash
aws sts get-caller-identity                    # the right account?
aws budgets describe-budgets --account-id <MGMT_ID> --query 'Budgets[].[BudgetName,BudgetLimit.Amount]'
```

---

## 🔥 Field notes

> [!NOTE]
> **Free plan vs paid plan.** AWS accounts created after mid-2025 can start on a *Free plan* with credits. Some services, including Organizations, may be unavailable until you upgrade. `aws freetier get-account-plan-state` shows the plan and the remaining credits.

> [!TIP]
> **One free tier for the whole org.** With consolidated billing, the free-tier allowance is shared across all accounts. Creating more accounts does **not** give you more free usage.

---

## 🎤 Interview corner

<details><summary>Why shouldn't you run workloads in the management account?</summary>

SCPs never apply to it, so no guardrail can protect it. It already holds the most powerful permissions in the org (creating accounts, attaching policies, SSO for everyone). Keep it small: Organizations, Identity Center, billing, and the org trail.
</details>

<details><summary>What's the first thing you do with a brand-new AWS account?</summary>

Turn on MFA for root, make sure root has no access keys, set alternate contacts, create a budget alarm, then stop using root. All daily work goes through federated, short-lived roles.
</details>

---

**Terraform:** the budget is in [`terraform/organization/budget.tf`](../terraform/organization/budget.tf). Root MFA can't be automated; that's by design.

[⬅ Lab overview](../README.md) · [Phase 1 ➡](01-organization.md)
