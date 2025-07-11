#!/bin/bash

# AWS Well-Architected Reliability - Comprehensive Assessment Script
# This script analyzes your AWS infrastructure for reliability best practices

set -e

echo "=== AWS Reliability Assessment ==="

# Check AWS CLI configuration
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured. Please run 'aws configure' first"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

echo "📋 Reliability Assessment for Account: $ACCOUNT_ID in Region: $REGION"
echo "📅 Assessment Date: $(date)"

# Create output directory
mkdir -p ../outputs
OUTPUT_FILE="../outputs/reliability-assessment-$(date +%Y%m%d-%H%M%S).txt"

# Function to log output to both console and file
log_output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_output "=== AWS Reliability Assessment ==="
log_output "Account ID: $ACCOUNT_ID"
log_output "Region: $REGION"
log_output "Assessment Date: $(date)"
log_output ""

# 1. Multi-AZ and High Availability Analysis
log_output "=== 1. MULTI-AZ AND HIGH AVAILABILITY ANALYSIS ==="

# Check VPC and subnet distribution
log_output "VPC and Subnet Distribution:"
vpcs=$(aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,State]' --output text)
echo "$vpcs" | while read vpc_id cidr_block state; do
    if [ -n "$vpc_id" ]; then
        log_output "VPC: $vpc_id ($cidr_block, $state)"
        
        # Get subnets for this VPC
        subnets=$(aws ec2 describe-subnets \
            --filters Name=vpc-id,Values="$vpc_id" \
            --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,MapPublicIpOnLaunch]' \
            --output text)
        
        az_count=0
        public_subnets=0
        private_subnets=0
        
        echo "$subnets" | while read subnet_id az cidr public; do
            if [ -n "$subnet_id" ]; then
                az_count=$((az_count + 1))
                if [ "$public" = "True" ]; then
                    public_subnets=$((public_subnets + 1))
                    log_output "  Public Subnet: $subnet_id in $az ($cidr)"
                else
                    private_subnets=$((private_subnets + 1))
                    log_output "  Private Subnet: $subnet_id in $az ($cidr)"
                fi
            fi
        done
        
        # Count unique AZs
        unique_azs=$(echo "$subnets" | awk '{print $2}' | sort -u | wc -l)
        log_output "  Availability Zones: $unique_azs"
        
        if [ "$unique_azs" -lt 2 ]; then
            log_output "  🔴 CRITICAL: VPC spans less than 2 AZs - single point of failure"
        else
            log_output "  ✅ VPC spans multiple AZs"
        fi
        
        log_output ""
    fi
done

# Check EC2 instance distribution
log_output "EC2 Instance Distribution Across AZs:"
running_instances=$(aws ec2 describe-instances \
    --filters Name=instance-state-name,Values=running \
    --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,Placement.AvailabilityZone]' \
    --output text)

if [ -z "$running_instances" ]; then
    log_output "No running EC2 instances found"
else
    # Count instances per AZ
    echo "$running_instances" | awk '{print $3}' | sort | uniq -c | while read count az; do
        log_output "  $az: $count instances"
    done
    
    # Check if instances are distributed across multiple AZs
    az_count=$(echo "$running_instances" | awk '{print $3}' | sort -u | wc -l)
    if [ "$az_count" -lt 2 ]; then
        log_output "  🔴 CRITICAL: All instances in single AZ - no high availability"
    else
        log_output "  ✅ Instances distributed across multiple AZs"
    fi
fi

# 2. Auto Scaling Analysis
log_output ""
log_output "=== 2. AUTO SCALING ANALYSIS ==="

# Check Auto Scaling Groups
asg_groups=$(aws autoscaling describe-auto-scaling-groups \
    --query 'AutoScalingGroups[*].[AutoScalingGroupName,MinSize,MaxSize,DesiredCapacity,HealthCheckType,HealthCheckGracePeriod]' \
    --output text)

if [ -z "$asg_groups" ]; then
    log_output "No Auto Scaling Groups found"
    log_output "🟡 WARNING: No auto-scaling configured - manual scaling required"
