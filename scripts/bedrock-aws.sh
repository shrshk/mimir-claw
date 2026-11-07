#!/usr/bin/env bash
# Sets up the AWS side of the Personal agent's model: an AWS user that can only call the Claude models through the
# us-east-2 inference profiles, its keys in ~/.aws as profile openclaw-air, then one tiny call to prove it works.
# Run it yourself on the Mac that runs OpenClaw, signed in to your AWS account as an admin:
#   scripts/bedrock-aws.sh [--admin-profile NAME] [--user NAME] [--rotate]
# Safe to run again: the user is made only when missing, its policy is set again, and working keys are kept.
# --rotate makes new keys, checks them, then deletes the old ones. The keys go from AWS straight into
# ~/.aws/credentials (owner-only): never printed, never on a command line.
# Not here: Anthropic's one-time use-case form in the Bedrock console, if your account has not sent it (the test at
# the end says so).
set -euo pipefail
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
REPO=$(cd "$(dirname "$0")/.." && pwd)
ADMIN=${AWS_PROFILE:-default}; NAME=openclaw-air; ROTATE=""
PROFILE=openclaw-air; REGION=us-east-2; POLICY=bedrock-claude-invoke
while [ $# -gt 0 ]; do
  case $1 in
    --admin-profile) ADMIN=$2; shift ;;
    --user) NAME=$2; shift ;;
    --rotate) ROTATE=1 ;;
    *) echo "usage: bedrock-aws.sh [--admin-profile NAME] [--user NAME] [--rotate]" >&2; exit 2 ;;
  esac
  shift
done
command -v aws >/dev/null || { echo "needs the AWS CLI: brew install awscli" >&2; exit 1; }
admin() { aws --profile "$ADMIN" "$@"; }

account=$(admin sts get-caller-identity --query Account --output text 2>/dev/null) || {
  echo "admin profile '$ADMIN' does not sign in: aws configure --profile $ADMIN (or aws sso login), or pass --admin-profile" >&2
  exit 1
}
echo "admin: profile $ADMIN"

# 1. the user
if admin iam get-user --user-name "$NAME" >/dev/null 2>&1; then echo "user $NAME: there"; else
  admin iam create-user --user-name "$NAME" --tags Key=purpose,Value=openclaw-bedrock >/dev/null
  echo "user $NAME: made"
fi

# 2. its only permission: call Claude through the us-east-2 inference profiles (and the models behind them, which
# can run in any US region, only through those profiles)
profiles="arn:aws:bedrock:$REGION:$account:inference-profile/us.anthropic.claude-*"
admin iam put-user-policy --user-name "$NAME" --policy-name "$POLICY" --policy-document "$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ClaudeInferenceProfiles",
      "Effect": "Allow",
      "Action": ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
      "Resource": "$profiles"
    },
    {
      "Sid": "ClaudeModelsThroughThoseProfiles",
      "Effect": "Allow",
      "Action": ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
      "Resource": "arn:aws:bedrock:*::foundation-model/anthropic.claude-*",
      "Condition": {"StringLike": {"bedrock:InferenceProfileArn": "$profiles"}}
    }
  ]
}
JSON
)"
echo "policy $POLICY: set (Claude through the $REGION inference profiles only)"
other=$(admin iam list-attached-user-policies --user-name "$NAME" --query 'AttachedPolicies[].PolicyName' --output text)
extra=$(admin iam list-user-policies --user-name "$NAME" --query 'PolicyNames' --output text | tr '\t' '\n' | grep -vx "$POLICY" || true)
[ -z "$other$extra" ] || echo "note: $NAME also has $(echo $other $extra): remove them in IAM for least privilege"

# 3. the keys
whose=$(aws --profile "$PROFILE" sts get-caller-identity --query Arn --output text 2>/dev/null || true)
old_key=""
if [ -n "$whose" ] && [ "${whose##*/}" != "$NAME" ]; then
  echo "profile $PROFILE holds the keys of another AWS user (${whose##*/}); pass --user ${whose##*/}, or remove the profile" >&2
  exit 1
elif [ -n "$whose" ] && [ -z "$ROTATE" ]; then
  echo "keys: profile $PROFILE works, kept (--rotate for new ones)"
else
  [ -z "$whose" ] || old_key=$(aws configure get aws_access_key_id --profile "$PROFILE")
  count=$(admin iam list-access-keys --user-name "$NAME" --query 'length(AccessKeyMetadata)' --output text)
  others=$((count - (old_key != "" ? 1 : 0)))
  if [ "$others" -gt 0 ]; then
    echo "$NAME has $others access key(s) that profile $PROFILE does not use: delete them in IAM first" >&2
    [ "$count" -lt 2 ] || exit 1
  fi
  mkdir -p "$HOME/.aws" && chmod 700 "$HOME/.aws"
  backup=""
  if [ -n "$old_key" ]; then  # put back if the new keys fail, so OpenClaw keeps working
    backup=$(mktemp "$HOME/.aws/credentials.before-rotate.XXXXXX")
    cp -p "$HOME/.aws/credentials" "$backup"
  fi
  admin iam create-access-key --user-name "$NAME" --output json | python3 -c '
import configparser, json, os, sys
key = json.load(sys.stdin)["AccessKey"]
path, profile = os.path.expanduser("~/.aws/credentials"), sys.argv[1]
creds = configparser.RawConfigParser()
creds.read(path)
creds[profile] = {"aws_access_key_id": key["AccessKeyId"], "aws_secret_access_key": key["SecretAccessKey"]}
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    creds.write(f)
os.chmod(path, 0o600)
' "$PROFILE"
  aws configure set region "$REGION" --profile "$PROFILE"
  echo "keys: new ones in ~/.aws/credentials as profile $PROFILE"
fi

# 4. the test: new keys and policies take a few seconds to reach Bedrock
log=$(mktemp)
for try in 1 2 3 4 5 6; do
  if bash "$REPO/scripts/bedrock-test.sh" "$PROFILE" 2>"$log"; then
    rm -f "$log"
    echo "bedrock: Haiku answers as $NAME"
    if [ -n "$old_key" ]; then
      admin iam delete-access-key --user-name "$NAME" --access-key-id "$old_key"
      rm -f "$backup"
      echo "keys: the old ones deleted"
    fi
    exit 0
  fi
  [ "$try" = 6 ] || sleep 10
done
cat "$log" >&2; rm -f "$log"
if [ -n "$old_key" ]; then
  new_key=$(aws configure get aws_access_key_id --profile "$PROFILE")
  mv "$backup" "$HOME/.aws/credentials"
  admin iam delete-access-key --user-name "$NAME" --access-key-id "$new_key"
  echo "rotation undone: profile $PROFILE has its old keys again, the new ones are deleted" >&2
fi
exit 1
