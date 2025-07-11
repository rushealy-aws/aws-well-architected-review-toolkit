#!/bin/bash

# AWS Well-Architected Performance Efficiency - Baseline Assessment Script
# This script establishes performance baselines for your AWS workloads

set -e

echo "=== AWS Performance Baseline Assessment ==="

# Check AWS CLI configuration
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured. Please run 'aws configure' first"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

echo "📋 Performance Assessment for Account: $ACCOUNT_ID in Region: $REGION"
echo "📅 Assessment Date: $(date)"

# Create output directory
mkdir -p ../outputs
OUTPUT_FILE="../outputs/performance-baseline-$(date +%Y%m%d-%H%M%S).txt"

# Function to log output to both console and file
log_output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_output "=== AWS Performance Baseline Assessment ==="
log_output "Account ID: $ACCOUNT_ID"
log_output "Region: $REGION"
log_output "Assessment Date: $(date)"
log_output ""

# 1. EC2 Performance Analysis
log_output "=== 1. EC2 PERFORMANCE ANALYSIS ==="

# Get running instances
running_instances=$(aws ec2 describe-instances \
    --filters Name=instance-state-name,Values=running \
    --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,LaunchTime,Placement.AvailabilityZone]' \
    --output text)

if [ -z "$running_instances" ]; then
    log_output "No running EC2 instances found"
else
    log_output "Running EC2 Instances Performance Metrics (Last 24 hours):"
    log_output ""
    
    echo "$running_instances" | while read instance_id instance_type launch_time az; do
        if [ -n "$instance_id" ]; then
            log_output "Instance: $instance_id ($instance_type) in $az"
            
            # CPU Utilization
            cpu_stats=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/EC2 \
                --metric-name CPUUtilization \
                --dimensions Name=InstanceId,Value="$instance_id" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Average,Maximum,Minimum \
                --query 'Datapoints[*].[Average,Maximum,Minimum]' \
                --output text)
            
            if [ -n "$cpu_stats" ]; then
                avg_cpu=$(echo "$cpu_stats" | awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
                max_cpu=$(echo "$cpu_stats" | awk '{if($2>max) max=$2} END {printf "%.2f", max+0}')
                min_cpu=$(echo "$cpu_stats" | awk '{min=100; if($3<min) min=$3} END {printf "%.2f", min+0}')
                
                log_output "  CPU - Avg: ${avg_cpu}%, Max: ${max_cpu}%, Min: ${min_cpu}%"
            else
                log_output "  CPU - No data available"
            fi
            
            # Network Performance
            network_in=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/EC2 \
                --metric-name NetworkIn \
                --dimensions Name=InstanceId,Value="$instance_id" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Average \
                --query 'Datapoints[*].Average' \
                --output text | awk '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count/1024/1024; else print "0"}')
            
            network_out=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/EC2 \
                --metric-name NetworkOut \
                --dimensions Name=InstanceId,Value="$instance_id" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Average \
                --query 'Datapoints[*].Average' \
                --output text | awk '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count/1024/1024; else print "0"}')
            
            log_output "  Network - In: ${network_in} MB/hr, Out: ${network_out} MB/hr"
            
            # Performance recommendations
            if (( $(echo "$avg_cpu < 10" | bc -l 2>/dev/null || echo "0") )); then
                log_output "  💡 RECOMMENDATION: Consider downsizing - low CPU utilization"
            elif (( $(echo "$avg_cpu > 80" | bc -l 2>/dev/null || echo "0") )); then
                log_output "  ⚠️  RECOMMENDATION: Consider upsizing - high CPU utilization"
            else
                log_output "  ✅ CPU utilization appears optimal"
            fi
            
            log_output ""
        fi
    done
fi

# 2. RDS Performance Analysis
log_output "=== 2. RDS PERFORMANCE ANALYSIS ==="

rds_instances=$(aws rds describe-db-instances \
    --query 'DBInstances[?DBInstanceStatus==`available`].[DBInstanceIdentifier,DBInstanceClass,Engine,MultiAZ]' \
    --output text)

if [ -z "$rds_instances" ]; then
    log_output "No available RDS instances found"