else
    log_output "Auto Scaling Groups Configuration:"
    echo "$asg_groups" | while read asg_name min_size max_size desired_capacity health_check_type grace_period; do
        if [ -n "$asg_name" ]; then
            log_output "ASG: $asg_name"
            log_output "  Capacity: Min=$min_size, Max=$max_size, Desired=$desired_capacity"
            log_output "  Health Check: $health_check_type (Grace Period: ${grace_period}s)"
            
            # Check AZ distribution for ASG
            asg_azs=$(aws autoscaling describe-auto-scaling-groups \
                --auto-scaling-group-names "$asg_name" \
                --query 'AutoScalingGroups[0].AvailabilityZones' \
                --output text)
            
            az_count=$(echo "$asg_azs" | wc -w)
            log_output "  Availability Zones: $az_count ($asg_azs)"
            
            if [ "$az_count" -lt 2 ]; then
                log_output "  🔴 CRITICAL: ASG spans less than 2 AZs"
            else
                log_output "  ✅ ASG spans multiple AZs"
            fi
            
            if [ "$min_size" -eq 0 ]; then
                log_output "  🟡 WARNING: Min size is 0 - service could scale to zero"
            fi
            
            log_output ""
        fi
    done
    
    # Check scaling policies
    log_output "Auto Scaling Policies:"
    scaling_policies=$(aws autoscaling describe-policies \
        --query 'ScalingPolicies[*].[PolicyName,PolicyType,AdjustmentType,ScalingAdjustment,Cooldown]' \
        --output text)
    
    if [ -z "$scaling_policies" ]; then
        log_output "🟡 WARNING: No scaling policies configured"
    else
        echo "$scaling_policies" | while read policy_name policy_type adjustment_type scaling_adjustment cooldown; do
            log_output "  Policy: $policy_name ($policy_type)"
            log_output "    Adjustment: $adjustment_type $scaling_adjustment"
            log_output "    Cooldown: ${cooldown}s"
        done
    fi
fi

# 3. Load Balancer Analysis
log_output ""
log_output "=== 3. LOAD BALANCER ANALYSIS ==="

