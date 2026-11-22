#!/usr/bin/env bash
# Lab 1 — automated validation of the landing zone (Phase 7).
#
# Every write call here is SAFE: it either re-applies the current value,
# targets a resource that doesn't exist, or uses --dry-run. If a guardrail
# is missing, the call still changes nothing.
#
# Needs two AWS CLI profiles (Identity Center / SSO roles work best):
#   - a member-account admin (the security account) — the SCPs are tested against it
#   - a management-account admin — reads the org and attaches/detaches policies
# Run ./validate.sh --help for all options.

set -uo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Profiles
  -s, --sec-profile NAME     Member (security) account profile      [${SEC_PROFILE}]
  -m, --mgmt-profile NAME    Management account profile             [${MGMT_PROFILE}]
                             Pass "" to use the default credential chain.

Environment
  -r, --region REGION        Home region                            [${REGION}]
      --denied-region REGION A region the SCP must block (C5)       [${DENIED_REGION}]
      --trail NAME           Organization trail name                [${TRAIL_NAME}]
      --aggregator NAME      Config aggregator name                 [${AGGREGATOR}]
      --analyzer NAME        Access Analyzer (organization) name    [${ANALYZER}]

Extra tests
  -w, --attach-workload      Attach workload-guardrails to the member account,
                             run C2/C8/C9/C10, then detach it again
      --wait SECONDS         Wait after attaching, for the SCP to propagate [${WAIT}]
  -l, --validate-logs        Run cloudtrail validate-logs for the last 24 h (slow)

  -h, --help                 Show this help

Every option can also be set as an environment variable:
SEC_PROFILE, MGMT_PROFILE, REGION, DENIED_REGION, TRAIL_NAME, AGGREGATOR, ANALYZER, WAIT.

Examples
  $(basename "$0")
  $(basename "$0") -s my-member-admin -m my-mgmt-admin --region eu-central-1 --denied-region us-west-2
  $(basename "$0") --attach-workload --validate-logs
EOF
}

SEC_PROFILE="${SEC_PROFILE-acme-security}"
MGMT_PROFILE="${MGMT_PROFILE-acme-mgmt}"
REGION="${REGION:-us-east-1}"
DENIED_REGION="${DENIED_REGION:-eu-west-1}"
TRAIL_NAME="${TRAIL_NAME:-org-trail}"
AGGREGATOR="${AGGREGATOR:-org-aggregator}"
ANALYZER="${ANALYZER:-org-external-access}"
WAIT="${WAIT:-30}"
FAKE="scp-test-nonexistent"
FAKE_DETECTOR="00000000000000000000000000000000"
AMI="resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"

ATTACH_WORKLOAD=false
VALIDATE_LOGS=false

need_value() { [ $# -ge 2 ] || { echo "Option $1 needs a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --*=*) opt="${1%%=*}"; val="${1#*=}"; shift; set -- "$opt" "$val" "$@"; continue ;;
    -s|--sec-profile)    need_value "$@"; SEC_PROFILE="$2";   shift ;;
    -m|--mgmt-profile)   need_value "$@"; MGMT_PROFILE="$2";  shift ;;
    -r|--region)         need_value "$@"; REGION="$2";        shift ;;
    --denied-region)     need_value "$@"; DENIED_REGION="$2"; shift ;;
    --trail)             need_value "$@"; TRAIL_NAME="$2";    shift ;;
    --aggregator)        need_value "$@"; AGGREGATOR="$2";    shift ;;
    --analyzer)          need_value "$@"; ANALYZER="$2";      shift ;;
    --wait)              need_value "$@"; WAIT="$2";          shift ;;
    -w|--attach-workload) ATTACH_WORKLOAD=true ;;
    -l|--validate-logs)  VALIDATE_LOGS=true ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

case "$WAIT" in ''|*[!0-9]*) echo "--wait must be a number of seconds" >&2; exit 2 ;; esac
[ "$REGION" != "$DENIED_REGION" ] || { echo "--denied-region must differ from --region" >&2; exit 2; }

