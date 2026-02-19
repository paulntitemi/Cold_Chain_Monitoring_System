#!/bin/bash

##############################################################################
# ColdTrack Cold Chain Monitoring System - System Health Check
# ==========================================================================
# Performs a comprehensive health check of all ColdTrack infrastructure
# components, both cloud (AWS) and local (Docker services).
#
# Usage:
#   ./scripts/check-system-health.sh [OPTIONS]
#
# Options:
#   --region REGION    AWS region (default: eu-west-1)
#   --verbose          Show detailed output for each check
#   --json             Output results as JSON
#   -h, --help         Show this help message
#
# Exit Codes:
#   0  All critical checks passed
#   1  One or more critical checks failed
#   2  Script error / prerequisites missing
##############################################################################

set -uo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

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
REGION="eu-west-1"
VERBOSE=false
JSON_OUTPUT=false

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0
CRITICAL_FAIL=false

# Results array for JSON output
declare -a RESULTS=()

# ---------------------------------------------------------------------------
# Parse Arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --region)
            REGION="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        -h|--help)
            head -22 "$0" | tail -19
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR] Unknown option: $1${NC}"
            exit 2
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
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${BLUE}${BOLD}------------------------------------------------------------${NC}"
        echo -e "${BLUE}${BOLD}  $1${NC}"
        echo -e "${BLUE}${BOLD}------------------------------------------------------------${NC}"
    fi
}

record_result() {
    local component="$1"
    local status="$2"   # PASS, FAIL, WARN, SKIP
    local message="$3"
    local critical="${4:-true}"

    case "$status" in
        PASS)
            PASS_COUNT=$((PASS_COUNT + 1))
            if [ "$JSON_OUTPUT" = false ]; then
                echo -e "  ${GREEN}[PASS]${NC} ${component}: ${message}"
            fi
            ;;
        FAIL)
            FAIL_COUNT=$((FAIL_COUNT + 1))
            if [ "$critical" = "true" ]; then
                CRITICAL_FAIL=true
            fi
            if [ "$JSON_OUTPUT" = false ]; then
                echo -e "  ${RED}[FAIL]${NC} ${component}: ${message}"
            fi
            ;;
        WARN)
            WARN_COUNT=$((WARN_COUNT + 1))
            if [ "$JSON_OUTPUT" = false ]; then
                echo -e "  ${YELLOW}[WARN]${NC} ${component}: ${message}"
            fi
            ;;
        SKIP)
            SKIP_COUNT=$((SKIP_COUNT + 1))
            if [ "$JSON_OUTPUT" = false ]; then
                echo -e "  ${DIM}[SKIP]${NC} ${component}: ${message}"
            fi
            ;;
    esac

    RESULTS+=("{\"component\":\"${component}\",\"status\":\"${status}\",\"message\":\"${message}\",\"critical\":${critical}}")
}

verbose_output() {
    if [ "$VERBOSE" = true ] && [ "$JSON_OUTPUT" = false ]; then
        echo -e "         ${DIM}$1${NC}"
    fi
}

# ---------------------------------------------------------------------------
# Check 1: AWS Credentials
# ---------------------------------------------------------------------------
check_aws_credentials() {
    log_header "AWS Credentials"

    if ! command -v aws &> /dev/null; then
        record_result "AWS CLI" "FAIL" "AWS CLI is not installed" "true"
        return
    fi

    local caller_id
    if caller_id=$(aws sts get-caller-identity --region "${REGION}" 2>&1); then
        local account_id arn
        account_id=$(echo "$caller_id" | jq -r '.Account' 2>/dev/null || echo "unknown")
        arn=$(echo "$caller_id" | jq -r '.Arn' 2>/dev/null || echo "unknown")
        record_result "AWS Credentials" "PASS" "Authenticated (account: ${account_id})"
        verbose_output "ARN: ${arn}"
    else
        record_result "AWS Credentials" "FAIL" "Invalid or expired credentials" "true"
    fi
}

