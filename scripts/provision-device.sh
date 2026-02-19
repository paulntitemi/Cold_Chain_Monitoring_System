#!/bin/bash

##############################################################################
# ColdTrack Cold Chain Monitoring System - Device Provisioning Script
# ==========================================================================
# Provisions a new ESP32 sensor device with AWS IoT Core, creating the
# necessary Thing, certificates, policies, and configuration files.
#
# Usage:
#   ./scripts/provision-device.sh <DEVICE_ID> [OPTIONS]
#
# Arguments:
#   DEVICE_ID          Unique identifier for the device (e.g., ESP32_001)
#
# Options:
#   --region REGION    AWS region (default: eu-west-1)
#   --thing-type TYPE  IoT Thing Type (default: coldtrack-esp32-sensor)
#   --policy NAME      IoT Policy name (default: coldtrack-sensor-policy)
#   --force            Overwrite existing certificates
#   -h, --help         Show this help message
#
# Output:
#   Certificates and config are saved to:
#     esp32/certificates/<DEVICE_ID>/
#
# Prerequisites:
#   - aws cli v2
#   - jq
#   - curl or wget
#   - Valid AWS credentials
##############################################################################

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AMAZON_ROOT_CA_URL="https://www.amazontrust.com/repository/AmazonRootCA1.pem"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEVICE_ID=""
REGION="eu-west-1"
THING_TYPE="coldtrack-esp32-sensor"
POLICY_NAME="coldtrack-sensor-policy"
FORCE=false

# ---------------------------------------------------------------------------
# Parse Arguments
# ---------------------------------------------------------------------------
show_help() {
    head -28 "$0" | tail -25
    exit 0
}

if [[ $# -lt 1 ]]; then
    echo -e "${RED}[ERROR] Device ID is required.${NC}"
    echo ""
    echo "Usage: $0 <DEVICE_ID> [--region REGION] [--thing-type TYPE] [--policy NAME] [--force]"
    echo "Example: $0 ESP32_001"
    exit 1
fi

# First positional argument is device ID
DEVICE_ID="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --region)
            REGION="$2"
            shift 2
            ;;
        --thing-type)
            THING_TYPE="$2"
            shift 2
            ;;
        --policy)
            POLICY_NAME="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}[ERROR] Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------
CERT_DIR="${PROJECT_ROOT}/esp32/certificates/${DEVICE_ID}"

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------
timestamp() {
    date "+%H:%M:%S"
}

log_header() {
    echo ""
    echo -e "${BLUE}${BOLD}============================================================${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}============================================================${NC}"
    echo ""
}

log_step() {
    echo -e "${CYAN}[$(timestamp)] >> $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(timestamp)] [PASS] $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[$(timestamp)] [WARN] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(timestamp)] [FAIL] $1${NC}"
}

log_info() {
    echo -e "${DIM}[$(timestamp)] [INFO] $1${NC}"
}

die() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial provisioning failures
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        log_error "Provisioning failed. Partial resources may have been created."
        log_info "To clean up, manually check AWS IoT Core in region ${REGION}."
        if [ -d "${CERT_DIR}" ] && [ "$FORCE" = false ]; then
            log_info "Certificate directory: ${CERT_DIR}"
        fi
    fi
}
trap cleanup_on_error EXIT

