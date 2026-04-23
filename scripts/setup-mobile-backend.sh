#!/usr/bin/env bash
# =============================================================================
# ColdTrack - Setup Mobile Backend
# Creates DynamoDB table, IoT Rule (direct → DynamoDB, no Lambda), query
# Lambda, HTTP API Gateway, and Cognito Identity Pool for the mobile app.
#
# Architecture after this script runs:
#
#   ESP32 → IoT Core ─┬─→ coldtrack_telemetry_processor (existing → InfluxDB)
#                     └─→ coldtrack_telemetry_to_dynamodb (NEW → DynamoDB)
#
#   Mobile → Cognito (guest) → SigV4 → API Gateway → Lambda → DynamoDB
#
# Prerequisites:
#   - AWS CLI v2
#   - jq (for parsing responses)
#   - Python 3 (for zipping the Lambda)
#
# Usage:
#   export AWS_ACCESS_KEY_ID=your_key
#   export AWS_SECRET_ACCESS_KEY=your_secret
#   ./scripts/setup-mobile-backend.sh
# =============================================================================
set -euo pipefail

REGION="eu-west-1"
ACCOUNT_ID="825765428301"

READINGS_TABLE="coldtrack-readings"
IOT_RULE_NAME="coldtrack_telemetry_to_dynamodb"
IOT_DDB_ROLE="coldtrack-iot-dynamodb-role"
LAMBDA_ROLE="coldtrack-mobile-api-lambda-role"
LAMBDA_NAME="coldtrack-mobile-api"
API_NAME="coldtrack-mobile-api"
API_STAGE="prod"
IDENTITY_POOL_NAME="coldtrack-mobile-guest"
UNAUTH_ROLE_NAME="Cognito_coldtrackMobileGuestUnauth_Role"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LAMBDA_SRC="${PROJECT_DIR}/lambda/mobile_api"
ZIP_PATH="/tmp/coldtrack-mobile-api.zip"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass()   { echo -e "${GREEN}[PASS]${NC} $1"; }
info()   { echo -e "${YELLOW}[INFO]${NC} $1"; }
fail()   { echo -e "${RED}[FAIL]${NC} $1"; }
header() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
header "Pre-flight"

for cmd in aws jq python3 zip; do
    if ! command -v "$cmd" &>/dev/null; then
        fail "$cmd not found"; exit 1
    fi
done
pass "CLI tools present"

aws sts get-caller-identity --region "$REGION" --output text &>/dev/null || {
    fail "AWS credentials invalid — export AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY"
    exit 1
}
pass "Authenticated"

# ===========================================================================
# 1. DynamoDB table
# ===========================================================================
header "1. DynamoDB table"

if aws dynamodb describe-table --table-name "$READINGS_TABLE" --region "$REGION" &>/dev/null; then
    pass "Table '$READINGS_TABLE' already exists"
else
    info "Creating table '$READINGS_TABLE' (PK=deviceId, SK=timestamp)..."
    aws dynamodb create-table \
        --table-name "$READINGS_TABLE" \
        --region "$REGION" \
        --billing-mode PAY_PER_REQUEST \
        --attribute-definitions \
            AttributeName=deviceId,AttributeType=S \
            AttributeName=timestamp,AttributeType=S \
        --key-schema \
            AttributeName=deviceId,KeyType=HASH \
            AttributeName=timestamp,KeyType=RANGE \
        --output text >/dev/null
    info "Waiting for table to become ACTIVE..."
    aws dynamodb wait table-exists --table-name "$READINGS_TABLE" --region "$REGION"
    pass "Table ready"
fi

# ===========================================================================
# 2. IAM role for IoT Rule → DynamoDB
# ===========================================================================
header "2. IoT → DynamoDB IAM role"

if aws iam get-role --role-name "$IOT_DDB_ROLE" &>/dev/null; then
    IOT_DDB_ROLE_ARN=$(aws iam get-role --role-name "$IOT_DDB_ROLE" --query 'Role.Arn' --output text)
    pass "Role already exists"