else
    log_output "RDS Instance Performance Metrics (Last 24 hours):"
    log_output ""
    
    echo "$rds_instances" | while read db_instance db_class engine multi_az; do
        if [ -n "$db_instance" ]; then
            log_output "RDS Instance: $db_instance ($db_class, $engine, Multi-AZ: $multi_az)"
            
            # CPU Utilization
            db_cpu=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/RDS \
                --metric-name CPUUtilization \
                --dimensions Name=DBInstanceIdentifier,Value="$db_instance" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Average,Maximum \
                --query 'Datapoints[*].[Average,Maximum]' \
                --output text)
            
            if [ -n "$db_cpu" ]; then
                avg_db_cpu=$(echo "$db_cpu" | awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
                max_db_cpu=$(echo "$db_cpu" | awk '{if($2>max) max=$2} END {printf "%.2f", max+0}')
                log_output "  CPU - Avg: ${avg_db_cpu}%, Max: ${max_db_cpu}%"
            fi
            
            # Database Connections
            db_connections=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/RDS \
                --metric-name DatabaseConnections \
                --dimensions Name=DBInstanceIdentifier,Value="$db_instance" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Average,Maximum \
                --query 'Datapoints[*].[Average,Maximum]' \
                --output text | awk '{sum+=$1; if($2>max) max=$2; count++} END {if(count>0) printf "Avg: %.0f, Max: %.0f", sum/count, max; else print "No data"}')
            
            log_output "  Connections - $db_connections"
            
            # Read/Write Latency
            read_latency=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/RDS \
                --metric-name ReadLatency \
                --dimensions Name=DBInstanceIdentifier,Value="$db_instance" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Average \
                --query 'Datapoints[*].Average' \
                --output text | awk '{sum+=$1; count++} END {if(count>0) printf "%.4f", sum/count; else print "0"}')
            
            write_latency=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/RDS \
                --metric-name WriteLatency \
                --dimensions Name=DBInstanceIdentifier,Value="$db_instance" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Average \
                --query 'Datapoints[*].Average' \
                --output text | awk '{sum+=$1; count++} END {if(count>0) printf "%.4f", sum/count; else print "0"}')
            
            log_output "  Latency - Read: ${read_latency}s, Write: ${write_latency}s"
            
            # Performance recommendations
            if (( $(echo "$avg_db_cpu > 80" | bc -l 2>/dev/null || echo "0") )); then
                log_output "  ⚠️  RECOMMENDATION: High CPU utilization - consider upsizing"
            elif (( $(echo "$read_latency > 0.2" | bc -l 2>/dev/null || echo "0") )); then
                log_output "  ⚠️  RECOMMENDATION: High read latency - consider read replicas or optimization"
            else
                log_output "  ✅ Database performance appears optimal"
            fi
            
            log_output ""
        fi
    done
fi

# 3. Load Balancer Performance Analysis
log_output "=== 3. LOAD BALANCER PERFORMANCE ANALYSIS ==="

load_balancers=$(aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[?State.Code==`active`].[LoadBalancerName,LoadBalancerArn,Type]' \
    --output text)

if [ -z "$load_balancers" ]; then
    log_output "No active load balancers found"
else
    log_output "Load Balancer Performance Metrics (Last 24 hours):"
    log_output ""
    
    echo "$load_balancers" | while read lb_name lb_arn lb_type; do
        if [ -n "$lb_name" ]; then
            log_output "Load Balancer: $lb_name ($lb_type)"
            
            # Extract load balancer ID for CloudWatch metrics
            lb_id=$(echo "$lb_arn" | cut -d'/' -f2-)
            
            # Request Count
            request_count=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/ApplicationELB \
                --metric-name RequestCount \
                --dimensions Name=LoadBalancer,Value="$lb_id" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Sum \
                --query 'Datapoints[*].Sum' \
                --output text | awk '{sum+=$1} END {printf "%.0f", sum}')
            
            # Response Time
            response_time=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/ApplicationELB \
                --metric-name TargetResponseTime \
                --dimensions Name=LoadBalancer,Value="$lb_id" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Average,Maximum \
                --query 'Datapoints[*].[Average,Maximum]' \
                --output text)
            
            if [ -n "$response_time" ]; then
                avg_response=$(echo "$response_time" | awk '{sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count; else print "0"}')
                max_response=$(echo "$response_time" | awk '{if($2>max) max=$2} END {printf "%.3f", max+0}')
                log_output "  Requests (24h): $request_count"
                log_output "  Response Time - Avg: ${avg_response}s, Max: ${max_response}s"
            fi
            
            # Error Rate
            error_4xx=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/ApplicationELB \
                --metric-name HTTPCode_Target_4XX_Count \
                --dimensions Name=LoadBalancer,Value="$lb_id" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Sum \
                --query 'Datapoints[*].Sum' \
                --output text | awk '{sum+=$1} END {printf "%.0f", sum}')
            
            error_5xx=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/ApplicationELB \
                --metric-name HTTPCode_Target_5XX_Count \
                --dimensions Name=LoadBalancer,Value="$lb_id" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Sum \
                --query 'Datapoints[*].Sum' \
                --output text | awk '{sum+=$1} END {printf "%.0f", sum}')
            
            log_output "  Errors - 4XX: $error_4xx, 5XX: $error_5xx"
            
            # Performance recommendations
            if (( $(echo "$avg_response > 1.0" | bc -l 2>/dev/null || echo "0") )); then
                log_output "  ⚠️  RECOMMENDATION: High response time - investigate backend performance"
            elif [ "$error_5xx" -gt 0 ]; then
                log_output "  ⚠️  RECOMMENDATION: Server errors detected - check target health"
            else
                log_output "  ✅ Load balancer performance appears optimal"
            fi
            
            log_output ""
        fi
    done