# ---------------------------------------------------------------------------
# Step 1: Validate Prerequisites
# ---------------------------------------------------------------------------
validate_prerequisites() {
    log_header "Step 1/8: Validating Prerequisites"

    # AWS CLI
    if ! command -v aws &> /dev/null; then
        die "AWS CLI is not installed. Install from https://aws.amazon.com/cli/"
    fi
    log_success "AWS CLI installed"

    # jq
    if ! command -v jq &> /dev/null; then
        die "jq is not installed. Install: brew install jq (macOS) or apt-get install jq (Linux)"
    fi
    log_success "jq installed"

    # curl or wget
    if command -v curl &> /dev/null; then
        DOWNLOAD_CMD="curl"
        log_success "curl available for downloads"
    elif command -v wget &> /dev/null; then
        DOWNLOAD_CMD="wget"
        log_success "wget available for downloads"
    else
        die "Neither curl nor wget is installed."
    fi

    # AWS credentials
    log_step "Verifying AWS credentials ..."
    if ! aws sts get-caller-identity --region "${REGION}" &> /dev/null; then
        die "AWS credentials are invalid or expired. Run 'aws configure'."
    fi
    log_success "AWS credentials are valid"

    # Check if certificate directory already exists
    if [ -d "${CERT_DIR}" ] && [ "$FORCE" = false ]; then
        if ls "${CERT_DIR}"/*.pem* &> /dev/null 2>&1; then
            die "Certificates already exist for ${DEVICE_ID} at ${CERT_DIR}. Use --force to overwrite."
        fi
    fi
}

# ---------------------------------------------------------------------------
# Step 2: Create Thing Type (if needed)
# ---------------------------------------------------------------------------
create_thing_type() {
    log_header "Step 2/8: Creating Thing Type"

    log_step "Checking if thing type '${THING_TYPE}' exists ..."

    if aws iot describe-thing-type \
        --thing-type-name "${THING_TYPE}" \
        --region "${REGION}" &> /dev/null; then
        log_info "Thing type '${THING_TYPE}' already exists"
    else
        log_step "Creating thing type '${THING_TYPE}' ..."
        aws iot create-thing-type \
            --thing-type-name "${THING_TYPE}" \
            --thing-type-properties "thingTypeDescription=ColdTrack ESP32 temperature sensor for cold chain monitoring,searchableAttributes=device_id,location,firmware_version" \
            --region "${REGION}" > /dev/null

        log_success "Thing type '${THING_TYPE}' created"
    fi
}

# ---------------------------------------------------------------------------
# Step 3: Create IoT Thing
# ---------------------------------------------------------------------------
create_iot_thing() {
    log_header "Step 3/8: Creating IoT Thing"

    log_step "Creating thing '${DEVICE_ID}' with type '${THING_TYPE}' ..."

    if aws iot describe-thing \
        --thing-name "${DEVICE_ID}" \
        --region "${REGION}" &> /dev/null; then
        log_warn "Thing '${DEVICE_ID}' already exists. Continuing with existing thing."
    else
        aws iot create-thing \
            --thing-name "${DEVICE_ID}" \
            --thing-type-name "${THING_TYPE}" \
            --attribute-payload "attributes={provisioned_at=$(date -u +%Y-%m-%dT%H:%M:%SZ),provisioned_by=provision-device-script}" \
            --region "${REGION}" > /dev/null

        log_success "IoT Thing '${DEVICE_ID}' created"
    fi
}

# ---------------------------------------------------------------------------
# Step 4: Generate Certificates
# ---------------------------------------------------------------------------
generate_certificates() {
    log_header "Step 4/8: Generating Device Certificates"

    mkdir -p "${CERT_DIR}"

    log_step "Creating keys and certificate ..."

    local cert_output
    cert_output=$(aws iot create-keys-and-certificate \
        --set-as-active \
        --region "${REGION}" \
        --output json) || die "Failed to create keys and certificate"

    # Extract certificate components
    local cert_arn cert_id
    cert_arn=$(echo "$cert_output" | jq -r '.certificateArn')
    cert_id=$(echo "$cert_output" | jq -r '.certificateId')

    if [ -z "$cert_arn" ] || [ "$cert_arn" = "null" ]; then
        die "Failed to extract certificate ARN from response."
    fi

    # Save certificate PEM
    echo "$cert_output" | jq -r '.certificatePem' > "${CERT_DIR}/certificate.pem.crt"
    log_success "Certificate saved to ${CERT_DIR}/certificate.pem.crt"

    # Save private key
    echo "$cert_output" | jq -r '.keyPair.PrivateKey' > "${CERT_DIR}/private.pem.key"
    chmod 600 "${CERT_DIR}/private.pem.key"
    log_success "Private key saved to ${CERT_DIR}/private.pem.key"

    # Save public key
    echo "$cert_output" | jq -r '.keyPair.PublicKey' > "${CERT_DIR}/public.pem.key"
    log_success "Public key saved to ${CERT_DIR}/public.pem.key"

    # Save certificate ARN and ID for later steps
    echo "$cert_arn" > "${CERT_DIR}/certificate_arn.txt"
    echo "$cert_id" > "${CERT_DIR}/certificate_id.txt"

    log_info "Certificate ARN: ${cert_arn}"
    log_info "Certificate ID : ${cert_id}"

    # Export for subsequent steps
    CERT_ARN="$cert_arn"
}

# ---------------------------------------------------------------------------
# Step 5: Download Amazon Root CA
# ---------------------------------------------------------------------------
download_root_ca() {
    log_header "Step 5/8: Downloading Amazon Root CA"

    local ca_path="${CERT_DIR}/AmazonRootCA1.pem"

    if [ -f "${ca_path}" ] && [ "$FORCE" = false ]; then
        log_info "Root CA already exists at ${ca_path}"
        return 0
    fi

    log_step "Downloading from ${AMAZON_ROOT_CA_URL} ..."

    if [ "$DOWNLOAD_CMD" = "curl" ]; then
        curl -sS -o "${ca_path}" "${AMAZON_ROOT_CA_URL}" || die "Failed to download Amazon Root CA"
    else
        wget -q -O "${ca_path}" "${AMAZON_ROOT_CA_URL}" || die "Failed to download Amazon Root CA"
    fi

    # Verify the CA file is not empty
    if [ ! -s "${ca_path}" ]; then
        die "Downloaded Root CA file is empty."
    fi

    log_success "Amazon Root CA saved to ${ca_path}"
}

# ---------------------------------------------------------------------------
# Step 6: Create / Attach IoT Policy
# ---------------------------------------------------------------------------
setup_iot_policy() {
    log_header "Step 6/8: Setting Up IoT Policy"

    log_step "Checking if policy '${POLICY_NAME}' exists ..."

    if aws iot get-policy \
        --policy-name "${POLICY_NAME}" \
        --region "${REGION}" &> /dev/null; then
        log_info "Policy '${POLICY_NAME}' already exists"
    else
        log_step "Creating policy '${POLICY_NAME}' ..."

        local policy_doc
        policy_doc=$(cat <<'POLICY_EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "iot:Connect",
            "Resource": "*",
            "Condition": {
                "Bool": {
                    "iot:Connection.Thing.IsAttached": "true"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "iot:Publish",
            "Resource": [
                "arn:aws:iot:*:*:topic/coldtrack/sensors/*/telemetry",
                "arn:aws:iot:*:*:topic/coldtrack/sensors/*/alerts",
                "arn:aws:iot:*:*:topic/coldtrack/sensors/*/status"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "iot:Subscribe",
            "Resource": [
                "arn:aws:iot:*:*:topicfilter/coldtrack/commands/*",
                "arn:aws:iot:*:*:topicfilter/coldtrack/config/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "iot:Receive",
            "Resource": [
                "arn:aws:iot:*:*:topic/coldtrack/commands/*",
                "arn:aws:iot:*:*:topic/coldtrack/config/*"
            ]
        }
    ]
}
POLICY_EOF
        )

        aws iot create-policy \
            --policy-name "${POLICY_NAME}" \
            --policy-document "${policy_doc}" \
            --region "${REGION}" > /dev/null || die "Failed to create IoT policy"

        log_success "Policy '${POLICY_NAME}' created"
    fi

    # Attach policy to certificate
    log_step "Attaching policy '${POLICY_NAME}' to certificate ..."
    aws iot attach-policy \
        --policy-name "${POLICY_NAME}" \
        --target "${CERT_ARN}" \
        --region "${REGION}" 2>/dev/null || {
            log_warn "Policy may already be attached to this certificate."
        }
    log_success "Policy attached to certificate"
}

