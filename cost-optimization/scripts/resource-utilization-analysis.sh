#!/bin/bash

# AWS Well-Architected Cost Optimization - Resource Utilization Analysis
# This script analyzes resource utilization to identify right-sizing opportunities

set -e

echo "=== AWS Resource Utilization Analysis ==="

# Check AWS CLI configuration
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured. Please run 'aws configure' first"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

echo "📋 Analysis for Account: $ACCOUNT_ID in Region: $REGION"
echo "📅 Analysis Date: $(date)"

# Create output directory
mkdir -p ../outputs
OUTPUT_FILE="../outputs/resource-utilization-analysis-$(date +%Y%m%d-%H%M%S).txt"

# Function to log output to both console and file
log_output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_output "=== AWS Resource Utilization Analysis ==="
log_output "Account ID: $ACCOUNT_ID"
log_output "Region: $REGION"
log_output "Analysis Date: $(date)"
log_output ""

# 1. EC2 Instance Utilization Analysis
log_output "=== 1. EC2 INSTANCE UTILIZATION ANALYSIS ==="

# Get all running instances
running_instances=$(aws ec2 describe-instances \
    --filters Name=instance-state-name,Values=running \
    --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,LaunchTime]' \
    --output text)

if [ -z "$running_instances" ]; then
    log_output "No running EC2 instances found"
else
    log_output "Analyzing utilization for running EC2 instances..."
    log_output ""
    
    # Analyze each instance
    echo "$running_instances" | while read instance_id instance_type launch_time; do
        if [ -n "$instance_id" ]; then
            log_output "Instance: $instance_id ($instance_type)"
            
            # Get CPU utilization for last 7 days
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
            
            # Get max CPU utilization
            max_cpu=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/EC2 \
                --metric-name CPUUtilization \
                --dimensions Name=InstanceId,Value="$instance_id" \
                --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 86400 \
                --statistics Maximum \
                --query 'Datapoints[*].Maximum' \
                --output text | awk '{if($1>max) max=$1} END {printf "%.2f", max+0}')
            
            log_output "  Average CPU (7 days): ${avg_cpu}%"
            log_output "  Maximum CPU (7 days): ${max_cpu}%"
            
            # Provide right-sizing recommendations
            if (( $(echo "$avg_cpu < 5" | bc -l 2>/dev/null || echo "0") )); then
                log_output "  🔴 RECOMMENDATION: Consider downsizing - very low utilization"
            elif (( $(echo "$avg_cpu < 20" | bc -l 2>/dev/null || echo "0") )); then
                log_output "  🟡 RECOMMENDATION: Consider downsizing - low utilization"
            elif (( $(echo "$avg_cpu > 80" | bc -l 2>/dev/null || echo "0") )); then
                log_output "  🔴 RECOMMENDATION: Consider upsizing - high utilization"
            else
                log_output "  ✅ RECOMMENDATION: Instance size appears appropriate"
            fi
            
            log_output ""
        fi
    done
fi

# 2. EBS Volume Utilization
log_output "=== 2. EBS VOLUME UTILIZATION ANALYSIS ==="

# Get all EBS volumes
volumes=$(aws ec2 describe-volumes \
    --query 'Volumes[*].[VolumeId,Size,VolumeType,State,Attachments[0].InstanceId]' \
    --output text)

if [ -z "$volumes" ]; then
    log_output "No EBS volumes found"
else
    log_output "EBS Volume Analysis:"
    log_output ""
    
    total_volumes=0
    unattached_volumes=0
    total_size=0
    
    echo "$volumes" | while read volume_id size volume_type state instance_id; do
        if [ -n "$volume_id" ]; then
            total_volumes=$((total_volumes + 1))
            total_size=$((total_size + size))
            
            if [ "$state" = "available" ]; then
                unattached_volumes=$((unattached_volumes + 1))
                log_output "🔴 UNATTACHED: $volume_id ($size GB, $volume_type)"
            elif [ -n "$instance_id" ]; then
                log_output "✅ ATTACHED: $volume_id ($size GB, $volume_type) -> $instance_id"
            fi
        fi
    done
    
    log_output ""
    log_output "EBS Summary:"
    log_output "- Total volumes: $total_volumes"
    log_output "- Unattached volumes: $unattached_volumes"
    log_output "- Total storage: $total_size GB"
fi

# 3. RDS Instance Utilization
log_output ""
log_output "=== 3. RDS INSTANCE UTILIZATION ANALYSIS ==="

# Get RDS instances
rds_instances=$(aws rds describe-db-instances \
    --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,DBInstanceStatus]' \
    --output text)

if [ -z "$rds_instances" ]; then
    log_output "No RDS instances found"
