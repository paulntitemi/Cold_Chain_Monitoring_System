#!/usr/bin/env bash
# =============================================================================
# ColdTrack - Setup Storage Pipeline
# Creates Timestream table, S3 bucket, Kinesis Firehose, IoT Rule,
# and deploys the process-violation Lambda with Timestream support.
#
# Prerequisites:
#   - AWS CLI v2 installed and configured
#   - You must create the Timestream DATABASE first via AWS Console:
#     Console → Amazon Timestream → Create database → "coldtrack-telemetry"
#   - Export AWS credentials before running this script
#
# Usage:
#   export AWS_ACCESS_KEY_ID=your_key
#   export AWS_SECRET_ACCESS_KEY=your_secret
#   ./scripts/setup-storage.sh
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REGION="eu-west-1"
ACCOUNT_ID="825765428301"
PROJECT="coldtrack"

TIMESTREAM_DB="coldtrack-telemetry"
TIMESTREAM_TABLE="sensor_data"

S3_RAW_BUCKET="coldtrack-raw-data-${ACCOUNT_ID}-${REGION}"
S3_ML_BUCKET="coldtrack-ml-models-${ACCOUNT_ID}-${REGION}"

FIREHOSE_STREAM="coldtrack-telemetry-to-s3"
FIREHOSE_ROLE_NAME="coldtrack-firehose-role"
IOT_FIREHOSE_ROLE_NAME="coldtrack-iot-firehose-role"

LAMBDA_FUNCTION="coldtrack-processor"
IOT_RULE_NAME="coldtrack_telemetry_to_firehose"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colours
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

pass()  { echo -e "${GREEN}[PASS]${NC} $1"; }
info()  { echo -e "${YELLOW}[INFO]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; }
header() { echo -e "\n${YELLOW}━━━ $1 ━━━${NC}"; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
header "Pre-flight Checks"

if ! command -v aws &>/dev/null; then
    fail "AWS CLI not found. Install: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    exit 1
fi
pass "AWS CLI found"

# Verify credentials
CALLER=$(aws sts get-caller-identity --region "$REGION" --output json 2>&1) || {
    fail "AWS credentials not configured. Export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."
    exit 1
}
CALLER_ACCOUNT=$(echo "$CALLER" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])")
pass "Authenticated as account $CALLER_ACCOUNT"

# ==========================================================================
# Step 1: Timestream Table
# ==========================================================================
header "Step 1: Timestream Table"

# Check if Timestream database exists
if aws timestream-write describe-database \
    --database-name "$TIMESTREAM_DB" \
    --region "$REGION" &>/dev/null; then
    pass "Timestream database '$TIMESTREAM_DB' exists"
else
    fail "Timestream database '$TIMESTREAM_DB' not found."
    echo "  Create it first via the AWS Console:"
    echo "    1. Go to Amazon Timestream → Databases → Create database"
    echo "    2. Name: $TIMESTREAM_DB"
    echo "    3. Type: Standard"
    echo "  Then re-run this script."
    exit 1
fi

# Create table if not exists
if aws timestream-write describe-table \
    --database-name "$TIMESTREAM_DB" \
    --table-name "$TIMESTREAM_TABLE" \
    --region "$REGION" &>/dev/null; then
    pass "Timestream table '$TIMESTREAM_TABLE' already exists"
else
    info "Creating Timestream table '$TIMESTREAM_TABLE'..."
    aws timestream-write create-table \
        --database-name "$TIMESTREAM_DB" \
        --table-name "$TIMESTREAM_TABLE" \
        --region "$REGION" \
        --retention-properties \
            "MemoryStoreRetentionPeriodInHours=2160,MagneticStoreRetentionPeriodInDays=365" \
        --magnetic-store-write-properties \
            "EnableMagneticStoreWrites=true" \
        --output text &>/dev/null
    pass "Created Timestream table '$TIMESTREAM_TABLE' (90d memory, 365d magnetic)"
fi

# ==========================================================================
# Step 2: S3 Buckets
# ==========================================================================
header "Step 2: S3 Buckets"

create_s3_bucket() {
    local bucket_name=$1
    local label=$2

    if aws s3api head-bucket --bucket "$bucket_name" --region "$REGION" 2>/dev/null; then
        pass "S3 bucket '$bucket_name' already exists"
    else
        info "Creating S3 bucket '$bucket_name'..."
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION" \
            --output text &>/dev/null

        # Block public access
        aws s3api put-public-access-block \
            --bucket "$bucket_name" \
            --public-access-block-configuration \
                "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

        # Enable server-side encryption
        aws s3api put-bucket-encryption \
            --bucket "$bucket_name" \
            --server-side-encryption-configuration \
                '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

        pass "Created S3 bucket '$bucket_name' ($label)"
    fi
}

create_s3_bucket "$S3_RAW_BUCKET" "raw telemetry / ML training"
create_s3_bucket "$S3_ML_BUCKET" "ML model artifacts"

# Add lifecycle policy for raw data bucket (tiering for ML datasets)
info "Setting lifecycle policy on raw data bucket..."
aws s3api put-bucket-lifecycle-configuration \
    --bucket "$S3_RAW_BUCKET" \
    --lifecycle-configuration '{
        "Rules": [{
            "ID": "telemetry-tiering",
            "Status": "Enabled",
            "Filter": {"Prefix": "telemetry/"},
            "Transitions": [
                {"Days": 30, "StorageClass": "INTELLIGENT_TIERING"},
                {"Days": 90, "StorageClass": "GLACIER"}
            ],
            "Expiration": {"Days": 730}
        }]
    }'
