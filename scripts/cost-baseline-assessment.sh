#!/bin/bash

# AWS Well-Architected Cost Optimization - Baseline Assessment Script
# This script analyzes your current AWS cost and usage patterns

set -e

echo "=== AWS Cost Optimization Baseline Assessment ==="

# Check AWS CLI configuration
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured. Please run 'aws configure' first"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

echo "📋 Assessment for Account: $ACCOUNT_ID in Region: $REGION"
echo "📅 Assessment Date: $(date)"

# Create output directory
mkdir -p ../outputs
OUTPUT_FILE="../outputs/cost-baseline-assessment-$(date +%Y%m%d-%H%M%S).txt"

# Function to log output to both console and file
log_output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_output "=== AWS Cost Optimization Baseline Assessment ==="
log_output "Account ID: $ACCOUNT_ID"
log_output "Region: $REGION"
log_output "Assessment Date: $(date)"
log_output ""

# 1. Current Month Cost Analysis
log_output "=== 1. CURRENT MONTH COST ANALYSIS ==="
current_month_start=$(date +%Y-%m-01)
current_month_end=$(date +%Y-%m-%d)

log_output "Analyzing costs from $current_month_start to $current_month_end"

# Get current month costs by service
log_output "Top 10 Services by Cost (Current Month):"
aws ce get-cost-and-usage \
    --time-period Start="$current_month_start",End="$current_month_end" \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --query 'ResultsByTime[0].Groups[?Metrics.BlendedCost.Amount>`0`] | sort_by(@, &Metrics.BlendedCost.Amount) | reverse(@) | [0:10].[Keys[0],Metrics.BlendedCost.Amount,Metrics.BlendedCost.Unit]' \
    --output table | tee -a "$OUTPUT_FILE"

# 2. Last 3 Months Trend Analysis
log_output ""
log_output "=== 2. COST TREND ANALYSIS (Last 3 Months) ==="
three_months_ago=$(date -d '3 months ago' +%Y-%m-01)

log_output "Monthly cost trend from $three_months_ago to $current_month_end:"
aws ce get-cost-and-usage \
    --time-period Start="$three_months_ago",End="$current_month_end" \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --query 'ResultsByTime[*].[TimePeriod.Start,Total.BlendedCost.Amount,Total.BlendedCost.Unit]' \
    --output table | tee -a "$OUTPUT_FILE"

# 3. EC2 Instance Analysis
log_output ""
log_output "=== 3. EC2 INSTANCE ANALYSIS ==="

# Count instances by type
log_output "EC2 Instances by Type:"
aws ec2 describe-instances \
    --query 'Reservations[*].Instances[?State.Name==`running`].InstanceType' \
    --output text | sort | uniq -c | sort -nr | tee -a "$OUTPUT_FILE"

# Get EC2 costs for current month
log_output ""
log_output "EC2 Costs by Instance Type (Current Month):"
aws ce get-cost-and-usage \
    --time-period Start="$current_month_start",End="$current_month_end" \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=INSTANCE_TYPE \
    --filter '{
        "Dimensions": {
            "Key": "SERVICE",
            "Values": ["Amazon Elastic Compute Cloud - Compute"]
        }
    }' \
    --query 'ResultsByTime[0].Groups[?Metrics.BlendedCost.Amount>`0`] | sort_by(@, &Metrics.BlendedCost.Amount) | reverse(@) | [0:10].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output table | tee -a "$OUTPUT_FILE"

# 4. Storage Analysis
log_output ""
log_output "=== 4. STORAGE ANALYSIS ==="

# S3 bucket count and estimated costs
s3_bucket_count=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text | wc -w)
log_output "Total S3 Buckets: $s3_bucket_count"

log_output ""
log_output "S3 Storage Costs (Current Month):"
aws ce get-cost-and-usage \
    --time-period Start="$current_month_start",End="$current_month_end" \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --filter '{
        "Dimensions": {
            "Key": "SERVICE",
            "Values": ["Amazon Simple Storage Service"]
        }
    }' \
    --query 'ResultsByTime[0].Total.[BlendedCost.Amount,BlendedCost.Unit]' \
    --output table | tee -a "$OUTPUT_FILE"

# EBS volume analysis
log_output ""
log_output "EBS Volumes by Type:"
aws ec2 describe-volumes \
    --query 'Volumes[*].VolumeType' \
    --output text | sort | uniq -c | sort -nr | tee -a "$OUTPUT_FILE"

# 5. Reserved Instance Analysis
log_output ""
log_output "=== 5. RESERVED INSTANCE ANALYSIS ==="

# Active Reserved Instances
log_output "Active Reserved Instances:"
aws ec2 describe-reserved-instances \
    --filters Name=state,Values=active \
    --query 'ReservedInstances[*].[InstanceType,InstanceCount,ProductDescription,End]' \
    --output table | tee -a "$OUTPUT_FILE"

# RI Utilization
log_output ""
log_output "Reserved Instance Utilization (Last Month):"
last_month_start=$(date -d 'last month' +%Y-%m-01)
last_month_end=$(date -d 'last month' +%Y-%m-%d)

aws ce get-reservation-utilization \
    --time-period Start="$last_month_start",End="$last_month_end" \
    --query 'UtilizationsByTime[0].Total.[UtilizationPercentage,PurchasedHours,UsedHours]' \
    --output table 2>/dev/null | tee -a "$OUTPUT_FILE" || log_output "No RI utilization data available"

# 6. Savings Plans Analysis
log_output ""
log_output "=== 6. SAVINGS PLANS ANALYSIS ==="