fi

# 4. Lambda Function Performance Analysis
log_output "=== 4. LAMBDA FUNCTION PERFORMANCE ANALYSIS ==="

lambda_functions=$(aws lambda list-functions \
    --query 'Functions[*].[FunctionName,Runtime,MemorySize,Timeout]' \
    --output text)

if [ -z "$lambda_functions" ]; then
    log_output "No Lambda functions found"
else
    log_output "Lambda Function Performance Metrics (Last 24 hours):"
    log_output ""
    
    echo "$lambda_functions" | while read function_name runtime memory_size timeout; do
        if [ -n "$function_name" ]; then
            log_output "Lambda Function: $function_name"
            log_output "  Configuration: $runtime, ${memory_size}MB, ${timeout}s timeout"
            
            # Invocation Count
            invocations=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/Lambda \
                --metric-name Invocations \
                --dimensions Name=FunctionName,Value="$function_name" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Sum \
                --query 'Datapoints[*].Sum' \
                --output text | awk '{sum+=$1} END {printf "%.0f", sum}')
            
            # Duration
            duration_stats=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/Lambda \
                --metric-name Duration \
                --dimensions Name=FunctionName,Value="$function_name" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Average,Maximum \
                --query 'Datapoints[*].[Average,Maximum]' \
                --output text)
            
            if [ -n "$duration_stats" ]; then
                avg_duration=$(echo "$duration_stats" | awk '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count; else print "0"}')
                max_duration=$(echo "$duration_stats" | awk '{if($2>max) max=$2} END {printf "%.0f", max+0}')
                log_output "  Invocations (24h): $invocations"
                log_output "  Duration - Avg: ${avg_duration}ms, Max: ${max_duration}ms"
            fi
            
            # Error Rate
            errors=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/Lambda \
                --metric-name Errors \
                --dimensions Name=FunctionName,Value="$function_name" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Sum \
                --query 'Datapoints[*].Sum' \
                --output text | awk '{sum+=$1} END {printf "%.0f", sum}')
            
            # Throttles
            throttles=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/Lambda \
                --metric-name Throttles \
                --dimensions Name=FunctionName,Value="$function_name" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Sum \
                --query 'Datapoints[*].Sum' \
                --output text | awk '{sum+=$1} END {printf "%.0f", sum}')
            
            log_output "  Errors: $errors, Throttles: $throttles"
            
            # Performance recommendations
            if [ "$invocations" = "0" ]; then
                log_output "  💡 RECOMMENDATION: Function not invoked - consider cleanup if unused"
            elif [ -n "$avg_duration" ] && [ "$avg_duration" -gt 0 ]; then
                timeout_ms=$((timeout * 1000))
                if [ "$max_duration" -gt $((timeout_ms - 1000)) ]; then
                    log_output "  ⚠️  RECOMMENDATION: Duration close to timeout - consider increasing timeout"
                elif [ "$avg_duration" -lt 1000 ] && [ "$memory_size" -gt 512 ]; then
                    log_output "  💡 RECOMMENDATION: Fast execution with high memory - consider reducing memory"
                elif [ "$avg_duration" -gt 5000 ]; then
                    log_output "  💡 RECOMMENDATION: Slow execution - consider increasing memory or optimizing code"
                else
                    log_output "  ✅ Function performance appears optimal"
                fi
            fi
            
            if [ "$throttles" -gt 0 ]; then
                log_output "  ⚠️  RECOMMENDATION: Throttling detected - check concurrency limits"
            fi
            
            log_output ""
        fi
    done