pass "Lifecycle policy set (Intelligent-Tiering @30d, Glacier @90d, expire @2yr)"

# ==========================================================================
# Step 3: IAM Role for Kinesis Firehose → S3
# ==========================================================================
header "Step 3: Firehose IAM Role"

FIREHOSE_ROLE_ARN=""
if aws iam get-role --role-name "$FIREHOSE_ROLE_NAME" &>/dev/null; then
    FIREHOSE_ROLE_ARN=$(aws iam get-role --role-name "$FIREHOSE_ROLE_NAME" --query 'Role.Arn' --output text)
    pass "Firehose role already exists: $FIREHOSE_ROLE_ARN"
else
    info "Creating Firehose IAM role..."

    FIREHOSE_ROLE_ARN=$(aws iam create-role \
        --role-name "$FIREHOSE_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "firehose.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --query 'Role.Arn' --output text)

    aws iam put-role-policy \
        --role-name "$FIREHOSE_ROLE_NAME" \
        --policy-name "firehose-s3-write" \
        --policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [{
                \"Effect\": \"Allow\",
                \"Action\": [
                    \"s3:AbortMultipartUpload\",
                    \"s3:GetBucketLocation\",
                    \"s3:GetObject\",
                    \"s3:ListBucket\",
                    \"s3:ListBucketMultipartUploads\",
                    \"s3:PutObject\"
                ],
                \"Resource\": [
                    \"arn:aws:s3:::${S3_RAW_BUCKET}\",
                    \"arn:aws:s3:::${S3_RAW_BUCKET}/*\"
                ]
            },{
                \"Effect\": \"Allow\",
                \"Action\": [\"logs:PutLogEvents\",\"logs:CreateLogStream\",\"logs:CreateLogGroup\"],
                \"Resource\": \"arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/kinesisfirehose/${FIREHOSE_STREAM}:*\"
            }]
        }"

    pass "Created Firehose role: $FIREHOSE_ROLE_ARN"
    info "Waiting 10s for IAM role propagation..."
    sleep 10
fi

# ==========================================================================
# Step 4: Kinesis Firehose Delivery Stream
# ==========================================================================
header "Step 4: Kinesis Firehose"

FIREHOSE_EXISTS=$(aws firehose describe-delivery-stream \
    --delivery-stream-name "$FIREHOSE_STREAM" \
    --region "$REGION" 2>/dev/null && echo "yes" || echo "no")

if [ "$FIREHOSE_EXISTS" = "yes" ]; then
    pass "Firehose stream '$FIREHOSE_STREAM' already exists"
else
    info "Creating Firehose delivery stream (batches telemetry → S3)..."
    aws firehose create-delivery-stream \
        --delivery-stream-name "$FIREHOSE_STREAM" \
        --delivery-stream-type "DirectPut" \
        --region "$REGION" \
        --extended-s3-destination-configuration "{
            \"RoleARN\": \"${FIREHOSE_ROLE_ARN}\",
            \"BucketARN\": \"arn:aws:s3:::${S3_RAW_BUCKET}\",
            \"Prefix\": \"telemetry/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/\",
            \"ErrorOutputPrefix\": \"errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/\",
            \"BufferingHints\": {\"IntervalInSeconds\": 60, \"SizeInMBs\": 1},
            \"CompressionFormat\": \"GZIP\",
            \"CloudWatchLoggingOptions\": {
                \"Enabled\": true,
                \"LogGroupName\": \"/aws/kinesisfirehose/${FIREHOSE_STREAM}\",
                \"LogStreamName\": \"S3Delivery\"
            }
        }" \
        --output text &>/dev/null

    pass "Created Firehose stream '$FIREHOSE_STREAM'"
    info "  Buffer: 60s / 1MB (small values for testing — increase in production)"
    info "  Path:   s3://${S3_RAW_BUCKET}/telemetry/year=.../month=.../day=.../hour=.../"
    info "  Format: newline-delimited JSON, GZIP compressed"

    info "Waiting for Firehose to become ACTIVE..."
    aws firehose describe-delivery-stream \
        --delivery-stream-name "$FIREHOSE_STREAM" \
        --region "$REGION" \
        --query 'DeliveryStreamDescription.DeliveryStreamStatus' \
        --output text
    sleep 5
