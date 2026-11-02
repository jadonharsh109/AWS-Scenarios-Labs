# ☁️ AWS Scenarios Labs

> **Learn AWS the way it's used at work:** start from a real business problem, build the solution click by click in the console, then rebuild it as production-grade Terraform.

Most tutorials teach one service at a time. Real jobs don't work like that. They start with *"an auditor is coming"* or *"thirty engineers share one IAM user"*. Each lab here starts with a scenario like that and ends with a working, tested AWS environment you understand well enough to explain in an interview.

---

## 🧪 How every lab works

| Step | What you do | Why |
|---|---|---|
| 📖 **Story** | Read the scenario: who the company is, what's broken, what leadership wants | Learn to start from requirements, not from services |
| 🖱️ **Manual build** | Follow the phase guides in the AWS console | See every setting, error message and default |
| ✅ **Validate** | Prove each control works with safe, repeatable tests | A control you haven't tested is a hope |
| 🏗️ **Terraform** | Rebuild the same thing as code (stacks, modules, remote state) | Turn understanding into something you can repeat |
| 🧹 **Cleanup** | Tear it down in the right order | Stay inside the free tier and budget |

Every phase guide also has:
- **🔥 Field notes:** real mistakes made while building the lab, and how they were fixed
- **🎤 Interview corner:** the questions this topic comes up in, with answers

---

## 📚 Labs

| # | Lab | Scenario | Key services | Status |
|---|---|---|---|---|
| 1 | [**Enterprise Landing Zone**](1/) | AcmeCorp moves from one shared account to a governed multi-account setup with SSO, guardrails and central security | Organizations · Identity Center · SCPs · CloudTrail · KMS · S3 Object Lock · GuardDuty · Security Hub · Config · Access Analyzer | ✅ Built · ⏳ validating |

*More labs coming. Each one gets its own numbered folder.*

### Lab 1 at a glance

**Two accounts. Fifteen compliance controls. One security console.**

```
Root ── guardrails: deny-leave-org · protect-baseline · region-restriction · ec2-baseline
├── 👑 Management      Organizations · Identity Center (SSO + MFA) · org CloudTrail · budget
├── 🛡️ Security OU     security account: immutable log bucket + GuardDuty · Security Hub · Config · Access Analyzer
├── 🚀 Workloads OU    ready for project accounts (no IAM users, encrypted, tagged, IMDSv2)
└── 🅿️ Suspended OU    deny-all
```

What you'll be able to explain afterwards:
- Why SCPs **never apply to the management account**, and how to test guardrails *safely*
- Why a versioned S3 bucket is **not** immutable (an admin really deleted a "locked" log file here)
- How Identity Center turns one login into **short-lived roles** in every account
- What a **delegated administrator** is, and why it can't disable itself

➡️ **[Start Lab 1](1/README.md)**

---

## 🧰 Before you start

- An AWS account you own on the **Paid plan**. Free credits still apply. Some labs need AWS Organizations, which the Free plan may block.
- **Root MFA** enabled and a **budget alert** set. Lab 1, Phase 0 walks you through both.
- AWS CLI v2 and Terraform ≥ 1.10
- Labs are designed to cost **a few dollars or less** if you clean up. Every lab lists its costs and has a cleanup phase.

> [!WARNING]
> Use a **dedicated learning account**, never a production or employer account. Labs create organization-wide policies that affect every account in the org.

---

## 📁 Repository layout

```
AWS-Scenarios-Labs/
├── README.md            ← you are here
└── 1/                   Lab 1 — Enterprise Landing Zone
    ├── README.md        story, architecture, controls, phase map
    ├── docs/            one guide per phase (steps · verify · field notes · interview corner)
    ├── policies/        SCP / tag / EC2 / KMS / bucket policies as JSON
    └── terraform/       the same lab as code (stacks + modules)
```