else
    log_output "Analyzing RDS instance utilization..."
    log_output ""
    
    echo "$rds_instances" | while read db_instance db_class engine status; do
        if [ -n "$db_instance" ] && [ "$status" = "available" ]; then
            log_output "RDS Instance: $db_instance ($db_class, $engine)"
            
            # Get CPU utilization
            avg_cpu=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/RDS \
                --metric-name CPUUtilization \
                --dimensions Name=DBInstanceIdentifier,Value="$db_instance" \
                --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 86400 \
                --statistics Average \
                --query 'Datapoints[*].Average' \
                --output text | awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
            
            # Get connection count
            avg_connections=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/RDS \
                --metric-name DatabaseConnections \
                --dimensions Name=DBInstanceIdentifier,Value="$db_instance" \
                --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 86400 \
                --statistics Average \
                --query 'Datapoints[*].Average' \
                --output text | awk '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count; else print "0"}')
            
            log_output "  Average CPU (7 days): ${avg_cpu}%"
            log_output "  Average Connections: ${avg_connections}"
            
            # Provide recommendations
            if (( $(echo "$avg_cpu < 20" | bc -l 2>/dev/null || echo "0") )); then
                log_output "  🟡 RECOMMENDATION: Consider downsizing - low CPU utilization"
            elif (( $(echo "$avg_cpu > 80" | bc -l 2>/dev/null || echo "0") )); then
                log_output "  🔴 RECOMMENDATION: Consider upsizing - high CPU utilization"
            else
                log_output "  ✅ RECOMMENDATION: Instance size appears appropriate"
            fi
            
            log_output ""
        fi
    done
fi

# 4. Load Balancer Utilization
log_output "=== 4. LOAD BALANCER UTILIZATION ANALYSIS ==="

# Get Application Load Balancers
albs=$(aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[*].[LoadBalancerName,LoadBalancerArn,State.Code]' \
    --output text)

if [ -z "$albs" ]; then
    log_output "No Application Load Balancers found"
else
    log_output "Analyzing Load Balancer utilization..."
    log_output ""
    
    echo "$albs" | while read lb_name lb_arn state; do
        if [ -n "$lb_name" ] && [ "$state" = "active" ]; then
            log_output "Load Balancer: $lb_name"
            
            # Extract the load balancer identifier for CloudWatch
            lb_id=$(echo "$lb_arn" | cut -d'/' -f2-)
            
            # Get request count
            total_requests=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/ApplicationELB \
                --metric-name RequestCount \
                --dimensions Name=LoadBalancer,Value="$lb_id" \
                --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 86400 \
                --statistics Sum \
                --query 'Datapoints[*].Sum' \
                --output text | awk '{sum+=$1} END {printf "%.0f", sum}')
            
            # Get average response time
            avg_response_time=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/ApplicationELB \
                --metric-name TargetResponseTime \
                --dimensions Name=LoadBalancer,Value="$lb_id" \
                --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 86400 \
                --statistics Average \
                --query 'Datapoints[*].Average' \
                --output text | awk '{sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count; else print "0"}')
            
            log_output "  Total Requests (7 days): ${total_requests}"
            log_output "  Average Response Time: ${avg_response_time}s"
            
            # Check if load balancer is being used
            if [ "$total_requests" = "0" ] || [ -z "$total_requests" ]; then
                log_output "  🔴 RECOMMENDATION: Load balancer appears unused - consider deletion"
            else
                log_output "  ✅ Load balancer is actively serving traffic"
            fi
            
            log_output ""
        fi
    done
fi

# 5. Lambda Function Utilization
log_output "=== 5. LAMBDA FUNCTION UTILIZATION ANALYSIS ==="

# Get Lambda functions
functions=$(aws lambda list-functions \
    --query 'Functions[*].[FunctionName,Runtime,MemorySize,Timeout]' \
    --output text)

if [ -z "$functions" ]; then
    log_output "No Lambda functions found"
else
    log_output "Analyzing Lambda function utilization..."
    log_output ""
    
    echo "$functions" | while read function_name runtime memory_size timeout; do
        if [ -n "$function_name" ]; then
            log_output "Lambda Function: $function_name"
            log_output "  Runtime: $runtime, Memory: ${memory_size}MB, Timeout: ${timeout}s"
            
            # Get invocation count
            invocations=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/Lambda \
                --metric-name Invocations \
                --dimensions Name=FunctionName,Value="$function_name" \
                --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 86400 \
                --statistics Sum \
                --query 'Datapoints[*].Sum' \
                --output text | awk '{sum+=$1} END {printf "%.0f", sum}')
            
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
            
            # Get error count
            errors=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/Lambda \
                --metric-name Errors \
                --dimensions Name=FunctionName,Value="$function_name" \
                --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 86400 \
                --statistics Sum \
                --query 'Datapoints[*].Sum' \
                --output text | awk '{sum+=$1} END {printf "%.0f", sum}')
            
            log_output "  Invocations (7 days): ${invocations}"
            log_output "  Average Duration: ${avg_duration}ms"
            log_output "  Errors: ${errors}"
            
            # Provide recommendations
            if [ "$invocations" = "0" ] || [ -z "$invocations" ]; then
                log_output "  🔴 RECOMMENDATION: Function appears unused - consider deletion"
            elif [ -n "$avg_duration" ] && [ "$avg_duration" -gt 0 ]; then
                if [ "$avg_duration" -lt 1000 ] && [ "$memory_size" -gt 512 ]; then
                    log_output "  🟡 RECOMMENDATION: Consider reducing memory allocation"
                elif [ "$avg_duration" -gt 5000 ]; then
                    log_output "  🟡 RECOMMENDATION: Consider increasing memory or optimizing code"
                else
                    log_output "  ✅ Function configuration appears appropriate"
                fi
            fi
            
            log_output ""
        fi
    done
