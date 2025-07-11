#!/bin/bash

# AWS Well-Architected Review Toolkit - Common Utility Functions
# This file contains reusable functions for assessment scripts

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_header() {
    echo -e "\n${PURPLE}=== $1 ===${NC}" | tee -a "$LOG_FILE"
}

# AWS CLI helper functions
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    log_success "AWS CLI is installed"
}

check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first"
        exit 1
    fi
    log_success "AWS CLI is configured"
}

get_aws_account_id() {
    aws sts get-caller-identity --query Account --output text
}

get_aws_region() {
    aws configure get region
}

get_aws_user_arn() {
    aws sts get-caller-identity --query Arn --output text
}

# File and directory management
create_output_directory() {
    local dir_name="$1"
    if [ -z "$dir_name" ]; then
        dir_name="outputs"
    fi
    
    mkdir -p "$dir_name"
    log_info "Created output directory: $dir_name"
}

create_timestamped_file() {
    local base_name="$1"
    local extension="${2:-txt}"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    echo "${base_name}-${timestamp}.${extension}"
}

# JSON and data processing
validate_json() {
    local json_file="$1"
    if jq empty "$json_file" 2>/dev/null; then
        log_success "Valid JSON: $json_file"
        return 0
    else
        log_error "Invalid JSON: $json_file"
        return 1
    fi
}

extract_json_value() {
    local json_file="$1"
    local jq_filter="$2"
    jq -r "$jq_filter" "$json_file" 2>/dev/null || echo "null"
}

# AWS service availability checks
check_service_availability() {
    local service="$1"
    local operation="$2"
    
    case "$service" in
        "wellarchitected")
            aws wellarchitected list-workloads --max-results 1 &> /dev/null
            ;;
        "ec2")
            aws ec2 describe-instances --max-items 1 &> /dev/null
            ;;
        "s3")
            aws s3 ls &> /dev/null
            ;;
        "cloudwatch")
            aws cloudwatch list-metrics --max-records 1 &> /dev/null
            ;;
        "iam")
            aws iam list-users --max-items 1 &> /dev/null
            ;;
        "ce")
            aws ce get-cost-and-usage --time-period Start=2023-01-01,End=2023-01-02 --granularity DAILY --metrics BlendedCost &> /dev/null
            ;;
        *)
            log_warning "Unknown service: $service"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        log_success "$service service is accessible"
        return 0
    else
        log_warning "$service service has limited access or is unavailable"
        return 1
    fi
}

# Progress tracking
show_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    
    local percentage=$((current * 100 / total))
    local filled=$((percentage / 2))
    local empty=$((50 - filled))
    
    printf "\r${CYAN}Progress: [%s%s] %d%% - %s${NC}" \
        "$(printf "%*s" $filled | tr ' ' '=')" \
        "$(printf "%*s" $empty)" \
        "$percentage" \
        "$description"
    
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# Error handling and retry logic
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local command=("$@")
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if "${command[@]}"; then
            return 0
        fi
        
        log_warning "Command failed (attempt $attempt/$max_attempts). Retrying in ${delay}s..."
        sleep "$delay"
        attempt=$((attempt + 1))
        delay=$((delay * 2))  # Exponential backoff
    done
    
    log_error "Command failed after $max_attempts attempts"
    return 1
}

# Resource tagging helpers
get_resource_tags() {
    local resource_arn="$1"
    aws resourcegroupstaggingapi get-resources --resource-arn-list "$resource_arn" --query 'ResourceTagMappingList[0].Tags' --output json 2>/dev/null || echo "[]"
}

check_required_tags() {
    local resource_arn="$1"
    local required_tags=("$@")
    shift
    
    local tags_json=$(get_resource_tags "$resource_arn")
    local missing_tags=()
    
    for tag in "${required_tags[@]}"; do
        if ! echo "$tags_json" | jq -e ".[] | select(.Key == \"$tag\")" > /dev/null; then
            missing_tags+=("$tag")
        fi
    done
    
    if [ ${#missing_tags[@]} -eq 0 ]; then
        log_success "All required tags present for $resource_arn"
        return 0
    else
        log_warning "Missing tags for $resource_arn: ${missing_tags[*]}"
        return 1
    fi
}

# Cost analysis helpers
get_monthly_cost() {
    local start_date="$1"
    local end_date="$2"
    local service_filter="$3"
    
    local filter_json="{}"
    if [ -n "$service_filter" ]; then
        filter_json="{\"Dimensions\":{\"Key\":\"SERVICE\",\"Values\":[\"$service_filter\"]}}"
    fi
    
    aws ce get-cost-and-usage \
        --time-period Start="$start_date",End="$end_date" \
        --granularity MONTHLY \
        --metrics BlendedCost \
        --filter "$filter_json" \
        --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
        --output text 2>/dev/null || echo "0"
}

# Security helpers
check_encryption_at_rest() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "$resource_type" in
        "s3")
            aws s3api get-bucket-encryption --bucket "$resource_id" &> /dev/null
            ;;
        "ebs")
            aws ec2 describe-volumes --volume-ids "$resource_id" --query 'Volumes[0].Encrypted' --output text 2>/dev/null
            ;;
        "rds")
            aws rds describe-db-instances --db-instance-identifier "$resource_id" --query 'DBInstances[0].StorageEncrypted' --output text 2>/dev/null
            ;;
        *)
            log_warning "Unknown resource type for encryption check: $resource_type"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        log_success "Encryption enabled for $resource_type: $resource_id"
        return 0
    else
        log_warning "Encryption not enabled for $resource_type: $resource_id"
        return 1
    fi
}

