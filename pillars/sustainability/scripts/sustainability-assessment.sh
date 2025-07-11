#!/bin/bash

# AWS Well-Architected Sustainability - Assessment Script
# This script evaluates your AWS workload's environmental impact and efficiency

set -e

echo "=== AWS Sustainability Assessment ==="

# Check AWS CLI configuration
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured. Please run 'aws configure' first"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

echo "📋 Sustainability Assessment for Account: $ACCOUNT_ID in Region: $REGION"
echo "📅 Assessment Date: $(date)"

# Create output directory
mkdir -p ../outputs
OUTPUT_FILE="../outputs/sustainability-assessment-$(date +%Y%m%d-%H%M%S).txt"

# Function to log output to both console and file
log_output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_output "=== AWS Sustainability Assessment ==="
log_output "Account ID: $ACCOUNT_ID"
log_output "Region: $REGION"
log_output "Assessment Date: $(date)"
log_output ""

# 1. Region Selection Analysis
log_output "=== 1. REGION SELECTION ANALYSIS ==="

# Current region sustainability info
log_output "Current Region: $REGION"

# AWS regions with high renewable energy usage (as of 2024)
case $REGION in
    "us-west-1"|"us-west-2"|"eu-west-1"|"eu-central-1"|"eu-north-1"|"ca-central-1")
        log_output "✅ Region has high renewable energy usage"
        renewable_score=10
        ;;
    "us-east-1"|"us-east-2"|"eu-west-2"|"eu-west-3"|"ap-southeast-2")
        log_output "🟡 Region has moderate renewable energy usage"
        renewable_score=7
        ;;
    *)
        log_output "🟡 Region renewable energy information not available"
        renewable_score=5
        ;;
esac

# Check multi-region deployment
regions_used=$(aws ec2 describe-regions --query 'Regions[*].RegionName' --output text | wc -w)
log_output "Total AWS regions available: $regions_used"

# Check if resources are deployed in multiple regions
other_regions=$(aws ec2 describe-regions --query 'Regions[?RegionName!=`'$REGION'`].RegionName' --output text | head -3)
multi_region_resources=0

for region in $other_regions; do
    instances_in_region=$(aws ec2 describe-instances --region "$region" --query 'Reservations[*].Instances[?State.Name==`running`]' --output text 2>/dev/null | wc -l)
    if [ "$instances_in_region" -gt 0 ]; then
        multi_region_resources=$((multi_region_resources + instances_in_region))
        log_output "Resources found in $region: $instances_in_region instances"
    fi
done

if [ $multi_region_resources -gt 0 ]; then
    log_output "✅ Multi-region deployment detected"
else
    log_output "🟡 Single region deployment - consider proximity to users"
fi

# 2. Compute Resource Efficiency Analysis
log_output ""
log_output "=== 2. COMPUTE RESOURCE EFFICIENCY ANALYSIS ==="

# EC2 Instance Analysis
running_instances=$(aws ec2 describe-instances \
    --filters Name=instance-state-name,Values=running \
    --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,LaunchTime]' \
    --output text)

if [ -z "$running_instances" ]; then
    log_output "No running EC2 instances found"
else
    total_instances=$(echo "$running_instances" | wc -l)
    log_output "Total running EC2 instances: $total_instances"
    
    # Analyze instance types for efficiency
    graviton_instances=0
    burstable_instances=0
    oversized_instances=0
    
    echo "$running_instances" | while read instance_id instance_type launch_time; do
        if [ -n "$instance_id" ]; then
            # Check for Graviton processors (more energy efficient)
            if echo "$instance_type" | grep -q "6g\|7g"; then
                graviton_instances=$((graviton_instances + 1))
            fi
            
            # Check for burstable instances (T series)
            if echo "$instance_type" | grep -q "^t[2-4]"; then
                burstable_instances=$((burstable_instances + 1))
            fi
            
            # Check CPU utilization for right-sizing
            avg_cpu=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/EC2 \
                --metric-name CPUUtilization \
                --dimensions Name=InstanceId,Value="$instance_id" \
                --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 86400 \
                --statistics Average \
                --query 'Datapoints[*].Average' \
                --output text | awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
            
            if (( $(echo "$avg_cpu < 10" | bc -l 2>/dev/null || echo "0") )); then
                oversized_instances=$((oversized_instances + 1))
                log_output "  🔴 Underutilized: $instance_id ($instance_type) - ${avg_cpu}% CPU"
            fi
        fi
    done
    
    log_output ""
    log_output "Instance Efficiency Analysis:"
    log_output "  Graviton instances (energy efficient): $graviton_instances"
    log_output "  Burstable instances (T series): $burstable_instances"
    log_output "  Potentially oversized instances: $oversized_instances"
    
    # Calculate efficiency score
    efficiency_score=10
    if [ $oversized_instances -gt 0 ]; then
        efficiency_score=$((efficiency_score - (oversized_instances * 2)))
    fi
    
    if [ $graviton_instances -eq 0 ]; then
        efficiency_score=$((efficiency_score - 2))
        log_output "  💡 RECOMMENDATION: Consider Graviton processors for better energy efficiency"
    fi