fi

# ==========================================================================
# Step 5: IAM Role for IoT → Firehose
# ==========================================================================
header "Step 5: IoT-to-Firehose IAM Role"

IOT_FIREHOSE_ROLE_ARN=""
if aws iam get-role --role-name "$IOT_FIREHOSE_ROLE_NAME" &>/dev/null; then
    IOT_FIREHOSE_ROLE_ARN=$(aws iam get-role --role-name "$IOT_FIREHOSE_ROLE_NAME" --query 'Role.Arn' --output text)
    pass "IoT Firehose role already exists: $IOT_FIREHOSE_ROLE_ARN"
else
    info "Creating IoT-to-Firehose IAM role..."

    FIREHOSE_ARN=$(aws firehose describe-delivery-stream \
        --delivery-stream-name "$FIREHOSE_STREAM" \
        --region "$REGION" \
        --query 'DeliveryStreamDescription.DeliveryStreamARN' --output text)

    IOT_FIREHOSE_ROLE_ARN=$(aws iam create-role \
        --role-name "$IOT_FIREHOSE_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "iot.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --query 'Role.Arn' --output text)

    aws iam put-role-policy \
        --role-name "$IOT_FIREHOSE_ROLE_NAME" \
        --policy-name "iot-firehose-put" \
        --policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [{
                \"Effect\": \"Allow\",
                \"Action\": \"firehose:PutRecord\",
                \"Resource\": \"${FIREHOSE_ARN}\"
            }]
        }"

    pass "Created IoT Firehose role: $IOT_FIREHOSE_ROLE_ARN"
    info "Waiting 10s for IAM role propagation..."
    sleep 10
fi

# ==========================================================================
# Step 6: IoT Topic Rule → Firehose
# ==========================================================================
header "Step 6: IoT Rule for Firehose"

IOT_RULE_EXISTS=$(aws iot get-topic-rule --rule-name "$IOT_RULE_NAME" --region "$REGION" 2>/dev/null && echo "yes" || echo "no")

FIREHOSE_ARN=$(aws firehose describe-delivery-stream \
    --delivery-stream-name "$FIREHOSE_STREAM" \
    --region "$REGION" \
    --query 'DeliveryStreamDescription.DeliveryStreamARN' --output text)

if [ "$IOT_RULE_EXISTS" = "yes" ]; then
    pass "IoT rule '$IOT_RULE_NAME' already exists"
else
    info "Creating IoT rule to route telemetry to Firehose..."
    aws iot create-topic-rule \
        --rule-name "$IOT_RULE_NAME" \
        --region "$REGION" \
        --topic-rule-payload "{
            \"sql\": \"SELECT * FROM 'coldtrack/sensors/+/telemetry'\",
            \"ruleDisabled\": false,
            \"awsIotSqlVersion\": \"2016-03-23\",
            \"actions\": [{
                \"firehose\": {
                    \"deliveryStreamName\": \"${FIREHOSE_STREAM}\",
                    \"roleArn\": \"${IOT_FIREHOSE_ROLE_ARN}\",
                    \"separator\": \"\n\"
                }
            }]
        }"

    pass "Created IoT rule '$IOT_RULE_NAME' → Firehose → S3"
fi

# ==========================================================================
# Step 7: Update Lambda with Timestream env vars
# ==========================================================================
header "Step 7: Update Lambda Environment"

info "Adding Timestream env vars to Lambda '$LAMBDA_FUNCTION'..."

# Get current env vars and merge with new ones
CURRENT_ENV=$(aws lambda get-function-configuration \
    --function-name "$LAMBDA_FUNCTION" \
    --region "$REGION" \
    --query 'Environment.Variables' --output json 2>/dev/null || echo '{}')

