#!/bin/bash

##############################################################################
# ColdTrack Cold Chain Monitoring System - Infrastructure Deployment Script
# ==========================================================================
# Deploys the complete AWS infrastructure using Terraform.
#
# Usage:
#   ./scripts/deploy-infrastructure.sh [OPTIONS]
#
# Options:
#   --auto-approve     Skip confirmation prompt before applying
#   --destroy          Tear down all infrastructure
#   --plan-only        Run terraform plan without applying
#   -h, --help         Show this help message
#
# Environment Variables (optional):
#   ALERT_EMAIL        Email for SNS alert notifications
#   ALERT_PHONE        Phone number (E.164) for SMS alerts
#   TF_VAR_environment Deployment environment (default: development)
#
# Prerequisites:
#   - terraform >= 1.5.0
#   - aws cli v2
#   - jq
#   - python3
#   - Valid AWS credentials for eu-west-1
##############################################################################

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
LAMBDA_DIR="${PROJECT_ROOT}/lambda"
LAMBDA_PACKAGES_DIR="${TERRAFORM_DIR}/lambda_packages"
OUTPUTS_FILE="${PROJECT_ROOT}/deployment-outputs.json"

# ---------------------------------------------------------------------------
# Colors and formatting
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
# Flags (defaults)
# ---------------------------------------------------------------------------
AUTO_APPROVE=false
DESTROY=false
PLAN_ONLY=false

# ---------------------------------------------------------------------------
# Parse command-line arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --destroy)
            DESTROY=true
            shift
            ;;
        --plan-only)
            PLAN_ONLY=true
            shift
            ;;
        -h|--help)
            head -30 "$0" | tail -27
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR] Unknown option: $1${NC}"
            echo "Run with --help for usage information."
            exit 1
            ;;
    esac
done

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

# ---------------------------------------------------------------------------
# Prerequisite Checks
# ---------------------------------------------------------------------------
check_prerequisites() {
    log_header "Checking Prerequisites"

    local all_ok=true

    # Terraform
    if command -v terraform &> /dev/null; then
        local tf_version
        tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version // empty' 2>/dev/null || terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        log_success "Terraform installed (v${tf_version})"
    else
        log_error "Terraform is not installed. Install from https://developer.hashicorp.com/terraform/install"
        all_ok=false
    fi

    # AWS CLI
    if command -v aws &> /dev/null; then
        local aws_version
        aws_version=$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2)
        log_success "AWS CLI installed (v${aws_version})"
    else
        log_error "AWS CLI is not installed. Install from https://aws.amazon.com/cli/"
        all_ok=false
    fi

    # jq
    if command -v jq &> /dev/null; then
        log_success "jq installed ($(jq --version 2>&1))"
    else
        log_error "jq is not installed. Install: brew install jq (macOS) or apt-get install jq (Linux)"
        all_ok=false
    fi

    # Python3
    if command -v python3 &> /dev/null; then
        local py_version
        py_version=$(python3 --version 2>&1 | awk '{print $2}')
        log_success "Python3 installed (v${py_version})"
    else
        log_error "Python3 is not installed."
        all_ok=false
    fi

    if [ "$all_ok" = false ]; then
        die "One or more prerequisites are missing. Please install them and re-run."
    fi

    echo ""
    log_success "All prerequisites satisfied."
}

# ---------------------------------------------------------------------------
# Verify AWS Credentials
# ---------------------------------------------------------------------------
verify_aws_credentials() {
    log_header "Verifying AWS Credentials"

    log_step "Running aws sts get-caller-identity ..."
    local caller_id
    caller_id=$(aws sts get-caller-identity 2>&1) || die "AWS credentials are not configured or expired. Run 'aws configure' or set AWS_PROFILE."

    local account_id arn
    account_id=$(echo "$caller_id" | jq -r '.Account')
    arn=$(echo "$caller_id" | jq -r '.Arn')

    log_success "Authenticated successfully"
    log_info "Account : ${account_id}"
    log_info "ARN     : ${arn}"

    # Check if we can reach eu-west-1
    local region="${AWS_REGION:-eu-west-1}"
    log_step "Verifying access to region ${region} ..."
    if aws ec2 describe-regions --region-names "${region}" --output text &> /dev/null; then
        log_success "Region ${region} is accessible"
    else
        log_warn "Could not verify region ${region}. Deployment may still work if the region is enabled."
    fi
}