else
    IOT_DDB_ROLE_ARN=$(aws iam create-role \
        --role-name "$IOT_DDB_ROLE" \
        --assume-role-policy-document '{
            "Version":"2012-10-17",
            "Statement":[{
                "Effect":"Allow",
                "Principal":{"Service":"iot.amazonaws.com"},
                "Action":"sts:AssumeRole"
            }]
        }' \
        --query 'Role.Arn' --output text)
    aws iam put-role-policy \
        --role-name "$IOT_DDB_ROLE" \
        --policy-name "dynamodb-put" \
        --policy-document "{
            \"Version\":\"2012-10-17\",
            \"Statement\":[{
                \"Effect\":\"Allow\",
                \"Action\":[\"dynamodb:PutItem\"],
                \"Resource\":\"arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${READINGS_TABLE}\"
            }]
        }"
    pass "Role created: $IOT_DDB_ROLE_ARN"
    info "Waiting 10s for IAM propagation..."
    sleep 10
fi

# ===========================================================================
# 3. IoT Rule: telemetry → DynamoDB
# ===========================================================================
header "3. IoT Rule → DynamoDB"

# SQL extracts deviceId from the MQTT topic (3rd segment) and formats an
# ISO-8601 sort key. The quoted heredoc (<<'SQL_EOF') preserves the literal
# double quotes inside parse_time(...).
IOT_SQL=$(cat <<'SQL_EOF'
SELECT *, topic(3) as deviceId, parse_time("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", timestamp(), "UTC") as timestamp FROM 'coldtrack/sensors/+/telemetry'
SQL_EOF
)

if aws iot get-topic-rule --rule-name "$IOT_RULE_NAME" --region "$REGION" &>/dev/null; then
    pass "IoT rule already exists"
else
    RULE_PAYLOAD=$(mktemp)
    # jq --arg handles JSON escaping of the quoted SQL cleanly.
    jq -n \
        --arg sql "$IOT_SQL" \
        --arg roleArn "$IOT_DDB_ROLE_ARN" \
        --arg tableName "$READINGS_TABLE" \
        '{
            sql: $sql,
            ruleDisabled: false,
            awsIotSqlVersion: "2016-03-23",
            actions: [{
                dynamoDBv2: {
                    roleArn: $roleArn,
                    putItem: { tableName: $tableName }
                }
            }]
        }' > "$RULE_PAYLOAD"

    aws iot create-topic-rule \
        --rule-name "$IOT_RULE_NAME" \
        --region "$REGION" \
        --topic-rule-payload "file://${RULE_PAYLOAD}"
    rm -f "$RULE_PAYLOAD"
    pass "Rule '$IOT_RULE_NAME' created"
fi

# ===========================================================================
# 4. Lambda execution role
# ===========================================================================
header "4. Lambda execution role"

if aws iam get-role --role-name "$LAMBDA_ROLE" &>/dev/null; then
    LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$LAMBDA_ROLE" --query 'Role.Arn' --output text)
    pass "Role already exists"
else
    LAMBDA_ROLE_ARN=$(aws iam create-role \
        --role-name "$LAMBDA_ROLE" \
        --assume-role-policy-document '{
            "Version":"2012-10-17",
            "Statement":[{
                "Effect":"Allow",
                "Principal":{"Service":"lambda.amazonaws.com"},
                "Action":"sts:AssumeRole"
            }]
        }' \
        --query 'Role.Arn' --output text)
    aws iam put-role-policy \
        --role-name "$LAMBDA_ROLE" \
        --policy-name "ddb-and-logs" \
        --policy-document "{
            \"Version\":\"2012-10-17\",
            \"Statement\":[
                {
                    \"Effect\":\"Allow\",
                    \"Action\":[\"dynamodb:Query\",\"dynamodb:GetItem\"],
                    \"Resource\":\"arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${READINGS_TABLE}\"
                },
                {
                    \"Effect\":\"Allow\",
                    \"Action\":[\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],
                    \"Resource\":\"arn:aws:logs:${REGION}:${ACCOUNT_ID}:*\"
                }
            ]
        }"
    pass "Role created: $LAMBDA_ROLE_ARN"
    info "Waiting 10s for IAM propagation..."
    sleep 10
fi

# ===========================================================================
# 5. Deploy Lambda
# ===========================================================================
header "5. Lambda function"

info "Packaging Lambda from $LAMBDA_SRC..."
rm -f "$ZIP_PATH"
(cd "$LAMBDA_SRC" && zip -q -r "$ZIP_PATH" index.py)
pass "Zipped: $(wc -c < "$ZIP_PATH") bytes"

