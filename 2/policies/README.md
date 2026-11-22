# Lab 2 policies

| File | Attach to | Control | Phase |
|---|---|---|---|
| [`endpoints/bedrock-runtime.json`](endpoints/bedrock-runtime.json) | `bedrock-runtime` interface endpoint | G4 approved models only | 2 |
| [`endpoints/bedrock-agent-runtime.json`](endpoints/bedrock-agent-runtime.json) | `bedrock-agent-runtime` interface endpoint | Our account's KBs only | 2 |
| [`endpoints/dynamodb.json`](endpoints/dynamodb.json) | DynamoDB gateway endpoint | Only the chat-history table | 2 |
| [`iam/lambda-chat-role.json`](iam/lambda-chat-role.json) | `acme-genai-chat-role` (inline) | G3, G7 | 5 |
| [`api/resource-policy.json`](api/resource-policy.json) | `acme-genai-api` resource policy | G2 | 5 |
| [`logging/invocation-log-bucket.json`](logging/invocation-log-bucket.json) | Invocation-log bucket | G6, G9 | 6 |
| [`s3/docs-bucket.json`](s3/docs-bucket.json) | Docs bucket | G9 | 3 |

## Placeholders

| Placeholder | Where to find it |
|---|---|
| `<ACCOUNT_ID>` | `aws sts get-caller-identity --query Account --output text` |
| `<KB_ID>` | Bedrock → Knowledge Bases (Phase 3) |
| `<GUARDRAIL_ID>` | Bedrock → Guardrails (Phase 4) |
| `<VPCE_BEDROCK_RUNTIME>`, `<VPCE_BEDROCK_AGENT_RUNTIME>`, `<VPCE_EXECUTE_API>` | VPC → Endpoints (Phase 2) |

```bash
sed -e "s/<ACCOUNT_ID>/$ACCOUNT_ID/g" -e "s/<KB_ID>/$KB_ID/g" iam/lambda-chat-role.json > /tmp/role.json
aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY --policy-document file:///tmp/role.json
```

## How G3 works

The Lambda role's `G3DenyBedrockOutsideEndpoint` denies Bedrock calls whose `aws:SourceVpce` isn't one of our endpoints. `aws:ViaAWSService = false` limits the deny to calls the Lambda makes **itself**. For `RetrieveAndGenerate`, the Knowledge Base then calls the model **on the Lambda's behalf**. That second call doesn't pass through our VPC endpoint, so without the exemption it would be denied and every question would fail.