fi

# Lambda Function Efficiency
lambda_functions=$(aws lambda list-functions \
    --query 'Functions[*].[FunctionName,Runtime,MemorySize,Timeout]' \
    --output text)

if [ -n "$lambda_functions" ]; then
    lambda_count=$(echo "$lambda_functions" | wc -l)
    log_output ""
    log_output "Lambda Functions: $lambda_count found"
    
    # Check for over-provisioned Lambda functions
    over_provisioned_lambda=0
    echo "$lambda_functions" | while read function_name runtime memory_size timeout; do
        if [ -n "$function_name" ]; then
            # Get average duration
            avg_duration=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/Lambda \
                --metric-name Duration \
                --dimensions Name=FunctionName,Value="$function_name" \
                --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 86400 \
                --statistics Average \
                --query 'Datapoints[*].Average' \
                --output text | awk '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count; else print "0"}')
            
            if [ -n "$avg_duration" ] && [ "$avg_duration" -gt 0 ]; then
                if [ "$avg_duration" -lt 1000 ] && [ "$memory_size" -gt 512 ]; then
                    over_provisioned_lambda=$((over_provisioned_lambda + 1))
                    log_output "  🟡 Over-provisioned: $function_name (${memory_size}MB, ${avg_duration}ms avg)"
                fi
            fi
        fi
    done
    
    log_output "  Over-provisioned Lambda functions: $over_provisioned_lambda"
fi

# 3. Storage Efficiency Analysis
log_output ""
log_output "=== 3. STORAGE EFFICIENCY ANALYSIS ==="

# S3 Storage Analysis
s3_buckets=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text)

if [ -n "$s3_buckets" ]; then
    bucket_count=$(echo "$s3_buckets" | wc -w)
    log_output "S3 Buckets: $bucket_count found"
    
    lifecycle_enabled=0
    intelligent_tiering=0
    
    for bucket in $s3_buckets; do
        # Check lifecycle configuration
        lifecycle=$(aws s3api get-bucket-lifecycle-configuration --bucket "$bucket" 2>/dev/null)
        if [ $? -eq 0 ]; then
            lifecycle_enabled=$((lifecycle_enabled + 1))
        fi
        
        # Check intelligent tiering
        intelligent_tier=$(aws s3api get-bucket-intelligent-tiering-configuration --bucket "$bucket" --id default 2>/dev/null)
        if [ $? -eq 0 ]; then
            intelligent_tiering=$((intelligent_tiering + 1))
        fi
    done
    
    log_output "  Buckets with lifecycle policies: $lifecycle_enabled"
    log_output "  Buckets with intelligent tiering: $intelligent_tiering"
    
    if [ $lifecycle_enabled -eq 0 ]; then
        log_output "  🔴 CRITICAL: No lifecycle policies configured - data may not be optimally stored"
    fi
    
    if [ $intelligent_tiering -eq 0 ]; then
        log_output "  💡 RECOMMENDATION: Consider S3 Intelligent Tiering for automatic optimization"
    fi
fi

# EBS Volume Analysis
ebs_volumes=$(aws ec2 describe-volumes \
    --query 'Volumes[*].[VolumeId,VolumeType,Size,State]' \
    --output text)