# ---------------------------------------------------------------------------
# Check 2: IoT Core Endpoint
# ---------------------------------------------------------------------------
check_iot_endpoint() {
    log_header "AWS IoT Core"

    local endpoint
    if endpoint=$(aws iot describe-endpoint \
        --endpoint-type iot:Data-ATS \
        --region "${REGION}" \
        --query 'endpointAddress' \
        --output text 2>&1); then

        record_result "IoT Endpoint" "PASS" "${endpoint}"

        # Check reachability (DNS resolution + port 8883)
        local host
        host="${endpoint}"
        if command -v nc &> /dev/null; then
            if nc -z -w 5 "${host}" 8883 &> /dev/null; then
                record_result "IoT Reachability" "PASS" "Port 8883 reachable on ${host}"
            else
                record_result "IoT Reachability" "WARN" "Port 8883 not reachable (firewall or network)" "false"
            fi
        elif command -v timeout &> /dev/null; then
            if timeout 5 bash -c "echo >/dev/tcp/${host}/8883" &> /dev/null; then
                record_result "IoT Reachability" "PASS" "Port 8883 reachable on ${host}"
            else
                record_result "IoT Reachability" "WARN" "Port 8883 not reachable (firewall or network)" "false"
            fi
        else
            record_result "IoT Reachability" "SKIP" "No nc or timeout command available" "false"
        fi
    else
        record_result "IoT Endpoint" "FAIL" "Cannot retrieve IoT endpoint" "true"
    fi
}

# ---------------------------------------------------------------------------
# Check 3: IoT Things
# ---------------------------------------------------------------------------
check_iot_things() {
    log_header "IoT Things"

    local things_output
    if things_output=$(aws iot list-things \
        --region "${REGION}" \
        --output json 2>&1); then

        local thing_count
        thing_count=$(echo "$things_output" | jq '.things | length' 2>/dev/null || echo "0")

        if [ "$thing_count" -gt 0 ]; then
            record_result "IoT Things" "PASS" "${thing_count} thing(s) registered"

            if [ "$VERBOSE" = true ] && [ "$JSON_OUTPUT" = false ]; then
                echo "$things_output" | jq -r '.things[].thingName' 2>/dev/null | while IFS= read -r name; do
                    verbose_output "- ${name}"
                done
            fi
        else
            record_result "IoT Things" "WARN" "No things registered yet" "false"
        fi
    else
        record_result "IoT Things" "FAIL" "Cannot list IoT things" "true"
    fi
}

# ---------------------------------------------------------------------------
# Check 4: Lambda Functions
# ---------------------------------------------------------------------------
check_lambda_functions() {
    log_header "Lambda Functions"

    local expected_functions=("coldtrack-process-violation" "coldtrack-api-handler" "coldtrack-predictive-analytics" "coldtrack-blockchain-logger")
    local found_any=false

    # List all Lambda functions and filter by project prefix
    local all_functions
    if all_functions=$(aws lambda list-functions \
        --region "${REGION}" \
        --query 'Functions[?starts_with(FunctionName, `coldtrack`)]' \
        --output json 2>&1); then

        local func_count
        func_count=$(echo "$all_functions" | jq 'length' 2>/dev/null || echo "0")

        if [ "$func_count" -gt 0 ]; then
            found_any=true
            record_result "Lambda Functions" "PASS" "${func_count} ColdTrack function(s) found"

            # Check each function's state
            echo "$all_functions" | jq -r '.[] | "\(.FunctionName)|\(.State // "Active")|\(.Runtime // "unknown")"' 2>/dev/null | while IFS='|' read -r fname fstate fruntime; do
                if [ "$fstate" = "Active" ] || [ "$fstate" = "null" ]; then
                    record_result "  Lambda: ${fname}" "PASS" "Active (${fruntime})"
                else
                    record_result "  Lambda: ${fname}" "WARN" "State: ${fstate}" "false"
                fi
            done
        fi
    fi

    if [ "$found_any" = false ]; then
        record_result "Lambda Functions" "WARN" "No ColdTrack Lambda functions found (deploy infrastructure first)" "false"
    fi
}