# ---------------------------------------------------------------------------
# Step 7: Attach Certificate to Thing
# ---------------------------------------------------------------------------
attach_certificate_to_thing() {
    log_header "Step 7/8: Attaching Certificate to Thing"

    log_step "Attaching certificate to thing '${DEVICE_ID}' ..."

    aws iot attach-thing-principal \
        --thing-name "${DEVICE_ID}" \
        --principal "${CERT_ARN}" \
        --region "${REGION}" || die "Failed to attach certificate to thing"

    log_success "Certificate attached to thing '${DEVICE_ID}'"
}

# ---------------------------------------------------------------------------
# Step 8: Get Endpoint & Generate Device Config
# ---------------------------------------------------------------------------
generate_device_config() {
    log_header "Step 8/8: Generating Device Configuration"

    # Get IoT endpoint
    log_step "Retrieving IoT endpoint for region ${REGION} ..."

    local iot_endpoint
    iot_endpoint=$(aws iot describe-endpoint \
        --endpoint-type iot:Data-ATS \
        --region "${REGION}" \
        --query 'endpointAddress' \
        --output text) || die "Failed to get IoT endpoint"

    log_success "IoT Endpoint: ${iot_endpoint}"

    # Save endpoint
    echo "${iot_endpoint}" > "${CERT_DIR}/iot_endpoint.txt"

    # Generate device configuration JSON
    log_step "Generating device configuration file ..."

    local config_file="${CERT_DIR}/device_config.json"

    cat > "${config_file}" <<CONFIG_EOF
{
    "device_id": "${DEVICE_ID}",
    "client_id": "${DEVICE_ID}",
    "iot_endpoint": "${iot_endpoint}",
    "region": "${REGION}",
    "mqtt": {
        "port": 8883,
        "keep_alive_seconds": 30,
        "ping_timeout_ms": 3000,
        "protocol": "mqtt"
    },
    "certificates": {
        "root_ca": "AmazonRootCA1.pem",
        "certificate": "certificate.pem.crt",
        "private_key": "private.pem.key"
    },
    "topics": {
        "telemetry": "coldtrack/sensors/${DEVICE_ID}/telemetry",
        "alerts": "coldtrack/sensors/${DEVICE_ID}/alerts",
        "status": "coldtrack/sensors/${DEVICE_ID}/status",
        "commands": "coldtrack/commands/${DEVICE_ID}",
        "config": "coldtrack/config/${DEVICE_ID}"
    },
    "telemetry": {
        "publish_interval_seconds": 5,
        "temperature_unit": "celsius",
        "gps_enabled": true
    },
    "thresholds": {
        "temp_min_celsius": 2.0,
        "temp_max_celsius": 8.0,
        "freeze_threshold_celsius": 0.0,
        "battery_low_percent": 20,
        "battery_critical_percent": 5
    },
    "provisioned_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "certificate_arn": "${CERT_ARN}"
}
CONFIG_EOF

    log_success "Device config saved to ${config_file}"
}