# ---------------------------------------------------------------------------
# Package Lambda Functions
# ---------------------------------------------------------------------------
package_lambda_functions() {
    log_header "Packaging Lambda Functions"

    mkdir -p "${LAMBDA_PACKAGES_DIR}"

    if [ ! -d "${LAMBDA_DIR}" ]; then
        log_warn "Lambda directory not found at ${LAMBDA_DIR}. Skipping Lambda packaging."
        return 0
    fi

    local count=0
    for func_dir in "${LAMBDA_DIR}"/*/; do
        [ ! -d "${func_dir}" ] && continue

        local func_name
        func_name=$(basename "${func_dir}")

        # Skip empty directories (no Python files)
        local has_code=false
        for ext in py js; do
            if ls "${func_dir}"*.${ext} &> /dev/null; then
                has_code=true
                break
            fi
        done

        if [ "$has_code" = false ]; then
            log_warn "Skipping ${func_name}/ -- no source files found"
            continue
        fi

        log_step "Packaging ${func_name} ..."

        local pkg_tmp_dir="/tmp/coldtrack_lambda_pkg_${func_name}"
        local zip_path="${LAMBDA_PACKAGES_DIR}/${func_name}.zip"

        # Clean previous build
        rm -rf "${pkg_tmp_dir}"
        mkdir -p "${pkg_tmp_dir}"

        # Install Python dependencies if requirements.txt exists
        if [ -f "${func_dir}/requirements.txt" ]; then
            local req_size
            req_size=$(wc -c < "${func_dir}/requirements.txt" | tr -d ' ')
            if [ "$req_size" -gt 1 ]; then
                log_info "  Installing dependencies from requirements.txt"
                python3 -m pip install -r "${func_dir}/requirements.txt" -t "${pkg_tmp_dir}" --quiet --disable-pip-version-check 2>/dev/null || {
                    log_warn "  pip install encountered warnings (non-fatal)"
                }
            fi
        fi

        # Copy function source files
        cp -r "${func_dir}"* "${pkg_tmp_dir}/" 2>/dev/null || true

        # Create zip package
        (cd "${pkg_tmp_dir}" && zip -r "${zip_path}" . > /dev/null 2>&1)

        local zip_size
        zip_size=$(du -h "${zip_path}" | awk '{print $1}')
        log_success "  ${func_name}.zip created (${zip_size})"

        # Cleanup temp
        rm -rf "${pkg_tmp_dir}"

        count=$((count + 1))
    done

    echo ""
    if [ "$count" -eq 0 ]; then
        log_warn "No Lambda functions were packaged."
    else
        log_success "Packaged ${count} Lambda function(s) into ${LAMBDA_PACKAGES_DIR}/"
    fi
}

# ---------------------------------------------------------------------------
# Build Terraform Variable Arguments
# ---------------------------------------------------------------------------
build_tf_var_args() {
    local tf_args=()

    # Pass ALERT_EMAIL if set
    if [ -n "${ALERT_EMAIL:-}" ]; then
        tf_args+=(-var "alert_email=${ALERT_EMAIL}")
        log_info "Using ALERT_EMAIL from environment"
    else
        log_warn "ALERT_EMAIL not set. Terraform will prompt or use default if defined."
    fi

    # Pass ALERT_PHONE if set
    if [ -n "${ALERT_PHONE:-}" ]; then
        tf_args+=(-var "alert_phone=${ALERT_PHONE}")
        log_info "Using ALERT_PHONE from environment"
    fi

    echo "${tf_args[@]:-}"
}

# ---------------------------------------------------------------------------
# Terraform Init
# ---------------------------------------------------------------------------
terraform_init() {
    log_header "Initializing Terraform"

    log_step "Running terraform init in ${TERRAFORM_DIR} ..."
    (cd "${TERRAFORM_DIR}" && terraform init -input=false -no-color 2>&1) | while IFS= read -r line; do
        echo -e "  ${DIM}${line}${NC}"
    done

    log_success "Terraform initialized successfully."
}

# ---------------------------------------------------------------------------
# Terraform Plan
# ---------------------------------------------------------------------------
terraform_plan() {
    log_header "Planning Infrastructure Changes"

    local tf_var_args
    tf_var_args=$(build_tf_var_args)

    log_step "Running terraform plan ..."
    echo ""

    local plan_exit=0
    # shellcheck disable=SC2086
    (cd "${TERRAFORM_DIR}" && terraform plan \
        -input=false \
        -out=tfplan \
        ${tf_var_args} \
        -no-color 2>&1) | while IFS= read -r line; do
        # Highlight additions/destructions
        if echo "$line" | grep -qE '^\s*\+'; then
            echo -e "  ${GREEN}${line}${NC}"
        elif echo "$line" | grep -qE '^\s*\-'; then
            echo -e "  ${RED}${line}${NC}"
        elif echo "$line" | grep -qE '^\s*~'; then
            echo -e "  ${YELLOW}${line}${NC}"
        else
            echo -e "  ${line}"
        fi
    done || plan_exit=$?

    if [ "$plan_exit" -ne 0 ]; then
        die "Terraform plan failed. Review the output above."
    fi

    echo ""
    log_success "Terraform plan completed. Plan saved to ${TERRAFORM_DIR}/tfplan"
}

# ---------------------------------------------------------------------------
# Terraform Apply
# ---------------------------------------------------------------------------
terraform_apply() {
    log_header "Applying Infrastructure Changes"

    if [ "$PLAN_ONLY" = true ]; then
        log_info "Plan-only mode: skipping apply."
        return 0
    fi

    # Confirmation prompt (unless --auto-approve)
    if [ "$AUTO_APPROVE" = false ]; then
        echo ""
        echo -e "${YELLOW}${BOLD}  You are about to apply Terraform changes to your AWS account.${NC}"
        echo -e "${YELLOW}  This will create, modify, or destroy cloud resources.${NC}"
        echo ""
        read -rp "  Do you want to proceed? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Deployment cancelled by user."
            exit 0
        fi
        echo ""
    fi

    log_step "Running terraform apply ..."

    local apply_exit=0
    (cd "${TERRAFORM_DIR}" && terraform apply \
        -input=false \
        -auto-approve \
        tfplan \
        -no-color 2>&1) | while IFS= read -r line; do
        if echo "$line" | grep -qE 'Creation complete|creation complete'; then
            echo -e "  ${GREEN}${line}${NC}"
        elif echo "$line" | grep -qE 'Destruction complete|destruction complete'; then
            echo -e "  ${RED}${line}${NC}"
        elif echo "$line" | grep -qE 'Error|error'; then
            echo -e "  ${RED}${line}${NC}"
        else
            echo -e "  ${DIM}${line}${NC}"
        fi
    done || apply_exit=$?

    if [ "$apply_exit" -ne 0 ]; then
        die "Terraform apply failed. Review the output above."
    fi

    echo ""
    log_success "Terraform apply completed successfully."
}

# ---------------------------------------------------------------------------
# Terraform Destroy
# ---------------------------------------------------------------------------
terraform_destroy() {
    log_header "Destroying Infrastructure"

    local tf_var_args
    tf_var_args=$(build_tf_var_args)

    if [ "$AUTO_APPROVE" = false ]; then
        echo ""
        echo -e "${RED}${BOLD}  WARNING: This will DESTROY all ColdTrack infrastructure!${NC}"
        echo -e "${RED}  This action is irreversible.${NC}"
        echo ""
        read -rp "  Type 'destroy' to confirm: " confirm
        if [ "$confirm" != "destroy" ]; then
            log_info "Destroy cancelled by user."
            exit 0
        fi
        echo ""
    fi

    log_step "Running terraform destroy ..."

    # shellcheck disable=SC2086
    (cd "${TERRAFORM_DIR}" && terraform destroy \
        -input=false \
        -auto-approve \
        ${tf_var_args} \
        -no-color 2>&1) | while IFS= read -r line; do
        echo -e "  ${DIM}${line}${NC}"
    done

    log_success "Infrastructure destroyed."
}

# ---------------------------------------------------------------------------
# Save Terraform Outputs
# ---------------------------------------------------------------------------
save_outputs() {
    log_header "Saving Deployment Outputs"

    log_step "Extracting terraform output ..."

    local outputs
    outputs=$(cd "${TERRAFORM_DIR}" && terraform output -json 2>/dev/null) || {
        log_warn "No Terraform outputs available (this is normal for a minimal config)."
        # Write an empty JSON so downstream tools don't fail
        echo '{}' > "${OUTPUTS_FILE}"
        return 0
    }

    # Enrich with metadata
    local enriched
    enriched=$(jq -n \
        --argjson outputs "${outputs}" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg region "${AWS_REGION:-eu-west-1}" \
        --arg project "coldtrack" \
        '{
            metadata: {
                deployed_at: $timestamp,
                region: $region,
                project: $project
            },
            outputs: $outputs
        }')

    echo "$enriched" > "${OUTPUTS_FILE}"
    log_success "Outputs saved to ${OUTPUTS_FILE}"
}

# ---------------------------------------------------------------------------
# Display Deployment Summary
# ---------------------------------------------------------------------------
display_summary() {
    log_header "Deployment Summary"

    echo -e "  ${GREEN}${BOLD}ColdTrack infrastructure has been deployed successfully.${NC}"
    echo ""

    # Show key outputs if the file is non-trivial
    if [ -f "${OUTPUTS_FILE}" ]; then
        local output_count
        output_count=$(jq '.outputs | length' "${OUTPUTS_FILE}" 2>/dev/null || echo "0")
        if [ "$output_count" -gt 0 ]; then
            echo -e "  ${BOLD}Key Outputs:${NC}"
            jq -r '.outputs | to_entries[] | "    \(.key): \(.value.value // .value)"' "${OUTPUTS_FILE}" 2>/dev/null || true
            echo ""
        fi
    fi

    echo -e "  ${BOLD}Files:${NC}"
    echo -e "    Outputs file : ${OUTPUTS_FILE}"
    echo -e "    Terraform dir: ${TERRAFORM_DIR}"
    echo ""
    echo -e "  ${BOLD}Next Steps:${NC}"
    echo -e "    1. Provision a device : ./scripts/provision-device.sh ESP32_001"
    echo -e "    2. Check system health: ./scripts/check-system-health.sh"
    echo -e "    3. Simulate a device  : python3 scripts/simulate-device.py --help"
    echo ""
    echo -e "  ${BOLD}Useful Commands:${NC}"
    echo -e "    View state  : cd terraform && terraform show"
    echo -e "    View outputs: cd terraform && terraform output"
    echo -e "    Destroy     : ./scripts/deploy-infrastructure.sh --destroy"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_header "ColdTrack Infrastructure Deployment"
    echo -e "  ${DIM}Project root : ${PROJECT_ROOT}${NC}"
    echo -e "  ${DIM}Terraform dir: ${TERRAFORM_DIR}${NC}"
    echo -e "  ${DIM}Region       : ${AWS_REGION:-eu-west-1}${NC}"
    echo -e "  ${DIM}Timestamp    : $(date -u +"%Y-%m-%dT%H:%M:%SZ")${NC}"
    echo ""

    check_prerequisites
    verify_aws_credentials

    if [ "$DESTROY" = true ]; then
        terraform_init
        terraform_destroy
        log_success "Infrastructure teardown complete."
        exit 0
    fi

    package_lambda_functions
    terraform_init
    terraform_plan
    terraform_apply
    save_outputs
    display_summary

    log_success "Deployment finished at $(date -u +"%H:%M:%S UTC")."
}

main "$@"