# Merge using Python (preserves existing vars, adds new ones)
MERGED_ENV=$(python3 -c "
import json, sys
current = json.loads('$CURRENT_ENV')
current['TIMESTREAM_DB'] = '$TIMESTREAM_DB'
current['TIMESTREAM_TABLE'] = '$TIMESTREAM_TABLE'
current['SNS_TOPIC_ARN'] = current.get('SNS_TOPIC_ARN', '')
print(json.dumps({'Variables': current}))
")

aws lambda update-function-configuration \
    --function-name "$LAMBDA_FUNCTION" \
    --region "$REGION" \
    --environment "$MERGED_ENV" \
    --output text &>/dev/null

pass "Lambda env vars updated (TIMESTREAM_DB=$TIMESTREAM_DB, TIMESTREAM_TABLE=$TIMESTREAM_TABLE)"

# ==========================================================================
# Step 8: Deploy Lambda Code
# ==========================================================================
header "Step 8: Deploy Lambda Code"

LAMBDA_DIR="${PROJECT_DIR}/lambda/process_violation"
ZIP_PATH="/tmp/coldtrack-process-violation.zip"

info "Packaging Lambda from $LAMBDA_DIR..."
cd "$LAMBDA_DIR"

# Install dependencies into package
pip3 install -r requirements.txt -t /tmp/lambda_package --quiet 2>/dev/null || true
cp -r /tmp/lambda_package/* /tmp/lambda_build/ 2>/dev/null || mkdir -p /tmp/lambda_build
cp index.py /tmp/lambda_build/

cd /tmp/lambda_build
zip -r "$ZIP_PATH" . -q
cd "$PROJECT_DIR"

info "Deploying Lambda code..."
aws lambda update-function-code \
    --function-name "$LAMBDA_FUNCTION" \
    --region "$REGION" \
    --zip-file "fileb://${ZIP_PATH}" \
    --output text &>/dev/null

# Update handler to match our code
aws lambda update-function-configuration \
    --function-name "$LAMBDA_FUNCTION" \
    --region "$REGION" \
    --handler "index.lambda_handler" \
    --output text &>/dev/null

pass "Lambda deployed with Timestream support"

# Cleanup
rm -rf /tmp/lambda_package /tmp/lambda_build "$ZIP_PATH"

# ==========================================================================
# Step 9: Add Timestream write permissions to Lambda role
# ==========================================================================
header "Step 9: Lambda Timestream Permissions"

LAMBDA_ROLE=$(aws lambda get-function-configuration \
    --function-name "$LAMBDA_FUNCTION" \
    --region "$REGION" \
    --query 'Configuration.Role' --output text 2>/dev/null || \
    aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION" \
        --region "$REGION" \
        --query 'Role' --output text)

LAMBDA_ROLE_NAME=$(echo "$LAMBDA_ROLE" | awk -F/ '{print $NF}')

info "Adding Timestream write permission to role '$LAMBDA_ROLE_NAME'..."
aws iam put-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-name "timestream-write" \
    --policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [{
            \"Effect\": \"Allow\",
            \"Action\": [
                \"timestream:WriteRecords\",
                \"timestream:DescribeEndpoints\",
                \"timestream:DescribeTable\",
                \"timestream:DescribeDatabase\"
            ],
            \"Resource\": [
                \"arn:aws:timestream:${REGION}:${ACCOUNT_ID}:database/${TIMESTREAM_DB}\",
                \"arn:aws:timestream:${REGION}:${ACCOUNT_ID}:database/${TIMESTREAM_DB}/table/${TIMESTREAM_TABLE}\"
            ]
        },{
            \"Effect\": \"Allow\",
            \"Action\": \"timestream:DescribeEndpoints\",
            \"Resource\": \"*\"
        }]
    }"

pass "Lambda has Timestream write permissions"

# ==========================================================================
# Summary
# ==========================================================================
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  ColdTrack Storage Pipeline Setup Complete${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  Data flow:"
echo "    ESP32 → IoT Core → Lambda → Timestream (hot queries)"
echo "                      → Firehose → S3 (ML training data)"
echo ""
echo "  Resources created:"
echo "    Timestream:  $TIMESTREAM_DB / $TIMESTREAM_TABLE"
echo "    S3 raw data: $S3_RAW_BUCKET"
echo "    S3 ML models:$S3_ML_BUCKET"
echo "    Firehose:    $FIREHOSE_STREAM"
echo "    IoT Rule:    $IOT_RULE_NAME"
echo ""
echo "  Next steps:"
echo "    1. Test the pipeline:"
echo "       python3 tests/test-storage-pipeline.py"
echo "    2. Set up Grafana dashboard:"
echo "       See docs/grafana-setup.md"
echo ""
