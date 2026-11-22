# Phase 0 — Prep: An Account Where Bedrock Actually Works

> **Mission:** pick where Lab 2 runs, make sure Bedrock can really be called there, and put a cost alarm in place before anything else.

[⬅ Lab overview](../README.md) · [Phase 1 ➡](01-network.md)

---

## Why this matters

Bedrock is the one service in this lab you can't fully control. A fresh account can have **every model quota set to 0**, and a region SCP can silently block newer models. Finding that out in Phase 5, with a VPC, endpoints and a Lambda already built, wastes days. So we prove that a model call works **first**.

## Pick your path

| | 🅰️ Standalone | 🅱️ On top of Lab 1 |
|---|---|---|
| Account | Any AWS account you own (Paid plan) | New `genai-dev` account in the **Workloads OU** |
| Sign-in | Your usual admin role / SSO | Lab 1 Identity Center (Platform-Admins → AdministratorAccess) |
| Budget | Create one (step 2) | Already covered by the Lab 1 budget |
| Guardrails | None | Lab 1 SCPs apply: region restriction, no IAM users, protected security services |

---

## Steps

### 1 · The account
**🅰️** Use your account. Check it's on the Paid plan (`aws freetier get-account-plan-state`).

**🅱️**
1. Management → Organizations → **Add an AWS account** → name `genai-dev`, email like `you+genai-dev@gmail.com`.
2. Move it into **Workloads**. It inherits `workload-guardrails` and `workload-tags` at once.
3. Identity Center → AWS accounts → `genai-dev` → **Assign users or groups** → `Platform-Admins` → `AdministratorAccess`.
4. Add a CLI profile:
   ```ini
   [profile acme-genai]
   sso_session = <your-session>
   sso_account_id = <GENAI_ID>
   sso_role_name = AdministratorAccess
   region = us-east-1
   ```

> [!NOTE]
> Lab 1's account quota is 2 by default. Check with `aws service-quotas get-service-quota --service-code organizations --quota-code L-E619E033 --region us-east-1`. If it's still 2, request 10 and use the `security` account meanwhile (works, but not best practice).

### 2 · Budget (🅰️ only)
Billing → Budgets → monthly cost budget **$10**, alerts at 50/80/100% actual and 100% forecasted.

### 3 · Bedrock quotas
Quotas are **per account and per region**. Check the two models we use:
```bash
aws service-quotas list-service-quotas --service-code bedrock --region us-east-1 \
  --query 'Quotas[?contains(QuotaName,`On-demand`) && (contains(QuotaName,`Nova Micro`) || contains(QuotaName,`Titan Text Embeddings V2`))].[QuotaName,Value]' \
  --output table
```
If any value is **0**, request an increase:
- **Service Quotas** → Amazon Bedrock → the quota → *Request increase at account level* (requests/min **10**, tokens/min **10,000**)
- Not adjustable? **Support → Create case → Account and billing → Service: Account → Category: Other Account Issues → Severity: General question.** List the quota names and codes and say it's a low-volume learning project.

### 4 · Model access
Amazon's own models (**Nova**, **Titan**) don't need an access request. Third-party models (e.g. Anthropic) ask for a one-time use-case form in the Bedrock console the first time.

### 5 · Smoke test: one real model call
```bash
aws bedrock-runtime converse --region us-east-1 \
  --model-id amazon.nova-micro-v1:0 \
  --messages '[{"role":"user","content":[{"text":"Say hi in 3 words"}]}]' \
  --query 'output.message.content[0].text' --output text
```
You want a short greeting. Anything else, see the field notes below.

### 6 · 🅱️ Region SCP vs cross-region inference
Many models are offered through **inference profiles** such as `us.amazon.nova-micro-v1:0`. Bedrock may serve the call from **another region** (us-east-2, us-west-2). Lab 1's `region-restriction` SCP sees `bedrock:InvokeModel` in `us-west-2` and denies it, even though you called `us-east-1`.

**Choice for this lab:** use **in-region on-demand model IDs** (`amazon.nova-micro-v1:0`, `amazon.titan-embed-text-v2:0`). No SCP change needed.

**If you need a cross-region model later**, don't remove the region SCP. Give Bedrock invocation its own, narrower region list:
1. Add `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` to the `NotAction` list of `region-restriction`.
2. Add a second statement that denies those two actions outside the profile's regions:
   ```json
   {
     "Sid": "C5BedrockInferenceRegions",
     "Effect": "Deny",
     "Action": ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
     "Resource": "*",
     "Condition": {
       "StringNotEquals": { "aws:RequestedRegion": ["us-east-1", "us-east-2", "us-west-2", "ap-south-1"] },
       "ArnNotLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/OrganizationAccountAccessRole" }
     }
   }
   ```
3. Validate with `aws accessanalyzer validate-policy --policy-type SERVICE_CONTROL_POLICY` before attaching.

## Verify

```bash
aws sts get-caller-identity                     # the Lab 2 account?
aws bedrock-runtime converse ...                # step 5 returns text
aws budgets describe-budgets --account-id <PAYER_ID> --query 'Budgets[].BudgetName'
```

---

## 🔥 Field notes

> [!WARNING]
> **`ValidationException: Operation not allowed`, in every account.** The first Nova Micro call failed in both Lab 1 accounts. It wasn't IAM and it wasn't an SCP: those say `AccessDenied`. Service Quotas showed the real cause:
> ```
> On-demand model inference tokens per minute for Amazon Nova Micro    0.0
> On-demand model inference requests per minute for Amazon Nova Micro  0.0
> ```
> New and credit-based accounts can start with Bedrock quotas at **0**. Raise them (step 3) and wait. Build Phases 1–2 meanwhile; they don't need Bedrock.

> [!WARNING]
> **The region SCP blocked a model we called in `us-east-1`.** Trying the inference profile instead:
> ```
> not authorized to perform: bedrock:InvokeModel on resource:
> arn:aws:bedrock:us-west-2::foundation-model/amazon.nova-micro-v1:0
> with an explicit deny in a service control policy
> ```
> Note the **us-west-2** in the resource: the profile routed the call there, and Lab 1's C5 did exactly its job. Step 6 explains the fix.

---

## 🎤 Interview corner

<details><summary>What is cross-region inference, and what does it mean for governance?</summary>

An inference profile (e.g. `us.…` or `global.…`) lets Bedrock serve a request from several regions to get more capacity. Your data stays in the profile's geography but may be **processed** in a region you didn't call. IAM and SCPs are evaluated for the destination region too, so region guardrails have to list those regions, and data-residency rules have to accept them.
</details>

<details><summary>"AccessDenied" vs "Operation not allowed" — what's the difference?</summary>

`AccessDenied` is an authorization decision (IAM, SCP, resource policy) and usually names the policy type. `ValidationException: Operation not allowed` comes from the service itself: the account isn't allowed to use that operation at all, often because of a 0 quota or an account-level restriction. Fixing IAM won't help; Service Quotas or Support will.
</details>

---

**Terraform:** the 🅱️ account is one more entry in Lab 1's [`organization`](../../1/terraform/organization) tfvars (`ou = "Workloads"`) plus an assignment in [`identity-center`](../../1/terraform/identity-center). Quota requests and the support case stay manual.

[⬅ Lab overview](../README.md) · [Phase 1 ➡](01-network.md)