# ---------------------------------------------------------------------------
# Check 5: SNS Topics
# ---------------------------------------------------------------------------
check_sns() {
    log_header "SNS Notifications"

    local topics_output
    if topics_output=$(aws sns list-topics \
        --region "${REGION}" \
        --output json 2>&1); then

        # Look for coldtrack topics
        local coldtrack_topics
        coldtrack_topics=$(echo "$topics_output" | jq -r '.Topics[].TopicArn' 2>/dev/null | grep -i "coldtrack" || true)

        if [ -n "$coldtrack_topics" ]; then
            local topic_count
            topic_count=$(echo "$coldtrack_topics" | wc -l | tr -d ' ')
            record_result "SNS Topics" "PASS" "${topic_count} ColdTrack topic(s) found"

            # Check subscriptions for each topic
            while IFS= read -r topic_arn; do
                local topic_name
                topic_name=$(echo "$topic_arn" | awk -F: '{print $NF}')

                local subs
                subs=$(aws sns list-subscriptions-by-topic \
                    --topic-arn "${topic_arn}" \
                    --region "${REGION}" \
                    --query 'Subscriptions[].{Protocol: Protocol, Status: SubscriptionArn}' \
                    --output json 2>/dev/null || echo "[]")

                local sub_count
                sub_count=$(echo "$subs" | jq 'length' 2>/dev/null || echo "0")

                if [ "$sub_count" -gt 0 ]; then
                    record_result "  SNS: ${topic_name}" "PASS" "${sub_count} subscription(s)"

                    if [ "$VERBOSE" = true ]; then
                        echo "$subs" | jq -r '.[] | "         \(.Protocol): \(.Status)"' 2>/dev/null | while IFS= read -r line; do
                            echo -e "  ${DIM}${line}${NC}"
                        done
                    fi
                else
                    record_result "  SNS: ${topic_name}" "WARN" "No subscriptions configured" "false"
                fi
            done <<< "$coldtrack_topics"
        else
            record_result "SNS Topics" "WARN" "No ColdTrack SNS topics found" "false"
        fi
    else
        record_result "SNS Topics" "FAIL" "Cannot list SNS topics" "true"
    fi
}