export AWS_PAGER="" AWS_DEFAULT_REGION="$REGION"

# ── Output ────────────────────────────────────────────────────────────────
if [ -t 1 ]; then G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
else G=""; R=""; Y=""; B=""; D=""; N=""; fi
PASSES=0; FAILS=0; WARNS=0; SKIPS=0

section() { printf '\n%s── %s ──%s\n' "$B" "$1" "$N"; }
pass()    { PASSES=$((PASSES+1)); printf '  %s✔ PASS%s  %-5s %s\n' "$G" "$N" "$1" "$2"; }
fail()    { FAILS=$((FAILS+1));   printf '  %s✘ FAIL%s  %-5s %s\n' "$R" "$N" "$1" "$2"
            [ -n "${3:-}" ] && printf '         %s%s%s\n' "$D" "$(echo "$3" | head -c 300 | tr '\n' ' ')" "$N"; }
warn()    { WARNS=$((WARNS+1));   printf '  %s! WARN%s  %-5s %s\n' "$Y" "$N" "$1" "$2"; }
skip()    { SKIPS=$((SKIPS+1));   printf '  %s- SKIP%s  %-5s %s\n' "$D" "$N" "$1" "$2"; }

# An empty profile name means "use the default credential chain" (env vars, instance role…)
sec()  { if [ -n "$SEC_PROFILE" ];  then aws --profile "$SEC_PROFILE" "$@";  else aws "$@"; fi; }
mgmt() { if [ -n "$MGMT_PROFILE" ]; then aws --profile "$MGMT_PROFILE" "$@"; else aws "$@"; fi; }

# ── Matchers ──────────────────────────────────────────────────────────────
# True when the output is an explicit SCP deny. EC2 hides the reason in an
# encoded message, so decode it and look for explicitDeny.
is_scp_deny() {
  local out="$1" encoded
  echo "$out" | grep -qi "explicit deny in a service control policy" && return 0
  encoded=$(echo "$out" | sed -n 's/.*Encoded authorization failure message: \([^ ]*\).*/\1/p' | head -1)
  [ -n "$encoded" ] || return 1
  sec sts decode-authorization-message --encoded-message "$encoded" \
      --query DecodedMessage --output text 2>/dev/null | grep -q '"explicitDeny":true'
}

# expect_scp_deny ID "description" aws-args...
expect_scp_deny() {
  local id="$1" desc="$2" out; shift 2
  out=$("$@" 2>&1)
  if is_scp_deny "$out"; then pass "$id" "$desc"
  else fail "$id" "$desc (expected an explicit SCP deny)" "$out"; fi
}

# expect_denied ID "description" aws-args...   (any AccessDenied is fine)
expect_denied() {
  local id="$1" desc="$2" out; shift 2
  out=$("$@" 2>&1)
  if echo "$out" | grep -qiE "AccessDenied|not authorized|UnauthorizedOperation"; then pass "$id" "$desc"
  else fail "$id" "$desc (expected access denied)" "$out"; fi
}

# expect_dryrun_ok ID "description" aws-args...
expect_dryrun_ok() {
  local id="$1" desc="$2" out; shift 2
  out=$("$@" 2>&1)
  if echo "$out" | grep -q "DryRunOperation"; then pass "$id" "$desc"
  else fail "$id" "$desc (expected DryRunOperation)" "$out"; fi
}

# eq ID "description" actual expected
eq() {
  if [ "$3" = "$4" ]; then pass "$1" "$2"
  else fail "$1" "$2 (got '$3', expected '$4')"; fi
}

# ── Org helpers (management profile) ─────────────────────────────────────
# policy_ids_for TARGET TYPE  → policy IDs attached directly to TARGET
policy_ids_for() {
  mgmt organizations list-policies-for-target --target-id "$1" --filter "$2" \
    --query 'Policies[].Id' --output text 2>/dev/null
}