fi

# 5. CloudFront Performance Analysis
log_output "=== 5. CLOUDFRONT PERFORMANCE ANALYSIS ==="

distributions=$(aws cloudfront list-distributions \
    --query 'DistributionList.Items[?Status==`Deployed`].[Id,DomainName,Enabled]' \
    --output text 2>/dev/null)

if [ -z "$distributions" ]; then
    log_output "No CloudFront distributions found"
else
    log_output "CloudFront Distribution Performance (Last 24 hours):"
    log_output ""
    
    echo "$distributions" | while read dist_id domain_name enabled; do
        if [ -n "$dist_id" ] && [ "$enabled" = "True" ]; then
            log_output "Distribution: $dist_id ($domain_name)"
            
            # Requests
            requests=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/CloudFront \
                --metric-name Requests \
                --dimensions Name=DistributionId,Value="$dist_id" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Sum \
                --query 'Datapoints[*].Sum' \
                --output text | awk '{sum+=$1} END {printf "%.0f", sum}')
            
            # Cache Hit Rate
            cache_hit_rate=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/CloudFront \
                --metric-name CacheHitRate \
                --dimensions Name=DistributionId,Value="$dist_id" \
                --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 3600 \
                --statistics Average \
                --query 'Datapoints[*].Average' \
                --output text | awk '{sum+=$1; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
            
            log_output "  Requests (24h): $requests"
            log_output "  Cache Hit Rate: ${cache_hit_rate}%"
            
            # Performance recommendations
            if (( $(echo "$cache_hit_rate < 80" | bc -l 2>/dev/null || echo "0") )); then
                log_output "  💡 RECOMMENDATION: Low cache hit rate - review caching policies"
            else
                log_output "  ✅ CloudFront performance appears optimal"
            fi
            
            log_output ""
        fi
    done
fi

# 6. Performance Summary and Baseline
log_output "=== 6. PERFORMANCE BASELINE SUMMARY ==="

log_output "PERFORMANCE BASELINE ESTABLISHED:"
log_output "□ EC2 instances analyzed for CPU and network utilization"
log_output "□ RDS instances analyzed for CPU, connections, and latency"
log_output "□ Load balancers analyzed for response time and error rates"
log_output "□ Lambda functions analyzed for duration and error rates"
log_output "□ CloudFront distributions analyzed for cache performance"
log_output ""

log_output "KEY PERFORMANCE INDICATORS (KPIs) TO MONITOR:"
log_output "□ EC2 CPU utilization (target: 40-80%)"
log_output "□ RDS response time (target: <100ms for simple queries)"
log_output "□ Load balancer response time (target: <500ms)"
log_output "□ Lambda function duration vs timeout ratio"
log_output "□ CloudFront cache hit rate (target: >80%)"
log_output ""

log_output "RECOMMENDED MONITORING SETUP:"
log_output "□ Set up CloudWatch dashboards for key metrics"
log_output "□ Configure alarms for performance thresholds"
log_output "□ Enable detailed monitoring for critical resources"
log_output "□ Implement custom metrics for business KPIs"
log_output "□ Set up automated performance reports"
log_output ""

log_output "NEXT STEPS:"
log_output "1. Review performance metrics and identify bottlenecks"
log_output "2. Set up monitoring and alerting for key metrics"
log_output "3. Implement performance testing procedures"
log_output "4. Plan capacity scaling based on usage patterns"
log_output "5. Schedule regular performance reviews"

log_output ""
log_output "=== PERFORMANCE BASELINE ASSESSMENT COMPLETE ==="
log_output "Full report saved to: $OUTPUT_FILE"

echo ""
echo "✅ Performance baseline assessment completed!"
echo "📄 Full report saved to: $OUTPUT_FILE"
echo ""
echo "🚀 Next: Run the load testing script to validate performance under load"
echo "   ./load-testing.sh"
