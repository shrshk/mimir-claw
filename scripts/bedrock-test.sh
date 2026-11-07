#!/usr/bin/env bash
# One tiny call to Bedrock as the Personal agent makes it: Haiku through the us-east-2 inference profile, with the
# AWS profile openclaw-air. Exit 0 when it answers; otherwise the reason on stderr (account numbers blanked).
#   scripts/bedrock-test.sh [profile]
set -uo pipefail
PROFILE=${1:-openclaw-air}
MODEL=us.anthropic.claude-haiku-4-5-20251001-v1:0
err=$(aws bedrock-runtime converse --profile "$PROFILE" --region us-east-2 --model-id "$MODEL" \
  --messages '[{"role":"user","content":[{"text":"Say ok."}]}]' --inference-config maxTokens=1 \
  --query stopReason --output text 2>&1 >/dev/null) && exit 0
reason=$(printf '%s\n' "$err" | grep -v '^$' | tail -1 | sed -E 's/[0-9]{12}/<account>/g')
echo "$reason" >&2
case $err in
  *"use case"*|*"use-case"*|*"model access"*|*"Model access"*|*aws-marketplace*)
    echo "Anthropic's one-time form: AWS console, Bedrock, Model catalog, a Claude model, submit the use case" >&2 ;;
  *InvalidClientTokenId*|*SignatureDoesNotMatch*|*"could not be found"*)
    echo "the keys in profile $PROFILE are wrong or deleted: run scripts/bedrock-aws.sh" >&2 ;;
  *AccessDenied*)
    echo "the AWS user may not call this model: run scripts/bedrock-aws.sh to set its policy" >&2 ;;
esac
exit 1
