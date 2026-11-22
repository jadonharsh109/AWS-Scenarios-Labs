# Phase 8 — Cleanup: Stop the Meter

> **Mission:** remove what costs money first, then everything else, in an order that doesn't leave orphans.

[⬅ Phase 7](07-validation.md) · [Lab overview](../README.md)

---

## Pausing for the day vs finishing the lab

| | Pause (keep your work) | Finish (delete everything) |
|---|---|---|
| Delete the 3 **interface endpoints** | ✅ | ✅ |
| Everything else | Keep (≈ $0 idle) | Delete (steps below) |

The interface endpoints are the only thing billing by the hour (~$0.72/day). Recreate them later with the same settings; private DNS makes the app work again with no code change.

## Steps (finish)

| # | What | Why this order |
|---|---|---|
| 1 | VPC → Endpoints → delete the **3 interface endpoints** | Stops the hourly cost first |
| 2 | API Gateway → delete `acme-genai-api` | Nothing can call the Lambda any more |
| 3 | Lambda → delete `acme-genai-chat`; IAM → delete `acme-genai-chat-role` | Lambda's ENIs are released after a few minutes |
| 4 | CloudShell → delete the **VPC environment** | Its ENI blocks subnet deletion |
| 5 | DynamoDB → delete `acme-genai-chat-history` | |
| 6 | Bedrock → Knowledge Base → delete data source, then `acme-hr-kb` | Choose to delete the vector data too |
| 7 | S3 Vectors → delete index, then vector bucket | If the KB didn't remove them |
| 8 | Bedrock → Guardrails → delete `acme-hr-guardrail` | |
| 9 | Bedrock → Settings → **turn off** model invocation logging | Account-wide setting; easy to forget |
| 10 | S3 → empty and delete docs and invocation-log buckets; CloudWatch → delete log groups | |
| 11 | VPC → delete gateway endpoints, security groups, subnets, route table, VPC | ENIs from steps 3–4 must be gone first |
| 12 | 🅰️ delete the trail and its bucket if you made one for this lab | |
| 13 | 🅱️ optional: close `genai-dev` (Organizations → move to **Suspended** → close account) | Closed accounts count against the quota for 90 days |

## Verify

```bash
aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[?VpcEndpointType==`Interface`].VpcEndpointId'   # []
aws bedrock get-model-invocation-logging-configuration                                                 # empty
aws bedrock-agent list-knowledge-bases --query 'knowledgeBaseSummaries[].name'                         # []
```

Check **Billing → Bills** the next day for leftover `VpcEndpoint-Hours`.

---

## 🔥 Field notes

*Added during the build.*

---

**Terraform:** destroy in reverse: `app` → `audit` → `knowledge-base` → `endpoints` → `network`. During the build, `terraform destroy` on `endpoints` alone is the daily "pause" button.

[⬅ Phase 7](07-validation.md) · [Lab overview](../README.md)