# ---------------------------------------------------------------------------
# Display Summary
# ---------------------------------------------------------------------------
display_summary() {
    log_header "Provisioning Complete"

    echo -e "  ${GREEN}${BOLD}Device '${DEVICE_ID}' has been provisioned successfully.${NC}"
    echo ""
    echo -e "  ${BOLD}Device Details:${NC}"
    echo -e "    Device ID     : ${DEVICE_ID}"
    echo -e "    Thing Type    : ${THING_TYPE}"
    echo -e "    Region        : ${REGION}"
    echo -e "    Policy        : ${POLICY_NAME}"

    if [ -f "${CERT_DIR}/iot_endpoint.txt" ]; then
        echo -e "    IoT Endpoint  : $(cat "${CERT_DIR}/iot_endpoint.txt")"
    fi

    echo ""
    echo -e "  ${BOLD}Certificate Files:${NC}"
    echo -e "    Directory     : ${CERT_DIR}/"
    echo -e "    Certificate   : certificate.pem.crt"
    echo -e "    Private Key   : private.pem.key"
    echo -e "    Public Key    : public.pem.key"
    echo -e "    Root CA       : AmazonRootCA1.pem"
    echo -e "    Device Config : device_config.json"
    echo ""
    echo -e "  ${BOLD}Next Steps:${NC}"
    echo -e "    1. Copy certificates to your ESP32 device:"
    echo -e "       ${DIM}scp -r ${CERT_DIR}/ user@device:/path/to/certs/${NC}"
    echo ""
    echo -e "    2. Test with the device simulator:"
    echo -e "       ${DIM}python3 scripts/simulate-device.py \\"
    echo -e "         --device-id ${DEVICE_ID} \\"
    echo -e "         --endpoint $(cat "${CERT_DIR}/iot_endpoint.txt" 2>/dev/null || echo '<endpoint>') \\"
    echo -e "         --cert ${CERT_DIR}/certificate.pem.crt \\"
    echo -e "         --key ${CERT_DIR}/private.pem.key \\"
    echo -e "         --ca ${CERT_DIR}/AmazonRootCA1.pem${NC}"
    echo ""
    echo -e "    3. Flash the ESP32 firmware with the certificate paths."
    echo ""
    echo -e "  ${YELLOW}${BOLD}IMPORTANT:${NC} ${YELLOW}Keep your private key secure. Never commit it to Git.${NC}"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_header "ColdTrack Device Provisioning"
    echo -e "  ${DIM}Device ID  : ${DEVICE_ID}${NC}"
    echo -e "  ${DIM}Region     : ${REGION}${NC}"
    echo -e "  ${DIM}Thing Type : ${THING_TYPE}${NC}"
    echo -e "  ${DIM}Policy     : ${POLICY_NAME}${NC}"
    echo -e "  ${DIM}Cert Dir   : ${CERT_DIR}${NC}"
    echo ""

    validate_prerequisites
    create_thing_type
    create_iot_thing
    generate_certificates
    download_root_ca
    setup_iot_policy
    attach_certificate_to_thing
    generate_device_config
    display_summary

    log_success "Device provisioning finished at $(date -u +"%H:%M:%S UTC")."
}

main