fi

# 6. S3 Storage Analysis
log_output "=== 6. S3 STORAGE ANALYSIS ==="

# Get S3 buckets
buckets=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text)

if [ -z "$buckets" ]; then
    log_output "No S3 buckets found"
else
    log_output "Analyzing S3 storage utilization..."
    log_output ""
    
    total_buckets=0
    
    for bucket in $buckets; do
        total_buckets=$((total_buckets + 1))
        log_output "S3 Bucket: $bucket"
        
        # Get bucket size (this is an approximation using CloudWatch metrics)
        bucket_size=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/S3 \
            --metric-name BucketSizeBytes \
            --dimensions Name=BucketName,Value="$bucket" Name=StorageType,Value=StandardStorage \
            --start-time $(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%S) \
            --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
            --period 86400 \
            --statistics Average \
            --query 'Datapoints[*].Average' \
            --output text 2>/dev/null | awk '{printf "%.0f", $1/1024/1024/1024}')
        
        # Get number of objects
        object_count=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/S3 \
            --metric-name NumberOfObjects \
            --dimensions Name=BucketName,Value="$bucket" Name=StorageType,Value=AllStorageTypes \
            --start-time $(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%S) \
            --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
            --period 86400 \
            --statistics Average \
            --query 'Datapoints[*].Average' \
            --output text 2>/dev/null | awk '{printf "%.0f", $1}')
        
        if [ -n "$bucket_size" ] && [ "$bucket_size" != "0" ]; then
            log_output "  Size: ${bucket_size} GB"
            log_output "  Objects: ${object_count}"
            
            # Check lifecycle configuration
            lifecycle=$(aws s3api get-bucket-lifecycle-configuration --bucket "$bucket" 2>/dev/null)
            if [ $? -eq 0 ]; then
                log_output "  ✅ Lifecycle policy configured"
            else
                log_output "  🟡 RECOMMENDATION: Consider implementing lifecycle policies"
            fi
        else
            log_output "  Size: Unable to determine (may be empty or new bucket)"
        fi
        
        log_output ""
    done
    
    log_output "Total S3 buckets analyzed: $total_buckets"
fi

# 7. Summary and Recommendations
log_output ""
log_output "=== 7. UTILIZATION SUMMARY AND RECOMMENDATIONS ==="

log_output "IMMEDIATE ACTIONS (High Impact):"
log_output "□ Delete or stop unused EC2 instances with very low CPU utilization (<5%)"
log_output "□ Delete unattached EBS volumes"
log_output "□ Remove unused Lambda functions (0 invocations)"
log_output "□ Delete unused Load Balancers (0 requests)"
log_output ""

log_output "RIGHT-SIZING OPPORTUNITIES (Medium Impact):"
log_output "□ Downsize EC2 instances with consistently low CPU utilization (<20%)"
log_output "□ Downsize RDS instances with low CPU utilization"
log_output "□ Optimize Lambda memory allocation based on duration patterns"
log_output "□ Review and optimize EBS volume types and sizes"
log_output ""

log_output "OPTIMIZATION STRATEGIES (Ongoing):"
log_output "□ Implement auto-scaling for variable workloads"
log_output "□ Use Spot Instances for fault-tolerant workloads"
log_output "□ Implement S3 lifecycle policies for data archival"
log_output "□ Set up CloudWatch alarms for utilization monitoring"
log_output "□ Regular utilization reviews (monthly)"
log_output ""

log_output "MONITORING SETUP:"
log_output "□ Enable detailed monitoring for all EC2 instances"
log_output "□ Set up CloudWatch dashboards for key metrics"
log_output "□ Configure utilization alerts (>80% and <20%)"
log_output "□ Implement automated right-sizing recommendations"

log_output ""
log_output "=== ANALYSIS COMPLETE ==="
log_output "Full report saved to: $OUTPUT_FILE"

echo ""
echo "✅ Resource utilization analysis completed!"
echo "📄 Full report saved to: $OUTPUT_FILE"
echo ""
echo "🚀 Next: Run the cost optimization recommendations script"
echo "   ./cost-optimization-recommendations.sh"