# find_attached TARGET TYPE MARKER → ID of the attached policy whose content contains MARKER.
# Matches on content (e.g. a Sid), so it works whatever the policy was named in the console.
find_attached() {
  local id
  for id in $(policy_ids_for "$1" "$2"); do
    if mgmt organizations describe-policy --policy-id "$id" \
         --query Policy.Content --output text 2>/dev/null | grep -q "$3"; then
      echo "$id"; return 0
    fi
  done
  return 1
}

check_attached() {   # check_attached ID "description" TARGET TYPE MARKER
  if find_attached "$3" "$4" "$5" >/dev/null; then pass "$1" "$2"
  else fail "$1" "$2 (no $4 containing '$5' attached)"; fi
}

# ══ Preflight ═════════════════════════════════════════════════════════════
section "Preflight"

SEC_ARN=$(sec sts get-caller-identity --query Arn --output text 2>&1) || {
  echo "${R}Cannot use member profile '${SEC_PROFILE:-default}':${N} $SEC_ARN"
  echo "Log in (e.g. aws sso login --profile ${SEC_PROFILE:-<name>}) or pass --sec-profile"; exit 1; }
mgmt sts get-caller-identity >/dev/null 2>&1 || {
  echo "${R}Cannot use management profile '${MGMT_PROFILE:-default}'.${N}"
  echo "Log in (e.g. aws sso login --profile ${MGMT_PROFILE:-<name>}) or pass --mgmt-profile"; exit 1; }

SEC_ID=$(sec sts get-caller-identity --query Account --output text)
MGMT_ID=$(sec organizations describe-organization --query Organization.MasterAccountId --output text)
ROOT_ID=$(mgmt organizations list-roots --query 'Roots[0].Id' --output text)
ou_id() {
  mgmt organizations list-organizational-units-for-parent --parent-id "$ROOT_ID" \
    --query "OrganizationalUnits[?Name=='$1'].Id | [0]" --output text
}
WORKLOADS_OU=$(ou_id Workloads)
SUSPENDED_OU=$(ou_id Suspended)

# SCPs never apply to the management account or to the break-glass role.
# Testing as either would make every guardrail look broken.
if [ "$SEC_ID" = "$MGMT_ID" ]; then
  echo "${R}$SEC_PROFILE points at the management account — SCPs don't apply there.${N}"; exit 1
fi
case "$SEC_ARN" in
  *assumed-role/AWSReservedSSO_*) pass "-" "Testing as an Identity Center role in a member account" ;;
  *OrganizationAccountAccessRole*) echo "${R}OrganizationAccountAccessRole is exempt from the SCPs. Use an SSO profile.${N}"; exit 1 ;;
  *) warn "-" "Caller is not an Identity Center role ($SEC_ARN)" ;;
esac

TRAIL_JSON=$(mgmt cloudtrail describe-trails --trail-name-list "$TRAIL_NAME" --output json 2>/dev/null)
TRAIL_ARN=$(echo "$TRAIL_JSON"  | sed -n 's/.*"TrailARN": "\([^"]*\)".*/\1/p' | head -1)
LOG_BUCKET=$(echo "$TRAIL_JSON" | sed -n 's/.*"S3BucketName": "\([^"]*\)".*/\1/p' | head -1)
[ -n "$TRAIL_ARN" ] || { echo "${R}Trail '$TRAIL_NAME' not found in the management account.${N}"; exit 1; }
echo "  ${D}member=${SEC_PROFILE:-default} ($SEC_ID)  mgmt=${MGMT_PROFILE:-default}  region=$REGION${N}"
echo "  ${D}root=$ROOT_ID  workloads=$WORKLOADS_OU  suspended=$SUSPENDED_OU  bucket=$LOG_BUCKET${N}"

# ══ 1. Policy attachments ═════════════════════════════════════════════════
section "Organization policies are attached where the design says"