if [ -n "$ebs_volumes" ]; then
    total_volumes=$(echo "$ebs_volumes" | wc -l)
    gp3_volumes=$(echo "$ebs_volumes" | grep -c "gp3" || echo "0")
    unattached_volumes=$(echo "$ebs_volumes" | grep -c "available" || echo "0")
    
    log_output ""
    log_output "EBS Volumes: $total_volumes total"
    log_output "  GP3 volumes (efficient): $gp3_volumes"
    log_output "  Unattached volumes (waste): $unattached_volumes"
    
    if [ $unattached_volumes -gt 0 ]; then
        log_output "  🔴 CRITICAL: $unattached_volumes unattached volumes consuming resources"
    fi
    
    if [ $gp3_volumes -eq 0 ] && [ $total_volumes -gt 0 ]; then
        log_output "  💡 RECOMMENDATION: Consider GP3 volumes for better price-performance"
    fi
fi

# 4. Network Efficiency Analysis
log_output ""
log_output "=== 4. NETWORK EFFICIENCY ANALYSIS ==="

# CloudFront Distribution Analysis
cloudfront_distributions=$(aws cloudfront list-distributions \
    --query 'DistributionList.Items[?Status==`Deployed`].[Id,DomainName]' \
    --output text 2>/dev/null)

if [ -n "$cloudfront_distributions" ]; then
    distribution_count=$(echo "$cloudfront_distributions" | wc -l)
    log_output "✅ CloudFront Distributions: $distribution_count found"
    
    # Check cache hit rates
    echo "$cloudfront_distributions" | while read dist_id domain_name; do
        cache_hit_rate=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/CloudFront \
            --metric-name CacheHitRate \
            --dimensions Name=DistributionId,Value="$dist_id" \
            --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
            --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
            --period 86400 \
            --statistics Average \
            --query 'Datapoints[*].Average' \
            --output text 2>/dev/null | awk '{sum+=$1; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
        
        if (( $(echo "$cache_hit_rate < 80" | bc -l 2>/dev/null || echo "0") )); then
            log_output "  🟡 Low cache hit rate: $domain_name (${cache_hit_rate}%)"
        fi
    done
else
    log_output "🟡 No CloudFront distributions found"
    log_output "💡 RECOMMENDATION: Consider CloudFront for global content delivery efficiency"
fi

# VPC Endpoints for private connectivity
vpc_endpoints=$(aws ec2 describe-vpc-endpoints \
    --query 'VpcEndpoints[*].[VpcEndpointId,ServiceName,State]' \
    --output text)

if [ -n "$vpc_endpoints" ]; then
    endpoint_count=$(echo "$vpc_endpoints" | wc -l)
    log_output "✅ VPC Endpoints: $endpoint_count configured"
else
    log_output "🟡 No VPC Endpoints found"
    log_output "💡 RECOMMENDATION: Use VPC Endpoints to reduce data transfer"
fi

# 5. Data Lifecycle Management
log_output ""
log_output "=== 5. DATA LIFECYCLE MANAGEMENT ==="

# Database backup and retention analysis
rds_instances=$(aws rds describe-db-instances \
    --query 'DBInstances[*].[DBInstanceIdentifier,BackupRetentionPeriod,DeletionProtection]' \
    --output text)

if [ -n "$rds_instances" ]; then
    log_output "RDS Backup Configuration:"
    echo "$rds_instances" | while read db_instance backup_retention deletion_protection; do
        log_output "  $db_instance: ${backup_retention} days retention, Deletion protection: $deletion_protection"
        
        if [ "$backup_retention" -gt 35 ]; then
            log_output "    🟡 Long backup retention may increase storage costs"
        fi
    done
fi

# CloudWatch Logs retention
log_groups_retention=$(aws logs describe-log-groups \
    --query 'logGroups[*].[logGroupName,retentionInDays]' \
    --output text)

if [ -n "$log_groups_retention" ]; then
    no_retention_count=0
    long_retention_count=0
    
    echo "$log_groups_retention" | while read log_group retention; do
        if [ "$retention" = "None" ]; then
            no_retention_count=$((no_retention_count + 1))
        elif [ "$retention" -gt 365 ]; then
            long_retention_count=$((long_retention_count + 1))
        fi
    done
    
    log_output ""
    log_output "CloudWatch Logs Retention:"
    log_output "  Log groups without retention policy: $no_retention_count"
    log_output "  Log groups with >1 year retention: $long_retention_count"
    
    if [ $no_retention_count -gt 0 ]; then
        log_output "  🔴 CRITICAL: Log groups without retention consume storage indefinitely"
    fi