if aws lambda get-function --function-name "$LAMBDA_NAME" --region "$REGION" &>/dev/null; then
    info "Updating existing Lambda..."
    aws lambda update-function-code \
        --function-name "$LAMBDA_NAME" \
        --region "$REGION" \
        --zip-file "fileb://${ZIP_PATH}" \
        --output text >/dev/null
    aws lambda update-function-configuration \
        --function-name "$LAMBDA_NAME" \
        --region "$REGION" \
        --environment "Variables={READINGS_TABLE=${READINGS_TABLE}}" \
        --output text >/dev/null
else
    info "Creating Lambda..."
    aws lambda create-function \
        --function-name "$LAMBDA_NAME" \
        --region "$REGION" \
        --runtime "python3.11" \
        --role "$LAMBDA_ROLE_ARN" \
        --handler "index.lambda_handler" \
        --timeout 10 \
        --memory-size 256 \
        --environment "Variables={READINGS_TABLE=${READINGS_TABLE}}" \
        --zip-file "fileb://${ZIP_PATH}" \
        --output text >/dev/null
fi
LAMBDA_ARN=$(aws lambda get-function --function-name "$LAMBDA_NAME" --region "$REGION" --query 'Configuration.FunctionArn' --output text)
pass "Lambda ready: $LAMBDA_ARN"

# ===========================================================================
# 6. HTTP API Gateway
# ===========================================================================
header "6. HTTP API Gateway"

API_ID=$(aws apigatewayv2 get-apis --region "$REGION" \
    --query "Items[?Name=='${API_NAME}'].ApiId | [0]" --output text)

if [ "$API_ID" = "None" ] || [ -z "$API_ID" ]; then
    info "Creating HTTP API..."
    API_ID=$(aws apigatewayv2 create-api \
        --name "$API_NAME" \
        --protocol-type HTTP \
        --region "$REGION" \
        --query 'ApiId' --output text)
    pass "API created: $API_ID"
else
    pass "API already exists: $API_ID"
fi

API_ARN="arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}"
API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/${API_STAGE}"

# Create the integration (reusable across all routes)
INTEGRATION_ID=$(aws apigatewayv2 get-integrations --api-id "$API_ID" --region "$REGION" \
    --query "Items[?IntegrationUri=='${LAMBDA_ARN}'].IntegrationId | [0]" --output text)

if [ "$INTEGRATION_ID" = "None" ] || [ -z "$INTEGRATION_ID" ]; then
    INTEGRATION_ID=$(aws apigatewayv2 create-integration \
        --api-id "$API_ID" \
        --region "$REGION" \
        --integration-type AWS_PROXY \
        --integration-uri "$LAMBDA_ARN" \
        --payload-format-version "2.0" \
        --query 'IntegrationId' --output text)
    pass "Integration created: $INTEGRATION_ID"
else
    pass "Integration exists: $INTEGRATION_ID"
fi

# Create routes with IAM authorization (so SigV4 from the mobile works)
create_route() {
    local route_key="$1"
    local existing
    existing=$(aws apigatewayv2 get-routes --api-id "$API_ID" --region "$REGION" \
        --query "Items[?RouteKey=='${route_key}'].RouteId | [0]" --output text)
    if [ "$existing" = "None" ] || [ -z "$existing" ]; then
        aws apigatewayv2 create-route \
            --api-id "$API_ID" \
            --region "$REGION" \
            --route-key "$route_key" \
            --target "integrations/${INTEGRATION_ID}" \
            --authorization-type "AWS_IAM" \
            --output text >/dev/null
        pass "Route created: $route_key"
    else
        pass "Route exists: $route_key"
    fi
}

create_route "GET /devices/{deviceId}/readings"
create_route "GET /devices/{deviceId}/readings/latest"
create_route "POST /incidents"

# Create/ensure stage
if ! aws apigatewayv2 get-stage --api-id "$API_ID" --stage-name "$API_STAGE" --region "$REGION" &>/dev/null; then
    aws apigatewayv2 create-stage \
        --api-id "$API_ID" \
        --region "$REGION" \
        --stage-name "$API_STAGE" \
        --auto-deploy \
        --output text >/dev/null
    pass "Stage created: $API_STAGE"
else
    pass "Stage exists: $API_STAGE"
fi