# Performance monitoring helpers
get_cloudwatch_metric() {
    local namespace="$1"
    local metric_name="$2"
    local dimensions="$3"
    local start_time="$4"
    local end_time="$5"
    local statistic="${6:-Average}"
    
    aws cloudwatch get-metric-statistics \
        --namespace "$namespace" \
        --metric-name "$metric_name" \
        --dimensions "$dimensions" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 3600 \
        --statistics "$statistic" \
        --query 'Datapoints[0].'"$statistic" \
        --output text 2>/dev/null || echo "null"
}

# Report generation helpers
generate_html_report() {
    local title="$1"
    local content_file="$2"
    local output_file="$3"
    
    cat > "$output_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>$title</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #232F3E; }
        h2 { color: #FF9900; }
        .success { color: #28a745; }
        .warning { color: #ffc107; }
        .error { color: #dc3545; }
        .info { color: #17a2b8; }
        pre { background-color: #f8f9fa; padding: 10px; border-radius: 5px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>$title</h1>
    <p>Generated on: $(date)</p>
    <hr>
    <pre>
$(cat "$content_file")
    </pre>
</body>
</html>
EOF
    
    log_success "HTML report generated: $output_file"
}

# Cleanup functions
cleanup_temp_files() {
    local temp_dir="${1:-/tmp/wa-toolkit-$$}"
    if [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
        log_info "Cleaned up temporary directory: $temp_dir"
    fi
}

# Signal handlers
setup_signal_handlers() {
    trap 'log_warning "Script interrupted by user"; cleanup_temp_files; exit 130' INT TERM
}

# Validation functions
validate_aws_region() {
    local region="$1"
    aws ec2 describe-regions --region-names "$region" &> /dev/null
    if [ $? -eq 0 ]; then
        log_success "Valid AWS region: $region"
        return 0
    else
        log_error "Invalid AWS region: $region"
        return 1
    fi
}

validate_date_format() {
    local date_string="$1"
    if date -d "$date_string" &> /dev/null; then
        log_success "Valid date format: $date_string"
        return 0
    else
        log_error "Invalid date format: $date_string"
        return 1
    fi
}

# Initialize common variables
init_common_vars() {
    export ACCOUNT_ID=$(get_aws_account_id)
    export AWS_REGION=$(get_aws_region)
    export TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    export LOG_FILE="${LOG_FILE:-assessment-${TIMESTAMP}.log}"
    
    # Create necessary directories
    create_output_directory "outputs"
    create_output_directory "reports"
    create_output_directory "logs"
    
    # Set up signal handlers
    setup_signal_handlers
    
    log_info "Common variables initialized"
    log_info "Account ID: $ACCOUNT_ID"
    log_info "Region: $AWS_REGION"
    log_info "Timestamp: $TIMESTAMP"
}

# Main initialization function
init_assessment() {
    log_header "AWS Well-Architected Assessment Initialization"
    
    check_aws_cli
    check_aws_credentials
    init_common_vars
    
    log_success "Assessment environment initialized successfully"
}

# Export functions for use in other scripts
export -f log_info log_success log_warning log_error log_header
export -f check_aws_cli check_aws_credentials get_aws_account_id get_aws_region
export -f create_output_directory create_timestamped_file
export -f validate_json extract_json_value
export -f check_service_availability show_progress retry_command
export -f get_resource_tags check_required_tags
export -f get_monthly_cost check_encryption_at_rest get_cloudwatch_metric
export -f generate_html_report cleanup_temp_files
export -f validate_aws_region validate_date_format
export -f init_common_vars init_assessment