fi

# 6. Automation and Efficiency
log_output ""
log_output "=== 6. AUTOMATION AND EFFICIENCY ==="

# Auto Scaling Groups
asg_count=$(aws autoscaling describe-auto-scaling-groups \
    --query 'AutoScalingGroups[*].AutoScalingGroupName' \
    --output text | wc -w)

log_output "Auto Scaling Groups: $asg_count configured"

if [ $asg_count -eq 0 ]; then
    log_output "🟡 No auto-scaling configured - manual resource management required"
else
    log_output "✅ Auto-scaling helps optimize resource usage"
fi

# Spot Instance Usage
spot_requests=$(aws ec2 describe-spot-instance-requests \
    --query 'SpotInstanceRequests[?State==`active`]' \
    --output text | wc -l)

log_output "Active Spot Instance Requests: $spot_requests"

if [ $spot_requests -eq 0 ]; then
    log_output "💡 RECOMMENDATION: Consider Spot Instances for fault-tolerant workloads"
else
    log_output "✅ Using Spot Instances for cost and efficiency optimization"
fi

# Scheduled Actions
scheduled_actions=$(aws autoscaling describe-scheduled-actions \
    --query 'ScheduledUpdateGroupActions[*].ScheduledActionName' \
    --output text | wc -w)

log_output "Scheduled Scaling Actions: $scheduled_actions configured"

# 7. Sustainability Score Calculation
log_output ""
log_output "=== 7. SUSTAINABILITY SCORE CALCULATION ==="

# Calculate overall sustainability score
sustainability_score=0

# Region selection (0-10 points)
sustainability_score=$((sustainability_score + renewable_score))

# Resource efficiency (0-20 points)
if [ -n "$running_instances" ]; then
    if [ $oversized_instances -eq 0 ]; then
        sustainability_score=$((sustainability_score + 10))
    elif [ $oversized_instances -lt 3 ]; then
        sustainability_score=$((sustainability_score + 5))
    fi
    
    if [ $graviton_instances -gt 0 ]; then
        sustainability_score=$((sustainability_score + 5))
    fi
    
    if [ $burstable_instances -gt 0 ]; then
        sustainability_score=$((sustainability_score + 5))
    fi
fi

# Storage efficiency (0-15 points)
if [ -n "$s3_buckets" ]; then
    if [ $lifecycle_enabled -gt 0 ]; then
        sustainability_score=$((sustainability_score + 8))
    fi
    
    if [ $intelligent_tiering -gt 0 ]; then
        sustainability_score=$((sustainability_score + 4))
    fi
    
    if [ $unattached_volumes -eq 0 ]; then
        sustainability_score=$((sustainability_score + 3))
    fi
fi

# Network efficiency (0-10 points)
if [ -n "$cloudfront_distributions" ]; then
    sustainability_score=$((sustainability_score + 5))
fi

if [ -n "$vpc_endpoints" ]; then
    sustainability_score=$((sustainability_score + 5))
fi

# Automation (0-15 points)
if [ $asg_count -gt 0 ]; then
    sustainability_score=$((sustainability_score + 8))
fi

if [ $spot_requests -gt 0 ]; then
    sustainability_score=$((sustainability_score + 4))
fi

if [ $scheduled_actions -gt 0 ]; then
    sustainability_score=$((sustainability_score + 3))
fi

# Data lifecycle (0-10 points)
if [ $no_retention_count -eq 0 ]; then
    sustainability_score=$((sustainability_score + 10))
elif [ $no_retention_count -lt 5 ]; then
    sustainability_score=$((sustainability_score + 5))
fi

# Convert to percentage
sustainability_percentage=$((sustainability_score * 100 / 80))

log_output "SUSTAINABILITY SCORE: $sustainability_score/80 ($sustainability_percentage%)"
log_output ""