# ---------------------------------------------------------------------------
# Check 6: Timestream Database
# ---------------------------------------------------------------------------
check_timestream() {
    log_header "Timestream Database"

    # Timestream may not be available in eu-west-1; try the configured region
    local ts_region="${REGION}"

    local db_output
    if db_output=$(aws timestream-write describe-database \
        --database-name "coldtrack-telemetry" \
        --region "${ts_region}" \
        --output json 2>&1); then

        local db_name
        db_name=$(echo "$db_output" | jq -r '.Database.DatabaseName' 2>/dev/null || echo "unknown")
        record_result "Timestream Database" "PASS" "Database '${db_name}' exists"

        # Check for tables
        local tables
        if tables=$(aws timestream-write list-tables \
            --database-name "coldtrack-telemetry" \
            --region "${ts_region}" \
            --output json 2>&1); then

            local table_count
            table_count=$(echo "$tables" | jq '.Tables | length' 2>/dev/null || echo "0")

            if [ "$table_count" -gt 0 ]; then
                record_result "Timestream Tables" "PASS" "${table_count} table(s) in database"
                if [ "$VERBOSE" = true ]; then
                    echo "$tables" | jq -r '.Tables[].TableName' 2>/dev/null | while IFS= read -r tbl; do
                        verbose_output "- ${tbl}"
                    done
                fi
            else
                record_result "Timestream Tables" "WARN" "No tables found in database" "false"
            fi
        fi
    else
        # Check if it is a "not found" vs permission/region error
        if echo "$db_output" | grep -qi "ResourceNotFoundException\|does not exist"; then
            record_result "Timestream Database" "WARN" "Database 'coldtrack-telemetry' not found (deploy infrastructure first)" "false"
        elif echo "$db_output" | grep -qi "not supported\|not available\|UnrecognizedClient"; then
            record_result "Timestream Database" "SKIP" "Timestream may not be available in ${ts_region}" "false"
        else
            record_result "Timestream Database" "WARN" "Cannot verify Timestream: $(echo "$db_output" | head -1)" "false"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Check 7: API Gateway
# ---------------------------------------------------------------------------
check_api_gateway() {
    log_header "API Gateway"

    local apis
    if apis=$(aws apigatewayv2 get-apis \
        --region "${REGION}" \
        --output json 2>&1); then

        local coldtrack_apis
        coldtrack_apis=$(echo "$apis" | jq '[.Items[] | select(.Name | test("coldtrack";"i"))]' 2>/dev/null || echo "[]")
        local api_count
        api_count=$(echo "$coldtrack_apis" | jq 'length' 2>/dev/null || echo "0")

        if [ "$api_count" -gt 0 ]; then
            record_result "API Gateway" "PASS" "${api_count} ColdTrack API(s) found"

            echo "$coldtrack_apis" | jq -r '.[] | "\(.Name)|\(.ApiEndpoint // "N/A")"' 2>/dev/null | while IFS='|' read -r api_name api_endpoint; do
                record_result "  API: ${api_name}" "PASS" "${api_endpoint}"

                # Test endpoint reachability
                if [ -n "$api_endpoint" ] && [ "$api_endpoint" != "N/A" ] && command -v curl &> /dev/null; then
                    local http_code
                    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${api_endpoint}" 2>/dev/null || echo "000")
                    if [ "$http_code" != "000" ]; then
                        verbose_output "HTTP response: ${http_code}"
                    fi
                fi
            done
        else
            # Also try REST API (v1)
            local rest_apis
            rest_apis=$(aws apigateway get-rest-apis \
                --region "${REGION}" \
                --output json 2>&1 || echo '{"items":[]}')

            local rest_coldtrack
            rest_coldtrack=$(echo "$rest_apis" | jq '[.items[] | select(.name | test("coldtrack";"i"))]' 2>/dev/null || echo "[]")
            local rest_count
            rest_count=$(echo "$rest_coldtrack" | jq 'length' 2>/dev/null || echo "0")

            if [ "$rest_count" -gt 0 ]; then
                record_result "API Gateway (REST)" "PASS" "${rest_count} ColdTrack REST API(s) found"
            else
                record_result "API Gateway" "WARN" "No ColdTrack APIs found" "false"
            fi
        fi
    else
        record_result "API Gateway" "WARN" "Cannot list API Gateways" "false"
    fi
}

# ---------------------------------------------------------------------------
# Check 8: Local Docker Services (Optional)
# ---------------------------------------------------------------------------
check_local_services() {
    log_header "Local Services (Optional)"

    # Check InfluxDB at port 8086
    if command -v curl &> /dev/null; then
        local influx_status
        influx_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:8086/health" 2>/dev/null || echo "000")

        if [ "$influx_status" = "200" ]; then
            record_result "InfluxDB (localhost:8086)" "PASS" "Healthy (HTTP 200)" "false"
        elif [ "$influx_status" = "000" ]; then
            record_result "InfluxDB (localhost:8086)" "SKIP" "Not running or not reachable" "false"
        else
            record_result "InfluxDB (localhost:8086)" "WARN" "Responding with HTTP ${influx_status}" "false"
        fi

        # Check Grafana at port 3000
        local grafana_status
        grafana_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:3000/api/health" 2>/dev/null || echo "000")

        if [ "$grafana_status" = "200" ]; then
            record_result "Grafana (localhost:3000)" "PASS" "Healthy (HTTP 200)" "false"
        elif [ "$grafana_status" = "000" ]; then
            record_result "Grafana (localhost:3000)" "SKIP" "Not running or not reachable" "false"
        else
            record_result "Grafana (localhost:3000)" "WARN" "Responding with HTTP ${grafana_status}" "false"
        fi
    else
        record_result "Local Services" "SKIP" "curl not available for local checks" "false"
    fi

    # Check if Docker is running
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            local container_count
            container_count=$(docker ps --filter "label=project=coldtrack" --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
            if [ "$container_count" -gt 0 ]; then
                record_result "Docker Containers" "PASS" "${container_count} ColdTrack container(s) running" "false"
                if [ "$VERBOSE" = true ]; then
                    docker ps --filter "label=project=coldtrack" --format '  {{.Names}}: {{.Status}}' 2>/dev/null | while IFS= read -r line; do
                        verbose_output "${line}"
                    done
                fi
            else
                # Also check without label filter
                local all_containers
                all_containers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i "coldtrack\|influx\|grafana" || true)
                if [ -n "$all_containers" ]; then
                    local ct
                    ct=$(echo "$all_containers" | wc -l | tr -d ' ')
                    record_result "Docker Containers" "PASS" "${ct} related container(s) running" "false"
                else
                    record_result "Docker Containers" "SKIP" "No ColdTrack containers running" "false"
                fi
            fi
        else
            record_result "Docker" "SKIP" "Docker daemon not running" "false"
        fi
    else
        record_result "Docker" "SKIP" "Docker not installed" "false"
    fi
}

# ---------------------------------------------------------------------------
# Check 9: Terraform State
# ---------------------------------------------------------------------------
check_terraform_state() {
    log_header "Terraform State"

    if [ ! -d "${TERRAFORM_DIR}" ]; then
        record_result "Terraform Directory" "WARN" "Terraform directory not found" "false"
        return
    fi

    if [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
        local resource_count
        resource_count=$(jq '.resources | length' "${TERRAFORM_DIR}/terraform.tfstate" 2>/dev/null || echo "0")
        record_result "Terraform State" "PASS" "${resource_count} resource(s) in state"
    elif [ -d "${TERRAFORM_DIR}/.terraform" ]; then
        record_result "Terraform State" "WARN" "Initialized but no state file (not yet applied)" "false"
    else
        record_result "Terraform State" "WARN" "Not initialized (run deploy-infrastructure.sh first)" "false"
    fi
}

# ---------------------------------------------------------------------------
# Display Summary
# ---------------------------------------------------------------------------
display_summary() {
    if [ "$JSON_OUTPUT" = true ]; then
        # Build JSON output
        local json_results="["
        local first=true
        for result in "${RESULTS[@]}"; do
            if [ "$first" = true ]; then
                first=false
            else
                json_results+=","
            fi
            json_results+="${result}"
        done
        json_results+="]"

        jq -n \
            --argjson results "${json_results}" \
            --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            --arg region "${REGION}" \
            --argjson pass "${PASS_COUNT}" \
            --argjson fail "${FAIL_COUNT}" \
            --argjson warn "${WARN_COUNT}" \
            --argjson skip "${SKIP_COUNT}" \
            --argjson healthy "$([ "$CRITICAL_FAIL" = false ] && echo true || echo false)" \
            '{
                timestamp: $timestamp,
                region: $region,
                healthy: $healthy,
                summary: { pass: $pass, fail: $fail, warn: $warn, skip: $skip },
                checks: $results
            }'
        return
    fi

    echo ""
    echo -e "${BLUE}${BOLD}============================================================${NC}"
    echo -e "${BLUE}${BOLD}  Health Check Summary${NC}"
    echo -e "${BLUE}${BOLD}============================================================${NC}"
    echo ""

    local total=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT + SKIP_COUNT))

    echo -e "  ${GREEN}[PASS]${NC} ${PASS_COUNT} check(s) passed"
    echo -e "  ${RED}[FAIL]${NC} ${FAIL_COUNT} check(s) failed"
    echo -e "  ${YELLOW}[WARN]${NC} ${WARN_COUNT} warning(s)"
    echo -e "  ${DIM}[SKIP]${NC} ${SKIP_COUNT} skipped"
    echo -e "  ${DIM}Total: ${total} check(s)${NC}"
    echo ""

    if [ "$CRITICAL_FAIL" = true ]; then
        echo -e "  ${RED}${BOLD}RESULT: UNHEALTHY -- One or more critical checks failed.${NC}"
        echo ""
        echo -e "  ${DIM}Run with --verbose for detailed output.${NC}"
    elif [ "$FAIL_COUNT" -gt 0 ]; then
        echo -e "  ${YELLOW}${BOLD}RESULT: DEGRADED -- Non-critical failures detected.${NC}"
    else
        echo -e "  ${GREEN}${BOLD}RESULT: HEALTHY -- All critical checks passed.${NC}"
    fi

    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${BLUE}${BOLD}============================================================${NC}"
        echo -e "${BLUE}${BOLD}  ColdTrack System Health Check${NC}"
        echo -e "${BLUE}${BOLD}============================================================${NC}"
        echo ""
        echo -e "  ${DIM}Region   : ${REGION}${NC}"
        echo -e "  ${DIM}Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")${NC}"
    fi

    check_aws_credentials
    check_iot_endpoint
    check_iot_things
    check_lambda_functions
    check_sns
    check_timestream
    check_api_gateway
    check_local_services
    check_terraform_state

    display_summary

    # Exit code
    if [ "$CRITICAL_FAIL" = true ]; then
        exit 1
    fi
    exit 0
}

main