# Matches the action, not the Sid: a policy created in the console has no Sid
check_attached C6  "Root: deny leaving the org / closing accounts"  "$ROOT_ID" SERVICE_CONTROL_POLICY organizations:LeaveOrganization
check_attached C3  "Root: protect-baseline (root user, BPA, security services, log bucket)" \
                                                                    "$ROOT_ID" SERVICE_CONTROL_POLICY C3DenyRootUser
check_attached C5  "Root: region restriction"                       "$ROOT_ID" SERVICE_CONTROL_POLICY C5DenyOutsideApprovedRegions
check_attached C9  "Root: EC2 declarative policy (IMDSv2, BPA)"    "$ROOT_ID" DECLARATIVE_POLICY_EC2 instance_metadata_defaults
check_attached C2  "Workloads OU: workload-guardrails"              "$WORKLOADS_OU" SERVICE_CONTROL_POLICY C2DenyIamUsersAndKeys
check_attached C10 "Workloads OU: tag policy"                       "$WORKLOADS_OU" TAG_POLICY '"Project"'
check_attached "-" "Suspended OU: deny-all"                         "$SUSPENDED_OU" SERVICE_CONTROL_POLICY SuspendedDenyAll

FEATURES=$(mgmt iam list-organizations-features --query EnabledFeatures --output text 2>&1)
if echo "$FEATURES" | grep -q RootCredentialsManagement && echo "$FEATURES" | grep -q RootSessions; then
  pass C3 "Centralized root access: RootCredentialsManagement + RootSessions enabled"
else fail C3 "Centralized root access not fully enabled" "$FEATURES"; fi

# ══ 2. Account baseline settings ══════════════════════════════════════════
section "Account baseline (security account)"