log_output "Active Savings Plans:"
aws savingsplans describe-savings-plans \
    --states Active \
    --query 'savingsPlans[*].[savingsPlanType,commitment,currency,start,end]' \
    --output table 2>/dev/null | tee -a "$OUTPUT_FILE" || log_output "No active Savings Plans found"

# 7. Unused Resources Detection
log_output ""
log_output "=== 7. UNUSED RESOURCES DETECTION ==="

# Unattached EBS volumes
log_output "Unattached EBS Volumes:"
unattached_volumes=$(aws ec2 describe-volumes \
    --filters Name=status,Values=available \
    --query 'Volumes[*].[VolumeId,Size,VolumeType,CreateTime]' \
    --output table)

if [ -n "$unattached_volumes" ]; then
    echo "$unattached_volumes" | tee -a "$OUTPUT_FILE"
else
    log_output "No unattached EBS volumes found"
fi

# Unused Elastic IPs
log_output ""
log_output "Unused Elastic IP Addresses:"
unused_eips=$(aws ec2 describe-addresses \
    --query 'Addresses[?!InstanceId].[PublicIp,AllocationId]' \
    --output table)

if [ -n "$unused_eips" ]; then
    echo "$unused_eips" | tee -a "$OUTPUT_FILE"
else
    log_output "No unused Elastic IP addresses found"
fi

# Stopped instances (still incurring EBS costs)
log_output ""
log_output "Stopped EC2 Instances (still incurring EBS costs):"
stopped_instances=$(aws ec2 describe-instances \
    --filters Name=instance-state-name,Values=stopped \
    --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,LaunchTime]' \
    --output table)

if [ -n "$stopped_instances" ]; then
    echo "$stopped_instances" | tee -a "$OUTPUT_FILE"
else
    log_output "No stopped instances found"
fi

# 8. Cost Allocation Tags Analysis
log_output ""
log_output "=== 8. COST ALLOCATION TAGS ANALYSIS ==="

log_output "Active Cost Allocation Tags:"
aws ce list-cost-allocation-tags \
    --status Active \
    --query 'CostAllocationTags[*].[TagKey,Type]' \
    --output table 2>/dev/null | tee -a "$OUTPUT_FILE" || log_output "Unable to retrieve cost allocation tags"

# 9. Trusted Advisor Cost Optimization Checks
log_output ""
log_output "=== 9. TRUSTED ADVISOR RECOMMENDATIONS ==="

log_output "Note: Trusted Advisor cost optimization checks require Business or Enterprise support plan"

# Try to get Trusted Advisor checks (will fail without proper support plan)
aws support describe-trusted-advisor-checks \
    --language en \
    --query 'checks[?category==`cost_optimizing`].[name,id]' \
    --output table 2>/dev/null | tee -a "$OUTPUT_FILE" || log_output "Trusted Advisor checks not available (requires Business/Enterprise support)"

# 10. Recommendations Summary
log_output ""
log_output "=== 10. IMMEDIATE RECOMMENDATIONS ==="

log_output "Based on this assessment, consider the following actions:"
log_output ""
log_output "HIGH PRIORITY:"
log_output "□ Review and delete unattached EBS volumes"
log_output "□ Release unused Elastic IP addresses"
log_output "□ Evaluate stopped instances - terminate if not needed"
log_output "□ Enable detailed billing and Cost Explorer"
log_output ""
log_output "MEDIUM PRIORITY:"
log_output "□ Analyze Reserved Instance opportunities for consistent workloads"
log_output "□ Implement cost allocation tags for better visibility"
log_output "□ Set up billing alerts and budgets"
log_output "□ Review S3 storage classes and lifecycle policies"
log_output ""
log_output "ONGOING:"
log_output "□ Regular right-sizing analysis for EC2 instances"
log_output "□ Monitor cost trends and anomalies"
log_output "□ Implement automated cost optimization policies"

# Calculate potential savings
log_output ""
log_output "=== POTENTIAL SAVINGS ESTIMATION ==="

# Count unused resources for savings estimation
unattached_vol_count=$(aws ec2 describe-volumes --filters Name=status,Values=available --query 'length(Volumes)' --output text)
unused_eip_count=$(aws ec2 describe-addresses --query 'length(Addresses[?!InstanceId])' --output text)
stopped_instance_count=$(aws ec2 describe-instances --filters Name=instance-state-name,Values=stopped --query 'length(Reservations[*].Instances[*])' --output text)

log_output "Potential Monthly Savings Opportunities:"
log_output "- Unattached EBS volumes: $unattached_vol_count volumes (~\$$(($unattached_vol_count * 10))/month estimated)"
log_output "- Unused Elastic IPs: $unused_eip_count IPs (~\$$(($unused_eip_count * 4))/month)"
log_output "- Stopped instances: $stopped_instance_count instances (EBS costs still apply)"

log_output ""
log_output "=== ASSESSMENT COMPLETE ==="
log_output "Full report saved to: $OUTPUT_FILE"
log_output ""
log_output "Next Steps:"
log_output "1. Review the detailed findings in the output file"
log_output "2. Prioritize recommendations based on potential savings"
log_output "3. Implement quick wins (delete unused resources)"
log_output "4. Plan longer-term optimizations (Reserved Instances, right-sizing)"
log_output "5. Set up ongoing monitoring and alerting"

echo ""
echo "✅ Cost baseline assessment completed!"
echo "📄 Full report saved to: $OUTPUT_FILE"
echo ""
echo "🚀 Next: Run the resource utilization analysis script"
echo "   ./resource-utilization-analysis.sh"
