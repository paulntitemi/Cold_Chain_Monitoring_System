#!/bin/bash
##############################################################################
# ColdTrack IoT Connection Test Runner
# Reads .env configuration and runs the MQTT connectivity test.
#
# Usage:
#   ./run-test.sh                  # Use settings from .env
#   ./run-test.sh --validate-only  # Only validate config, don't connect
##############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
VENV_DIR="${SCRIPT_DIR}/venv"
TEST_SCRIPT="${SCRIPT_DIR}/tests/test-iot-connection.py"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
if [ ! -f "${ENV_FILE}" ]; then
    echo -e "${RED}[ERROR] .env file not found at ${ENV_FILE}${NC}"
    echo "  Copy config/.env.example to .env and fill in your values."
    exit 1
fi

# Source .env (skip comments, handle values without export)
set -a
while IFS='=' read -r key value; do
    # Skip comments and blank lines
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    # Trim whitespace
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    export "$key=$value"
done < "${ENV_FILE}"
set +a

# ---------------------------------------------------------------------------
# Validate required variables
# ---------------------------------------------------------------------------
MISSING=false

check_var() {
    local var_name="$1"
    local var_value="${!var_name:-}"
    if [ -z "$var_value" ]; then
        echo -e "${RED}[FAIL] ${var_name} is not set in .env${NC}"
        MISSING=true
    fi
}

echo -e "${CYAN}>> Checking .env configuration...${NC}"

check_var "AWS_IOT_ENDPOINT"
check_var "DEVICE_ID"
check_var "ROOT_CA_PATH"
check_var "CERTIFICATE_PATH"
check_var "PRIVATE_KEY_PATH"

if [ "$MISSING" = true ]; then
    echo -e "${RED}[ERROR] Missing required configuration. Fix .env and retry.${NC}"
    exit 1
fi

# Resolve paths relative to project root
ROOT_CA="${SCRIPT_DIR}/${ROOT_CA_PATH}"
CERT="${SCRIPT_DIR}/${CERTIFICATE_PATH}"
KEY="${SCRIPT_DIR}/${PRIVATE_KEY_PATH}"
CLIENT="${CLIENT_ID:-${DEVICE_ID}}"

# Validate certificate files exist
FILES_OK=true
for label_path in "Root CA:${ROOT_CA}" "Certificate:${CERT}" "Private Key:${KEY}"; do
    label="${label_path%%:*}"
    fpath="${label_path#*:}"
    if [ -f "$fpath" ]; then
        size=$(wc -c < "$fpath" | tr -d ' ')
        echo -e "  ${GREEN}[OK]${NC} ${label}: ${fpath} (${size} bytes)"
    else
        echo -e "  ${RED}[FAIL]${NC} ${label}: ${fpath} (NOT FOUND)"
        FILES_OK=false
    fi
done

if [ "$FILES_OK" = false ]; then
    echo -e "\n${RED}[ERROR] Certificate files missing. Check paths in .env.${NC}"
    exit 1
fi

echo -e "  ${GREEN}[OK]${NC} Endpoint: ${AWS_IOT_ENDPOINT}"
echo -e "  ${GREEN}[OK]${NC} Device:   ${CLIENT}"
echo ""

# ---------------------------------------------------------------------------
# Validate-only mode
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--validate-only" ]; then
    echo -e "${GREEN}[PASS] Configuration is valid.${NC}"
    exit 0
fi

# ---------------------------------------------------------------------------
# Activate venv and run test
# ---------------------------------------------------------------------------
if [ ! -d "${VENV_DIR}" ]; then
    echo -e "${RED}[ERROR] Python venv not found at ${VENV_DIR}${NC}"
    echo "  Create it with: python3 -m venv venv && source venv/bin/activate && pip install awsiotsdk"
    exit 1
fi

echo -e "${CYAN}>> Activating venv and running connection test...${NC}"
echo ""

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

python3 "${TEST_SCRIPT}" \
    --endpoint "${AWS_IOT_ENDPOINT}" \
    --client-id "${CLIENT}" \
    --cert "${CERT}" \
    --key "${KEY}" \
    --ca "${ROOT_CA}"

EXIT_CODE=$?

deactivate 2>/dev/null || true

exit ${EXIT_CODE}