# Application Load Balancers
albs=$(aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[*].[LoadBalancerName,LoadBalancerArn,State.Code,Type,Scheme]' \
    --output text)

if [ -z "$albs" ]; then
    log_output "No Load Balancers found"
    log_output "🟡 WARNING: No load balancing configured - single point of failure"
else
    log_output "Load Balancer Configuration:"
    echo "$albs" | while read lb_name lb_arn state lb_type scheme; do
        if [ -n "$lb_name" ]; then
            log_output "Load Balancer: $lb_name ($lb_type, $scheme)"
            log_output "  State: $state"
            
            # Check AZ distribution
            lb_azs=$(aws elbv2 describe-load-balancers \
                --load-balancer-arns "$lb_arn" \
                --query 'LoadBalancers[0].AvailabilityZones[*].ZoneName' \
                --output text)
            
            az_count=$(echo "$lb_azs" | wc -w)
            log_output "  Availability Zones: $az_count ($lb_azs)"
            
            if [ "$az_count" -lt 2 ]; then
                log_output "  🔴 CRITICAL: Load balancer in less than 2 AZs"
            else
                log_output "  ✅ Load balancer spans multiple AZs"
            fi
            
            # Check target groups
            target_groups=$(aws elbv2 describe-target-groups \
                --load-balancer-arn "$lb_arn" \
                --query 'TargetGroups[*].[TargetGroupName,HealthCheckPath,HealthCheckIntervalSeconds,HealthyThresholdCount,UnhealthyThresholdCount]' \
                --output text)
            
            if [ -n "$target_groups" ]; then
                echo "$target_groups" | while read tg_name health_path interval healthy_threshold unhealthy_threshold; do
                    log_output "  Target Group: $tg_name"
                    log_output "    Health Check: $health_path (${interval}s interval)"
                    log_output "    Thresholds: Healthy=$healthy_threshold, Unhealthy=$unhealthy_threshold"
                done
            fi
            
            log_output ""
        fi
    done
fi

# 4. Database Reliability Analysis
log_output "=== 4. DATABASE RELIABILITY ANALYSIS ==="

# RDS Instances
rds_instances=$(aws rds describe-db-instances \
    --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,MultiAZ,BackupRetentionPeriod,StorageEncrypted]' \
    --output text)

if [ -z "$rds_instances" ]; then
    log_output "No RDS instances found"
else
    log_output "RDS Instance Reliability Configuration:"
    echo "$rds_instances" | while read db_instance db_class engine multi_az backup_retention encrypted; do
        if [ -n "$db_instance" ]; then
            log_output "RDS Instance: $db_instance ($db_class, $engine)"
            
            if [ "$multi_az" = "True" ]; then
                log_output "  ✅ Multi-AZ: Enabled"
            else
                log_output "  🔴 CRITICAL: Multi-AZ: Disabled - single point of failure"
            fi
            
            if [ "$backup_retention" -gt 0 ]; then
                log_output "  ✅ Backup Retention: $backup_retention days"
            else
                log_output "  🔴 CRITICAL: Backup Retention: Disabled"
            fi
            
            if [ "$encrypted" = "True" ]; then
                log_output "  ✅ Storage Encryption: Enabled"
            else
                log_output "  🟡 WARNING: Storage Encryption: Disabled"
            fi
            
            # Check for read replicas
            read_replicas=$(aws rds describe-db-instances \
                --query "DBInstances[?ReadReplicaSourceDBInstanceIdentifier=='$db_instance'].DBInstanceIdentifier" \
                --output text)
            
            if [ -n "$read_replicas" ]; then
                replica_count=$(echo "$read_replicas" | wc -w)
                log_output "  ✅ Read Replicas: $replica_count ($read_replicas)"
            else
                log_output "  🟡 INFO: No read replicas configured"
            fi
            
            log_output ""
        fi
    done
fi

# DynamoDB Tables
dynamodb_tables=$(aws dynamodb list-tables --query 'TableNames[*]' --output text)

if [ -n "$dynamodb_tables" ]; then
    log_output "DynamoDB Table Reliability Configuration:"
    for table_name in $dynamodb_tables; do
        log_output "DynamoDB Table: $table_name"
        
        # Check point-in-time recovery
        pitr_status=$(aws dynamodb describe-continuous-backups \
            --table-name "$table_name" \
            --query 'ContinuousBackupsDescription.ContinuousBackupsStatus' \
            --output text 2>/dev/null)
        
        if [ "$pitr_status" = "ENABLED" ]; then
            log_output "  ✅ Point-in-Time Recovery: Enabled"
        else
            log_output "  🟡 WARNING: Point-in-Time Recovery: Disabled"
        fi
        
        # Check global tables
        global_table=$(aws dynamodb describe-table \
            --table-name "$table_name" \
            --query 'Table.GlobalTableVersion' \
            --output text 2>/dev/null)
        
        if [ -n "$global_table" ] && [ "$global_table" != "None" ]; then
            log_output "  ✅ Global Table: Version $global_table"
        else
            log_output "  🟡 INFO: Not configured as Global Table"
        fi
        
        log_output ""
    done
fi

# 5. Backup and Recovery Analysis
log_output "=== 5. BACKUP AND RECOVERY ANALYSIS ==="

# AWS Backup
backup_plans=$(aws backup list-backup-plans \
    --query 'BackupPlansList[*].[BackupPlanId,BackupPlanName,CreationDate]' \
    --output text 2>/dev/null)

if [ -z "$backup_plans" ]; then
    log_output "🟡 WARNING: No AWS Backup plans configured"
else
    log_output "AWS Backup Plans:"
    echo "$backup_plans" | while read plan_id plan_name creation_date; do
        log_output "  Backup Plan: $plan_name (ID: $plan_id)"
        log_output "    Created: $creation_date"
    done
fi

# EBS Snapshots
recent_snapshots=$(aws ec2 describe-snapshots \
    --owner-ids self \
    --query 'Snapshots[?StartTime>=`2024-01-01`]' \
    --output text | wc -l)

log_output ""
log_output "EBS Snapshots: $recent_snapshots snapshots created this year"

if [ "$recent_snapshots" -eq 0 ]; then
    log_output "🟡 WARNING: No recent EBS snapshots found"
else
    log_output "✅ EBS snapshots are being created"
fi

# 6. Monitoring and Alerting Analysis
log_output ""
log_output "=== 6. MONITORING AND ALERTING ANALYSIS ==="

# CloudWatch Alarms
alarms=$(aws cloudwatch describe-alarms \
    --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName,ComparisonOperator,Threshold]' \
    --output text)

if [ -z "$alarms" ]; then
    log_output "🔴 CRITICAL: No CloudWatch alarms configured"
else
    alarm_count=$(echo "$alarms" | wc -l)
    ok_alarms=$(echo "$alarms" | grep -c "OK" || echo "0")
    alarm_alarms=$(echo "$alarms" | grep -c "ALARM" || echo "0")
    insufficient_data=$(echo "$alarms" | grep -c "INSUFFICIENT_DATA" || echo "0")
    
    log_output "CloudWatch Alarms: $alarm_count total"
    log_output "  OK: $ok_alarms"
    log_output "  ALARM: $alarm_alarms"
    log_output "  INSUFFICIENT_DATA: $insufficient_data"
    
    if [ "$alarm_alarms" -gt 0 ]; then
        log_output "  🔴 ACTIVE ALARMS DETECTED - investigate immediately"
    fi
    
    if [ "$insufficient_data" -gt 5 ]; then
        log_output "  🟡 WARNING: Many alarms with insufficient data - check metrics"
    fi
fi

# SNS Topics for notifications
sns_topics=$(aws sns list-topics --query 'Topics[*].TopicArn' --output text | wc -w)
log_output ""
log_output "SNS Topics for Notifications: $sns_topics"

if [ "$sns_topics" -eq 0 ]; then
    log_output "🟡 WARNING: No SNS topics configured for notifications"
fi

# 7. Network Reliability Analysis
log_output ""
log_output "=== 7. NETWORK RELIABILITY ANALYSIS ==="

# Internet Gateways
igws=$(aws ec2 describe-internet-gateways \
    --query 'InternetGateways[*].[InternetGatewayId,State,Attachments[*].VpcId]' \
    --output text)

log_output "Internet Gateways:"
if [ -z "$igws" ]; then
    log_output "  No Internet Gateways found"
else
    echo "$igws" | while read igw_id state vpc_id; do
        log_output "  IGW: $igw_id ($state) attached to VPC: $vpc_id"
    done
fi

# NAT Gateways
nat_gws=$(aws ec2 describe-nat-gateways \
    --query 'NatGateways[*].[NatGatewayId,State,SubnetId,VpcId]' \
    --output text)

log_output ""
log_output "NAT Gateways:"
if [ -z "$nat_gws" ]; then
    log_output "  No NAT Gateways found"
    log_output "  🟡 WARNING: Private subnets may not have internet access"
else
    nat_count=0
    echo "$nat_gws" | while read nat_id state subnet_id vpc_id; do
        nat_count=$((nat_count + 1))
        log_output "  NAT Gateway: $nat_id ($state) in subnet $subnet_id"
    done
    
    # Check if NAT Gateways are in multiple AZs
    nat_azs=$(aws ec2 describe-nat-gateways \
        --query 'NatGateways[*].SubnetId' \
        --output text | while read subnet_id; do
            aws ec2 describe-subnets --subnet-ids "$subnet_id" --query 'Subnets[0].AvailabilityZone' --output text
        done | sort -u | wc -l)
    
    if [ "$nat_azs" -lt 2 ]; then
        log_output "  🟡 WARNING: NAT Gateways not distributed across multiple AZs"
    else
        log_output "  ✅ NAT Gateways distributed across multiple AZs"
    fi
fi

# VPC Endpoints
vpc_endpoints=$(aws ec2 describe-vpc-endpoints \
    --query 'VpcEndpoints[*].[VpcEndpointId,ServiceName,State]' \
    --output text)

log_output ""
log_output "VPC Endpoints:"
if [ -z "$vpc_endpoints" ]; then
    log_output "  No VPC Endpoints found"
    log_output "  🟡 INFO: Consider VPC endpoints for private AWS service access"
else
    endpoint_count=$(echo "$vpc_endpoints" | wc -l)
    log_output "  $endpoint_count VPC endpoints configured"
    echo "$vpc_endpoints" | while read endpoint_id service_name state; do
        log_output "    $service_name: $endpoint_id ($state)"
    done
fi

# 8. Reliability Score and Recommendations
log_output ""
log_output "=== 8. RELIABILITY SCORE AND RECOMMENDATIONS ==="

# Calculate reliability score
score=100
critical_issues=0
warning_issues=0

# Check critical reliability factors
if [ -z "$running_instances" ]; then
    # No instances to evaluate
    :
else
    instance_az_count=$(echo "$running_instances" | awk '{print $3}' | sort -u | wc -l)
    if [ "$instance_az_count" -lt 2 ]; then
        score=$((score - 20))
        critical_issues=$((critical_issues + 1))
    fi
fi

if [ -z "$albs" ]; then
    score=$((score - 15))
    warning_issues=$((warning_issues + 1))
fi

if [ -z "$asg_groups" ]; then
    score=$((score - 15))
    warning_issues=$((warning_issues + 1))
fi

# Check RDS Multi-AZ
if [ -n "$rds_instances" ]; then
    single_az_rds=$(echo "$rds_instances" | grep -c "False" || echo "0")
    if [ "$single_az_rds" -gt 0 ]; then
        score=$((score - 20))
        critical_issues=$((critical_issues + 1))
    fi
fi

if [ -z "$alarms" ]; then
    score=$((score - 10))
    warning_issues=$((warning_issues + 1))
fi

log_output "RELIABILITY SCORE: $score/100"
log_output ""
log_output "CRITICAL ISSUES: $critical_issues"
log_output "WARNING ISSUES: $warning_issues"
log_output ""

# Prioritized recommendations
log_output "=== 9. PRIORITIZED RELIABILITY RECOMMENDATIONS ==="

log_output "🔴 CRITICAL (Fix Immediately):"
log_output "□ Deploy resources across multiple Availability Zones"
log_output "□ Enable Multi-AZ for all RDS instances"
log_output "□ Configure Auto Scaling Groups with min size > 0"
log_output "□ Set up load balancers for high availability"
log_output "□ Enable automated backups for all databases"
log_output ""

log_output "🟡 HIGH PRIORITY (Fix This Week):"
log_output "□ Configure CloudWatch alarms for critical metrics"
log_output "□ Set up SNS notifications for alerts"
log_output "□ Implement automated backup strategies"
log_output "□ Configure health checks for all services"
log_output "□ Set up monitoring dashboards"
log_output ""

log_output "🟢 MEDIUM PRIORITY (Fix This Month):"
log_output "□ Implement disaster recovery procedures"
log_output "□ Set up cross-region replication for critical data"
log_output "□ Configure VPC endpoints for private service access"
log_output "□ Implement infrastructure as code"
log_output "□ Regular reliability testing and chaos engineering"
log_output ""

log_output "ONGOING RELIABILITY PRACTICES:"
log_output "□ Regular disaster recovery testing"
log_output "□ Capacity planning and scaling reviews"
log_output "□ Performance and availability monitoring"
log_output "□ Incident response plan maintenance"
log_output "□ Architecture reviews for new deployments"

log_output ""
log_output "=== RELIABILITY ASSESSMENT COMPLETE ==="
log_output "Full report saved to: $OUTPUT_FILE"

echo ""
echo "✅ Reliability assessment completed!"
echo "📄 Full report saved to: $OUTPUT_FILE"
echo "🎯 Reliability Score: $score/100"
echo ""
if [ $critical_issues -gt 0 ]; then
    echo "🚨 URGENT: $critical_issues critical reliability issues found!"
fi
echo ""
echo "🚀 Next: Run the disaster recovery testing script"
echo "   ./disaster-recovery-test.sh"