# Sustainability level assessment
if [ $sustainability_percentage -ge 80 ]; then
    sustainability_level="EXCELLENT"
elif [ $sustainability_percentage -ge 60 ]; then
    sustainability_level="GOOD"
elif [ $sustainability_percentage -ge 40 ]; then
    sustainability_level="FAIR"
else
    sustainability_level="NEEDS IMPROVEMENT"
fi

log_output "SUSTAINABILITY LEVEL: $sustainability_level"

# 8. Environmental Impact Estimation
log_output ""
log_output "=== 8. ENVIRONMENTAL IMPACT ESTIMATION ==="

# Rough carbon footprint estimation based on resource usage
if [ -n "$running_instances" ]; then
    # Estimate based on instance hours (very rough approximation)
    estimated_monthly_hours=$((total_instances * 24 * 30))
    estimated_co2_kg=$((estimated_monthly_hours * 2 / 1000))  # Rough estimate
    
    log_output "Estimated Monthly Resource Usage:"
    log_output "  EC2 instance hours: $estimated_monthly_hours"
    log_output "  Estimated CO2 impact: ~${estimated_co2_kg}kg CO2/month"
    log_output "  (This is a rough estimate - actual impact varies by region and usage)"
fi

# 9. Sustainability Recommendations
log_output ""
log_output "=== 9. SUSTAINABILITY RECOMMENDATIONS ==="

log_output "🌱 IMMEDIATE ACTIONS (High Impact):"
if [ $unattached_volumes -gt 0 ]; then
    log_output "□ Delete $unattached_volumes unattached EBS volumes"
fi
if [ $oversized_instances -gt 0 ]; then
    log_output "□ Right-size $oversized_instances underutilized EC2 instances"
fi
if [ $lifecycle_enabled -eq 0 ]; then
    log_output "□ Implement S3 lifecycle policies for all buckets"
fi
if [ $no_retention_count -gt 0 ]; then
    log_output "□ Set retention policies for CloudWatch Log Groups"
fi
log_output ""

log_output "🌿 OPTIMIZATION OPPORTUNITIES (Medium Impact):"
if [ $graviton_instances -eq 0 ]; then
    log_output "□ Migrate to Graviton processors for better energy efficiency"
fi
if [ -z "$cloudfront_distributions" ]; then
    log_output "□ Implement CloudFront for global content delivery"
fi
if [ $intelligent_tiering -eq 0 ]; then
    log_output "□ Enable S3 Intelligent Tiering for automatic optimization"
fi
if [ $asg_count -eq 0 ]; then
    log_output "□ Implement Auto Scaling for dynamic resource allocation"
fi
if [ $spot_requests -eq 0 ]; then
    log_output "□ Use Spot Instances for fault-tolerant workloads"
fi
log_output ""

log_output "🌍 STRATEGIC INITIATIVES (Long-term Impact):"
log_output "□ Evaluate region selection based on renewable energy usage"
log_output "□ Implement serverless architectures where appropriate"
log_output "□ Use managed services to benefit from AWS efficiency improvements"
log_output "□ Implement comprehensive monitoring for resource optimization"
log_output "□ Regular sustainability reviews and optimization cycles"
log_output ""

log_output "SUSTAINABILITY BEST PRACTICES:"
log_output "□ Monitor and optimize resource utilization continuously"
log_output "□ Use appropriate storage classes and lifecycle policies"
log_output "□ Implement efficient data transfer and caching strategies"
log_output "□ Choose energy-efficient instance types and sizes"
log_output "□ Automate resource scaling based on demand"
log_output "□ Regular cleanup of unused resources"

log_output ""
log_output "=== SUSTAINABILITY ASSESSMENT COMPLETE ==="
log_output "Full report saved to: $OUTPUT_FILE"

echo ""
echo "✅ Sustainability assessment completed!"
echo "📄 Full report saved to: $OUTPUT_FILE"
echo "🌱 Sustainability Score: $sustainability_percentage% ($sustainability_level)"
echo ""
if [ $sustainability_percentage -lt 60 ]; then
    echo "🌍 Focus on immediate actions to improve environmental efficiency"
fi
echo ""
echo "🚀 Next: Implement the highest impact sustainability improvements"
echo "   Start with resource right-sizing and lifecycle policies"
