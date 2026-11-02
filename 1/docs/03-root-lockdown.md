# Phase 3 — Root Lockdown: The Safest Password Is No Password

> **Mission:** member accounts have **no root credentials at all**, and the rare root-only task becomes a short, audited, single-purpose session. (Control **C3**, part 1)

[⬅ Phase 2](02-identity-center.md) · [Lab overview](../README.md) · [Phase 4 ➡](04-logging.md)

---

## Why this matters

Every AWS account has a root user that can do anything. With 50 accounts, that's 50 root passwords and 50 MFA devices to protect. **Centralized root access management** removes that burden:

| Feature | What it gives you |
|---|---|
| **Root credentials management** | See and *delete* root passwords, keys, MFA and certificates in member accounts, from the management account |
| **Privileged root actions** | When you truly need root (for example, a bucket policy that locked everyone out), the management account gets a **short root session** allowed to do one task only |

Accounts created through Organizations **start without root credentials**. This feature keeps it that way, and lets you check it.

---

## Steps

1. Sign in to the **management account** (SSO admin) → IAM → **Root access management** → **Enable**. Tick both features.
2. In the **Accounts** table, check your member account. Root password, access keys and MFA should all read **Not present**.
3. If something is present: select the account → **Take privileged action** → *Delete root user credentials*.

### What "Take privileged action" offers

| Option | Use it when |
|---|---|
| Delete S3 bucket policy | A bucket policy locked out everyone, admins included |
| Delete SQS queue policy | The same, for an SQS queue |
| Delete root user credentials | Credentials exist (only offered then) |
| **Allow password recovery** | ⚠️ Avoid. It re-enables root sign-in for the account. |

## Verify

```bash
aws iam list-organizations-features
# EnabledFeatures: ["RootSessions", "RootCredentialsManagement"]
```

---

## 🔥 Field notes

> [!NOTE]
> **"I don't see *Delete root user credentials*."** That's good news. The console only offers it when there's something to delete. Organizations-created accounts have nothing.

> [!WARNING]
> **"You must sign in using the management account…"** You were in the member account. The access portal lists both accounts, so pick **management**.

> [!TIP]
> **Root sessions from the CLI** use task-scoped policies:
> ```bash
> aws sts assume-root --target-principal <SECURITY_ID> \
>   --task-policy-arn arn=arn:aws:iam::aws:policy/root-task/IAMAuditRootUserCredentials
> ```
> In Phase 5, the C3 SCP denies *all* root activity in member accounts, root sessions included. For a break-glass root task, detach `protect-baseline` first, then reattach it.

---

## 🎤 Interview corner

<details><summary>How do you secure root across hundreds of accounts?</summary>

Centralized root access management: delete root credentials in every member account, run privileged tasks through short root sessions from the management account, and deny root use with an SCP. Only the management account's root keeps credentials, with hardware MFA, locked away.
</details>

<details><summary>Name a task that still needs root.</summary>

Deleting a bucket policy that denies everyone, including admins. Others: changing the account's support plan, and some billing tasks. Privileged root sessions cover the most common recovery cases without a root password.
</details>

---

**Terraform:** [`terraform/organization/root-access.tf`](../terraform/organization/root-access.tf) (`aws_iam_organizations_features`).

[⬅ Phase 2](02-identity-center.md) · [Lab overview](../README.md) · [Phase 4 ➡](04-logging.md)