# Grant API Gateway permission to invoke the Lambda
aws lambda add-permission \
    --function-name "$LAMBDA_NAME" \
    --region "$REGION" \
    --statement-id "apigw-invoke-$(date +%s)" \
    --action "lambda:InvokeFunction" \
    --principal "apigateway.amazonaws.com" \
    --source-arn "${API_ARN}/*/*" \
    --output text 2>/dev/null || info "Lambda invoke permission already attached"

# ===========================================================================
# 7. Cognito Identity Pool (guest)
# ===========================================================================
header "7. Cognito Identity Pool"

POOL_ID=$(aws cognito-identity list-identity-pools --max-results 60 --region "$REGION" \
    --query "IdentityPools[?IdentityPoolName=='${IDENTITY_POOL_NAME}'].IdentityPoolId | [0]" --output text)

if [ "$POOL_ID" = "None" ] || [ -z "$POOL_ID" ]; then
    POOL_ID=$(aws cognito-identity create-identity-pool \
        --identity-pool-name "$IDENTITY_POOL_NAME" \
        --allow-unauthenticated-identities \
        --region "$REGION" \
        --query 'IdentityPoolId' --output text)
    pass "Pool created: $POOL_ID"
else
    pass "Pool exists: $POOL_ID"
fi

# Create unauthenticated role
if aws iam get-role --role-name "$UNAUTH_ROLE_NAME" &>/dev/null; then
    UNAUTH_ROLE_ARN=$(aws iam get-role --role-name "$UNAUTH_ROLE_NAME" --query 'Role.Arn' --output text)
    pass "Unauth role exists"
else
    UNAUTH_ROLE_ARN=$(aws iam create-role \
        --role-name "$UNAUTH_ROLE_NAME" \
        --assume-role-policy-document "{
            \"Version\":\"2012-10-17\",
            \"Statement\":[{
                \"Effect\":\"Allow\",
                \"Principal\":{\"Federated\":\"cognito-identity.amazonaws.com\"},
                \"Action\":\"sts:AssumeRoleWithWebIdentity\",
                \"Condition\":{
                    \"StringEquals\":{\"cognito-identity.amazonaws.com:aud\":\"${POOL_ID}\"},
                    \"ForAnyValue:StringLike\":{\"cognito-identity.amazonaws.com:amr\":\"unauthenticated\"}
                }
            }]
        }" \
        --query 'Role.Arn' --output text)
    pass "Unauth role created"
fi

# Attach execute-api policy for the mobile routes
aws iam put-role-policy \
    --role-name "$UNAUTH_ROLE_NAME" \
    --policy-name "mobile-api-invoke" \
    --policy-document "{
        \"Version\":\"2012-10-17\",
        \"Statement\":[{
            \"Effect\":\"Allow\",
            \"Action\":[\"execute-api:Invoke\"],
            \"Resource\":\"${API_ARN}/${API_STAGE}/*/*\"
        }]
    }"
pass "Execute-api policy attached"

# Bind the role to the pool
aws cognito-identity set-identity-pool-roles \
    --identity-pool-id "$POOL_ID" \
    --roles "unauthenticated=${UNAUTH_ROLE_ARN}" \
    --region "$REGION"
pass "Role bound to identity pool"

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ColdTrack Mobile Backend Ready${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Paste these into mobile/coldtrack/.env:${NC}"
echo ""
echo "  COGNITO_IDENTITY_POOL_ID=$POOL_ID"
echo "  API_GATEWAY_BASE_URL=$API_URL"
echo ""
echo -e "${BOLD}Also set the DEVICE_ID to a real publisher:${NC}"
echo ""
echo "  DEFAULT_DEVICE_ID=ESP32_TEST_002"
echo "  IOT_DEVICE_ID=ESP32_TEST_002"
echo ""
echo -e "${BOLD}Verify data flow:${NC}"
echo ""
echo "  # 1. Publish test telemetry (writes to DynamoDB via the new IoT Rule)"
echo "  ./run-test.sh"
echo ""
echo "  # 2. Confirm the row landed in DynamoDB"
echo "  aws dynamodb scan --table-name $READINGS_TABLE --region $REGION --limit 5"
echo ""
echo "  # 3. Launch the app — chart should fill with real readings within 5s"
echo "  cd mobile/coldtrack && flutter run"
echo ""