BPA=$(sec s3control get-public-access-block --account-id "$SEC_ID" \
  --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' \
  --output text 2>&1 | tr -s '\t ' ' ')
eq C4 "Account-level S3 Block Public Access: all four ON" "$BPA" "True True True True"
eq C8 "EBS encryption by default" \
  "$(sec ec2 get-ebs-encryption-by-default --query EbsEncryptionByDefault --output text 2>&1)" "True"

IMDS=$(sec ec2 get-instance-metadata-defaults --query 'AccountLevel.[HttpTokens,ManagedBy]' --output text 2>&1 | tr -s '\t ' ' ')
eq C9 "IMDS defaults: HttpTokens required, managed by declarative policy" "$IMDS" "required declarative-policy"
eq C9 "Snapshot block public access" \
  "$(sec ec2 get-snapshot-block-public-access-state --query State --output text 2>&1)" "block-all-sharing"
eq C9 "AMI block public access" \
  "$(sec ec2 get-image-block-public-access-state --query ImageBlockPublicAccessState --output text 2>&1)" "block-new-sharing"
eq C9 "EC2 serial console access disabled" \
  "$(sec ec2 get-serial-console-access-status --query SerialConsoleAccessEnabled --output text 2>&1)" "False"

# ══ 3. SCP denials — protect-baseline + region restriction ════════════════
section "SCP denials (as an admin in the security account)"

# C4: re-apply the current values — a no-op even if the SCP were missing
if [ "$BPA" = "True True True True" ]; then
  expect_scp_deny C4 "Change account-level S3 Block Public Access" \
    sec s3control put-public-access-block --account-id "$SEC_ID" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
else skip C4 "BPA isn't fully ON, so re-applying it would not be a no-op"; fi

expect_scp_deny C5 "Use a non-approved region ($DENIED_REGION)" \
  sec ec2 describe-vpcs --region "$DENIED_REGION"

# C7: fake targets — nothing real can be stopped or deleted
expect_scp_deny C7 "GuardDuty: delete detector"            sec guardduty delete-detector --detector-id "$FAKE_DETECTOR"
expect_scp_deny C7 "Config: stop recorder"                 sec configservice stop-configuration-recorder --configuration-recorder-name "$FAKE"
expect_scp_deny C7 "Config: delete aggregator"             sec configservice delete-configuration-aggregator --configuration-aggregator-name "$FAKE"
expect_scp_deny C7 "Access Analyzer: delete analyzer"      sec accessanalyzer delete-analyzer --analyzer-name "$FAKE"
expect_scp_deny C7 "CloudTrail: stop logging (local trail)" sec cloudtrail stop-logging --name "$FAKE"
expect_denied   C7 "CloudTrail: stop the org trail from a member account" \
  sec cloudtrail stop-logging --name "$TRAIL_ARN"

# C15: re-apply current bucket settings; DeleteBucket fails on a non-empty bucket anyway
if [ -n "$LOG_BUCKET" ]; then
  if [ "$(sec s3api get-bucket-versioning --bucket "$LOG_BUCKET" --query Status --output text 2>/dev/null)" = "Enabled" ]; then
    expect_scp_deny C15 "Log bucket: change versioning" \
      sec s3api put-bucket-versioning --bucket "$LOG_BUCKET" --versioning-configuration Status=Enabled
  else skip C15 "Versioning not readable/enabled — not re-applying"; fi

  LOCK=$(sec s3api get-object-lock-configuration --bucket "$LOG_BUCKET" --query ObjectLockConfiguration --output json 2>/dev/null)
  if [ -n "$LOCK" ]; then
    expect_scp_deny C15 "Log bucket: change Object Lock configuration" \
      sec s3api put-object-lock-configuration --bucket "$LOG_BUCKET" --object-lock-configuration "$LOCK"
  else skip C15 "Object Lock configuration not readable"; fi

  POLICY=$(sec s3api get-bucket-policy --bucket "$LOG_BUCKET" --query Policy --output text 2>/dev/null)
  if [ -n "$POLICY" ]; then
    expect_scp_deny C15 "Log bucket: replace the bucket policy" \
      sec s3api put-bucket-policy --bucket "$LOG_BUCKET" --policy "$POLICY"
  else skip C15 "Bucket policy not readable"; fi

  expect_scp_deny C15 "Log bucket: delete the bucket" sec s3api delete-bucket --bucket "$LOG_BUCKET"
else skip C15 "Log bucket name unknown"; fi

# ══ 4. Workload guardrails (C2, C8, C9, C10) ══════════════════════════════
section "Workload guardrails"

WG_ID=$(find_attached "$WORKLOADS_OU" SERVICE_CONTROL_POLICY C2DenyIamUsersAndKeys)
ALREADY=$(find_attached "$SEC_ID" SERVICE_CONTROL_POLICY C2DenyIamUsersAndKeys)
ATTACHED_BY_US=false

detach_workload() {
  if $ATTACHED_BY_US; then
    mgmt organizations detach-policy --policy-id "$WG_ID" --target-id "$SEC_ID" \
      && echo "  ${D}workload-guardrails detached from the security account again${N}" \
      || echo "  ${R}Could not detach $WG_ID from $SEC_ID — detach it manually!${N}"
    ATTACHED_BY_US=false
  fi
}
trap detach_workload EXIT
trap 'detach_workload; exit 130' INT TERM

if [ -z "$ALREADY" ] && $ATTACH_WORKLOAD && [ -n "$WG_ID" ]; then
  mgmt organizations attach-policy --policy-id "$WG_ID" --target-id "$SEC_ID" && ATTACHED_BY_US=true
  echo "  ${D}Attached workload-guardrails to the security account; waiting ${WAIT} s to propagate…${N}"
  sleep "$WAIT"
fi

if [ -n "$ALREADY" ] || $ATTACHED_BY_US; then
  TAGS='{Key=Project,Value=payments},{Key=Environment,Value=dev},{Key=Owner,Value=lab1-test}'
  TI="ResourceType=instance,Tags=[$TAGS]"
  TV="ResourceType=volume,Tags=[$TAGS]"

  # Non-existent user: if the SCP were missing, IAM would just say NoSuchEntity
  expect_scp_deny C2  "IAM: create access key"     sec iam create-access-key --user-name "$FAKE"
  expect_scp_deny C2  "IAM: create console login"  sec iam create-login-profile --user-name "$FAKE" --password 'Not-Used-1!'

  expect_scp_deny C10 "EC2: launch without tags" \
    sec ec2 run-instances --dry-run --instance-type t3.micro --image-id "$AMI" \
    --metadata-options HttpTokens=required
  expect_scp_deny C9  "EC2: launch with IMDSv1 allowed" \
    sec ec2 run-instances --dry-run --instance-type t3.micro --image-id "$AMI" \
    --metadata-options HttpTokens=optional --tag-specifications "$TI" "$TV"

  OUT=$(sec ec2 create-volume --dry-run --availability-zone "${REGION}a" --size 1 --no-encrypted \
        --tag-specifications "$TV" 2>&1)
  if is_scp_deny "$OUT"; then pass C8 "EC2: create unencrypted volume"
  elif echo "$OUT" | grep -q DryRunOperation; then
    # Default EBS encryption turns the request into an encrypted one before the SCP sees it
    warn C8 "Unencrypted volume not denied by SCP — EBS default encryption encrypts it anyway"
  else fail C8 "EC2: create unencrypted volume" "$OUT"; fi

  expect_dryrun_ok "✓" "EC2: compliant launch (tags + IMDSv2 + encrypted) would succeed" \
    sec ec2 run-instances --dry-run --instance-type t3.micro --image-id "$AMI" \
    --metadata-options HttpTokens=required \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={Encrypted=true}' \
    --tag-specifications "$TI" "$TV"
else
  skip "C2-10" "workload-guardrails isn't on the security account. Re-run with --attach-workload"
fi
detach_workload

# ══ 5. Logging ════════════════════════════════════════════════════════════
section "Central logging (C11)"

eq C11 "Org trail is multi-region + organization-wide + validated + KMS" \
  "$(mgmt cloudtrail describe-trails --trail-name-list "$TRAIL_NAME" \
     --query 'trailList[0].[IsMultiRegionTrail,IsOrganizationTrail,LogFileValidationEnabled,KmsKeyId!=`null`]' \
     --output text 2>&1 | tr -s '\t ' ' ')" "True True True True"
eq C11 "Org trail is logging" \
  "$(mgmt cloudtrail get-trail-status --name "$TRAIL_ARN" --query IsLogging --output text 2>&1)" "True"

if [ -n "$LOG_BUCKET" ]; then
  eq C11 "Log bucket: versioning enabled" \
    "$(sec s3api get-bucket-versioning --bucket "$LOG_BUCKET" --query Status --output text 2>&1)" "Enabled"
  eq C11 "Log bucket: Object Lock enabled" \
    "$(sec s3api get-object-lock-configuration --bucket "$LOG_BUCKET" \
       --query ObjectLockConfiguration.ObjectLockEnabled --output text 2>&1)" "Enabled"
  eq C4  "Log bucket: Block Public Access all ON" \
    "$(sec s3api get-public-access-block --bucket "$LOG_BUCKET" \
       --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' \
       --output text 2>&1 | tr -s '\t ' ' ')" "True True True True"
fi

if $VALIDATE_LOGS; then
  START=$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
  # Run from the security account: it owns the log bucket, and the bucket
  # policy doesn't let management read it (separation of duties).
  for acct in "$MGMT_ID" "$SEC_ID"; do
    OUT=$(sec cloudtrail validate-logs --trail-arn "$TRAIL_ARN" --start-time "$START" --account-id "$acct" 2>&1)
    if echo "$OUT" | grep -q "INVALID"; then fail C11 "validate-logs for $acct (last 24 h)" "$(echo "$OUT" | grep INVALID)"
    elif echo "$OUT" | grep -qE "[0-9]+/[0-9]+ log files valid"; then
      pass C11 "validate-logs for $acct: $(echo "$OUT" | grep -oE '[0-9]+/[0-9]+ log files valid')"
    else warn C11 "validate-logs for $acct gave no result" ; fi
  done
else
  skip C11 "Log integrity check (re-run with --validate-logs)"
fi

# ══ 6. Detection & monitoring ═════════════════════════════════════════════
section "Detection and monitoring (C12, C13, C14)"

ACCTS=$(sec configservice get-aggregate-discovered-resource-counts \
  --configuration-aggregator-name "$AGGREGATOR" --group-by-key ACCOUNT_ID \
  --query 'length(GroupedResourceCounts)' --output text 2>&1)
if [ "$ACCTS" -ge 2 ] 2>/dev/null; then pass C12 "Config aggregator sees $ACCTS accounts"
else fail C12 "Config aggregator should see both accounts" "$ACCTS"; fi

DET=$(sec guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null)
if [ -n "$DET" ] && [ "$DET" != "None" ]; then
  eq C13 "GuardDuty: auto-enable for all org accounts" \
    "$(sec guardduty describe-organization-configuration --detector-id "$DET" \
       --query AutoEnableOrganizationMembers --output text 2>&1)" "ALL"
  MEMBERS=$(sec guardduty list-members --detector-id "$DET" --query 'length(Members)' --output text 2>&1)
  if [ "$MEMBERS" -ge 1 ] 2>/dev/null; then pass C13 "GuardDuty: $MEMBERS member account(s) under the security admin"
  else fail C13 "GuardDuty: no member accounts" "$MEMBERS"; fi
else fail C13 "GuardDuty: no detector in $REGION"; fi

eq C13 "Security Hub: central configuration" \
  "$(sec securityhub describe-organization-configuration \
     --query OrganizationConfiguration.ConfigurationType --output text 2>&1)" "CENTRAL"
FINDING_ACCTS=$(sec securityhub get-findings --max-items 100 --query 'Findings[].AwsAccountId' --output text 2>/dev/null \
  | tr '\t' '\n' | sort -u | grep -c .)
if [ "$FINDING_ACCTS" -ge 2 ]; then pass C13 "Security Hub: findings from $FINDING_ACCTS accounts"
else warn C13 "Security Hub: findings from only $FINDING_ACCTS account(s) in the first 100"; fi

AA_ARN=$(sec accessanalyzer list-analyzers --type ORGANIZATION \
  --query "analyzers[?name=='$ANALYZER'].arn | [0]" --output text 2>/dev/null)
if [ -n "$AA_ARN" ] && [ "$AA_ARN" != "None" ]; then
  pass C13 "Access Analyzer: organization analyzer '$ANALYZER' exists"
  ACTIVE=$(sec accessanalyzer list-findings-v2 --analyzer-arn "$AA_ARN" \
    --filter '{"status":{"eq":["ACTIVE"]}}' --query 'length(findings)' --output text 2>&1)
  if [ "$ACTIVE" = "0" ]; then pass C13 "Access Analyzer: 0 active findings"
  else warn C13 "Access Analyzer: $ACTIVE active finding(s) — review them in the console"; fi
else fail C13 "Access Analyzer: analyzer '$ANALYZER' not found"; fi

BUDGETS=$(mgmt budgets describe-budgets --account-id "$MGMT_ID" --query 'length(Budgets)' --output text 2>&1)
if [ "$BUDGETS" -ge 1 ] 2>/dev/null; then pass C14 "Budgets: $BUDGETS budget(s) configured"
else fail C14 "Budgets: none found" "$BUDGETS"; fi

# ══ Summary ═══════════════════════════════════════════════════════════════
section "Summary"
printf '  %s%d passed%s  %s%d failed%s  %s%d warnings%s  %d skipped\n' \
  "$G" "$PASSES" "$N" "$R" "$FAILS" "$N" "$Y" "$WARNS" "$N" "$SKIPS"
echo "  ${D}Still manual: C1 (MFA at first sign-in), payments-dev1 empty portal, console delete of a log version.${N}"
[ "$FAILS" -eq 0 ]
