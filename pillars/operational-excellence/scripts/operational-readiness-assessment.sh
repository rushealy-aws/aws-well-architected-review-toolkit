#!/bin/bash

# AWS Well-Architected Operational Excellence - Readiness Assessment Script
# This script evaluates operational practices and automation maturity

set -e

echo "=== AWS Operational Excellence Readiness Assessment ==="

# Check AWS CLI configuration
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured. Please run 'aws configure' first"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

echo "📋 Operational Assessment for Account: $ACCOUNT_ID in Region: $REGION"
echo "📅 Assessment Date: $(date)"

# Create output directory
mkdir -p ../outputs
OUTPUT_FILE="../outputs/operational-readiness-$(date +%Y%m%d-%H%M%S).txt"

# Function to log output to both console and file
log_output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_output "=== AWS Operational Excellence Readiness Assessment ==="
log_output "Account ID: $ACCOUNT_ID"
log_output "Region: $REGION"
log_output "Assessment Date: $(date)"
log_output ""

# 1. Infrastructure as Code Analysis
log_output "=== 1. INFRASTRUCTURE AS CODE ANALYSIS ==="

# CloudFormation Stacks
cf_stacks=$(aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'StackSummaries[*].[StackName,StackStatus,CreationTime]' \
    --output text)

if [ -z "$cf_stacks" ]; then
    log_output "🔴 CRITICAL: No CloudFormation stacks found"
    log_output "Infrastructure appears to be manually managed"
else
    stack_count=$(echo "$cf_stacks" | wc -l)
    log_output "✅ CloudFormation Stacks: $stack_count found"
    
    echo "$cf_stacks" | while read stack_name status creation_time; do
        log_output "  Stack: $stack_name ($status) - Created: $creation_time"
    done
fi

# Check for drift detection
log_output ""
log_output "CloudFormation Drift Detection:"
if [ -n "$cf_stacks" ]; then
    echo "$cf_stacks" | head -5 | while read stack_name status creation_time; do
        # Check last drift detection
        drift_info=$(aws cloudformation describe-stack-drift-detection-status \
            --stack-drift-detection-id $(aws cloudformation detect-stack-drift \
                --stack-name "$stack_name" --query 'StackDriftDetectionId' --output text 2>/dev/null) \
            --query '[StackDriftStatus,DetectionStatus]' --output text 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            log_output "  $stack_name: Drift detection available"
        else
            log_output "  $stack_name: No recent drift detection"
        fi
    done
else
    log_output "  No stacks to check for drift"
fi

# CDK and Terraform detection
log_output ""
log_output "Other IaC Tools Detection:"

# Look for CDK artifacts
cdk_artifacts=$(find /Users/rushealy -name "cdk.json" -o -name "*.ts" -path "*/cdk/*" 2>/dev/null | wc -l)
if [ "$cdk_artifacts" -gt 0 ]; then
    log_output "  ✅ AWS CDK artifacts detected: $cdk_artifacts files"
else
    log_output "  🟡 No AWS CDK artifacts found"
fi

# Look for Terraform files
terraform_files=$(find /Users/rushealy -name "*.tf" -o -name "terraform.tfstate" 2>/dev/null | wc -l)
if [ "$terraform_files" -gt 0 ]; then
    log_output "  ✅ Terraform files detected: $terraform_files files"
else
    log_output "  🟡 No Terraform files found"
fi

# 2. CI/CD Pipeline Analysis
log_output ""
log_output "=== 2. CI/CD PIPELINE ANALYSIS ==="

# CodePipeline
pipelines=$(aws codepipeline list-pipelines \
    --query 'pipelines[*].[name,created,updated]' \
    --output text)

if [ -z "$pipelines" ]; then
    log_output "🔴 CRITICAL: No CodePipeline pipelines found"
else
    pipeline_count=$(echo "$pipelines" | wc -l)
    log_output "✅ CodePipeline Pipelines: $pipeline_count found"
    
    echo "$pipelines" | while read pipeline_name created updated; do
        log_output "  Pipeline: $pipeline_name"
        log_output "    Created: $created, Updated: $updated"
        
        # Get pipeline execution history
        executions=$(aws codepipeline list-pipeline-executions \
            --pipeline-name "$pipeline_name" \
            --max-items 5 \
            --query 'pipelineExecutionSummaries[*].[status,startTime]' \
            --output text 2>/dev/null)
        
        if [ -n "$executions" ]; then
            success_count=$(echo "$executions" | grep -c "Succeeded" || echo "0")
            failed_count=$(echo "$executions" | grep -c "Failed" || echo "0")
            log_output "    Recent executions: $success_count succeeded, $failed_count failed"
        fi
    done
fi

# CodeBuild Projects
build_projects=$(aws codebuild list-projects \
    --query 'projects[*]' \
    --output text | wc -w)

log_output ""
log_output "CodeBuild Projects: $build_projects found"

if [ "$build_projects" -eq 0 ]; then
    log_output "🟡 WARNING: No CodeBuild projects found"
fi

# CodeDeploy Applications
deploy_apps=$(aws codedeploy list-applications \
    --query 'applications[*]' \
    --output text | wc -w)

log_output "CodeDeploy Applications: $deploy_apps found"

if [ "$deploy_apps" -eq 0 ]; then
    log_output "🟡 WARNING: No CodeDeploy applications found"
fi

# 3. Monitoring and Observability Analysis
log_output ""
log_output "=== 3. MONITORING AND OBSERVABILITY ANALYSIS ==="

# CloudWatch Dashboards
dashboards=$(aws cloudwatch list-dashboards \
    --query 'DashboardEntries[*].[DashboardName,LastModified,Size]' \
    --output text)

if [ -z "$dashboards" ]; then
    log_output "🔴 CRITICAL: No CloudWatch dashboards found"
else
    dashboard_count=$(echo "$dashboards" | wc -l)
    log_output "✅ CloudWatch Dashboards: $dashboard_count found"
    
    echo "$dashboards" | while read dashboard_name last_modified size; do
        log_output "  Dashboard: $dashboard_name (Size: $size bytes, Modified: $last_modified)"
    done
fi

# CloudWatch Alarms
alarms=$(aws cloudwatch describe-alarms \
    --query 'MetricAlarms[*].[AlarmName,StateValue,ActionsEnabled]' \
    --output text)

if [ -z "$alarms" ]; then
    log_output "🔴 CRITICAL: No CloudWatch alarms configured"
else
    alarm_count=$(echo "$alarms" | wc -l)
    active_alarms=$(echo "$alarms" | grep -c "True" || echo "0")
    log_output "✅ CloudWatch Alarms: $alarm_count total, $active_alarms with actions enabled"
    
    # Count alarm states
    ok_count=$(echo "$alarms" | grep -c "OK" || echo "0")
    alarm_state_count=$(echo "$alarms" | grep -c "ALARM" || echo "0")
    insufficient_data=$(echo "$alarms" | grep -c "INSUFFICIENT_DATA" || echo "0")
    
    log_output "  States: OK=$ok_count, ALARM=$alarm_state_count, INSUFFICIENT_DATA=$insufficient_data"
    
    if [ "$alarm_state_count" -gt 0 ]; then
        log_output "  🔴 ACTIVE ALARMS: $alarm_state_count alarms in ALARM state"
    fi
fi

# CloudWatch Logs
log_groups=$(aws logs describe-log-groups \
    --query 'logGroups[*].[logGroupName,retentionInDays,storedBytes]' \
    --output text)

if [ -z "$log_groups" ]; then
    log_output "🟡 WARNING: No CloudWatch Log Groups found"
else
    log_group_count=$(echo "$log_groups" | wc -l)
    log_output "✅ CloudWatch Log Groups: $log_group_count found"
    
    # Check retention policies
    no_retention=$(echo "$log_groups" | grep -c "None" || echo "0")
    if [ "$no_retention" -gt 0 ]; then
        log_output "  🟡 WARNING: $no_retention log groups have no retention policy"
    fi
fi

# X-Ray Tracing
xray_traces=$(aws xray get-trace-summaries \
    --time-range-type TimeRangeByStartTime \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --query 'TraceSummaries[*].Id' \
    --output text 2>/dev/null | wc -w)

log_output ""
log_output "X-Ray Tracing:"
if [ "$xray_traces" -gt 0 ]; then
    log_output "  ✅ Active tracing detected: $xray_traces traces in last hour"
else
    log_output "  🟡 INFO: No X-Ray traces found in last hour"
fi

# 4. Automation Analysis
log_output ""
log_output "=== 4. AUTOMATION ANALYSIS ==="

# Systems Manager Automation Documents
ssm_docs=$(aws ssm list-documents \
    --filters Key=DocumentType,Values=Automation \
    --query 'DocumentIdentifiers[*].[Name,DocumentType,CreatedDate]' \
    --output text)

if [ -z "$ssm_docs" ]; then
    log_output "🟡 WARNING: No Systems Manager Automation documents found"
else
    ssm_doc_count=$(echo "$ssm_docs" | wc -l)
    log_output "✅ Systems Manager Automation Documents: $ssm_doc_count found"
fi

# Lambda Functions (for automation)
lambda_functions=$(aws lambda list-functions \
    --query 'Functions[*].[FunctionName,Runtime,LastModified]' \
    --output text)

if [ -z "$lambda_functions" ]; then
    log_output "🟡 WARNING: No Lambda functions found"
else
    lambda_count=$(echo "$lambda_functions" | wc -l)
    log_output "✅ Lambda Functions: $lambda_count found"
    
    # Check for automation-related functions
    automation_functions=$(echo "$lambda_functions" | grep -i -E "(automat|schedul|trigger|process)" | wc -l)
    log_output "  Automation-related functions: $automation_functions"
fi

# EventBridge Rules
eventbridge_rules=$(aws events list-rules \
    --query 'Rules[*].[Name,State,ScheduleExpression]' \
    --output text)

if [ -z "$eventbridge_rules" ]; then
    log_output "🟡 WARNING: No EventBridge rules found"
else
    rule_count=$(echo "$eventbridge_rules" | wc -l)
    enabled_rules=$(echo "$eventbridge_rules" | grep -c "ENABLED" || echo "0")
    log_output "✅ EventBridge Rules: $rule_count total, $enabled_rules enabled"
    
    # Check for scheduled rules
    scheduled_rules=$(echo "$eventbridge_rules" | grep -v "None" | grep -c "rate\|cron" || echo "0")
    log_output "  Scheduled rules: $scheduled_rules"
fi

# 5. Configuration Management Analysis
log_output ""
log_output "=== 5. CONFIGURATION MANAGEMENT ANALYSIS ==="

# AWS Config
config_recorders=$(aws configservice describe-configuration-recorders \
    --query 'ConfigurationRecorders[*].[name,recordingGroup.allSupported,recordingGroup.includeGlobalResourceTypes]' \
    --output text 2>/dev/null)

if [ -z "$config_recorders" ]; then
    log_output "🔴 CRITICAL: AWS Config not enabled"
else
    log_output "✅ AWS Config enabled"
    echo "$config_recorders" | while read recorder_name all_supported global_resources; do
        log_output "  Recorder: $recorder_name"
        log_output "    All resources: $all_supported"
        log_output "    Global resources: $global_resources"
    done
fi

# Config Rules
config_rules=$(aws configservice describe-config-rules \
    --query 'ConfigRules[*].[ConfigRuleName,ConfigRuleState,Source.Owner]' \
    --output text 2>/dev/null)

if [ -n "$config_rules" ]; then
    rule_count=$(echo "$config_rules" | wc -l)
    aws_managed=$(echo "$config_rules" | grep -c "AWS" || echo "0")
    log_output "  Config Rules: $rule_count total, $aws_managed AWS managed"
else
    log_output "  🟡 WARNING: No Config rules configured"
fi

# Systems Manager Parameter Store
parameters=$(aws ssm describe-parameters \
    --query 'Parameters[*].[Name,Type,LastModifiedDate]' \
    --output text 2>/dev/null)

if [ -z "$parameters" ]; then
    log_output ""
    log_output "🟡 WARNING: No Systems Manager parameters found"
else
    param_count=$(echo "$parameters" | wc -l)
    secure_params=$(echo "$parameters" | grep -c "SecureString" || echo "0")
    log_output ""
    log_output "✅ Systems Manager Parameters: $param_count total, $secure_params secure"
fi

# 6. Incident Response Readiness
log_output ""
log_output "=== 6. INCIDENT RESPONSE READINESS ==="

# SNS Topics for notifications
sns_topics=$(aws sns list-topics \
    --query 'Topics[*].TopicArn' \
    --output text)

if [ -z "$sns_topics" ]; then
    log_output "🔴 CRITICAL: No SNS topics for notifications"
else
    topic_count=$(echo "$sns_topics" | wc -w)
    log_output "✅ SNS Topics: $topic_count found"
    
    # Check for alert-related topics
    alert_topics=$(echo "$sns_topics" | grep -i -E "(alert|alarm|notify|incident)" | wc -l)
    log_output "  Alert-related topics: $alert_topics"
fi

# CloudTrail for audit logging
cloudtrail_trails=$(aws cloudtrail describe-trails \
    --query 'trailList[*].[Name,IsLogging,IsMultiRegionTrail,IncludeGlobalServiceEvents]' \
    --output text)

if [ -z "$cloudtrail_trails" ]; then
    log_output "🔴 CRITICAL: No CloudTrail trails configured"
else
    trail_count=$(echo "$cloudtrail_trails" | wc -l)
    active_trails=$(echo "$cloudtrail_trails" | grep -c "True" || echo "0")
    log_output "✅ CloudTrail Trails: $trail_count total, $active_trails logging"
fi

# 7. Change Management Analysis
log_output ""
log_output "=== 7. CHANGE MANAGEMENT ANALYSIS ==="

# Check for change management automation
change_calendar=$(aws ssm list-documents \
    --filters Key=DocumentType,Values=ChangeCalendar \
    --query 'DocumentIdentifiers[*].Name' \
    --output text 2>/dev/null)

if [ -n "$change_calendar" ]; then
    log_output "✅ Change Calendar configured"
else
    log_output "🟡 INFO: No Change Calendar found"
fi

# Maintenance Windows
maintenance_windows=$(aws ssm describe-maintenance-windows \
    --query 'WindowIdentities[*].[WindowId,Name,Enabled,Schedule]' \
    --output text 2>/dev/null)

if [ -z "$maintenance_windows" ]; then
    log_output "🟡 INFO: No maintenance windows configured"
else
    window_count=$(echo "$maintenance_windows" | wc -l)
    enabled_windows=$(echo "$maintenance_windows" | grep -c "True" || echo "0")
    log_output "✅ Maintenance Windows: $window_count total, $enabled_windows enabled"
fi

# 8. Operational Excellence Score
log_output ""
log_output "=== 8. OPERATIONAL EXCELLENCE SCORE ==="

# Calculate operational maturity score
score=100
critical_issues=0
warning_issues=0

# Infrastructure as Code
if [ -z "$cf_stacks" ] && [ "$terraform_files" -eq 0 ] && [ "$cdk_artifacts" -eq 0 ]; then
    score=$((score - 25))
    critical_issues=$((critical_issues + 1))
fi

# CI/CD
if [ -z "$pipelines" ]; then
    score=$((score - 20))
    critical_issues=$((critical_issues + 1))
fi

# Monitoring
if [ -z "$dashboards" ]; then
    score=$((score - 15))
    warning_issues=$((warning_issues + 1))
fi

if [ -z "$alarms" ]; then
    score=$((score - 15))
    critical_issues=$((critical_issues + 1))
fi

# Configuration Management
if [ -z "$config_recorders" ]; then
    score=$((score - 10))
    warning_issues=$((warning_issues + 1))
fi

# Incident Response
if [ -z "$sns_topics" ]; then
    score=$((score - 10))
    warning_issues=$((warning_issues + 1))
fi

if [ -z "$cloudtrail_trails" ]; then
    score=$((score - 5))
    warning_issues=$((warning_issues + 1))
fi

log_output "OPERATIONAL EXCELLENCE SCORE: $score/100"
log_output ""
log_output "CRITICAL ISSUES: $critical_issues"
log_output "WARNING ISSUES: $warning_issues"
log_output ""

# Maturity Level Assessment
if [ $score -ge 90 ]; then
    maturity_level="ADVANCED"
elif [ $score -ge 70 ]; then
    maturity_level="INTERMEDIATE"
elif [ $score -ge 50 ]; then
    maturity_level="BASIC"
else
    maturity_level="INITIAL"
fi

log_output "OPERATIONAL MATURITY LEVEL: $maturity_level"

# 9. Prioritized Recommendations
log_output ""
log_output "=== 9. PRIORITIZED OPERATIONAL RECOMMENDATIONS ==="

log_output "🔴 CRITICAL (Implement Immediately):"
log_output "□ Implement Infrastructure as Code (CloudFormation/CDK/Terraform)"
log_output "□ Set up CI/CD pipelines for automated deployments"
log_output "□ Configure CloudWatch alarms for critical metrics"
log_output "□ Enable CloudTrail for audit logging"
log_output "□ Set up SNS notifications for alerts"
log_output ""

log_output "🟡 HIGH PRIORITY (Implement This Month):"
log_output "□ Create operational dashboards in CloudWatch"
log_output "□ Enable AWS Config for configuration compliance"
log_output "□ Implement automated backup and recovery procedures"
log_output "□ Set up centralized logging with CloudWatch Logs"
log_output "□ Create runbooks and operational procedures"
log_output ""

log_output "🟢 MEDIUM PRIORITY (Implement This Quarter):"
log_output "□ Implement X-Ray tracing for application insights"
log_output "□ Set up maintenance windows for planned changes"
log_output "□ Create change management processes"
log_output "□ Implement chaos engineering practices"
log_output "□ Set up automated security scanning"
log_output ""

log_output "ONGOING OPERATIONAL PRACTICES:"
log_output "□ Regular operational reviews and retrospectives"
log_output "□ Continuous improvement of automation"
log_output "□ Team training on operational tools and practices"
log_output "□ Regular disaster recovery testing"
log_output "□ Performance and cost optimization reviews"

log_output ""
log_output "NEXT STEPS BY MATURITY LEVEL:"

case $maturity_level in
    "INITIAL")
        log_output "Focus on: Basic monitoring, IaC implementation, and CI/CD setup"
        ;;
    "BASIC")
        log_output "Focus on: Advanced monitoring, automation, and incident response"
        ;;
    "INTERMEDIATE")
        log_output "Focus on: Optimization, advanced automation, and proactive practices"
        ;;
    "ADVANCED")
        log_output "Focus on: Innovation, continuous improvement, and knowledge sharing"
        ;;
esac

log_output ""
log_output "=== OPERATIONAL READINESS ASSESSMENT COMPLETE ==="
log_output "Full report saved to: $OUTPUT_FILE"

echo ""
echo "✅ Operational readiness assessment completed!"
echo "📄 Full report saved to: $OUTPUT_FILE"
echo "🎯 Operational Excellence Score: $score/100"
echo "📊 Maturity Level: $maturity_level"
echo ""
if [ $critical_issues -gt 0 ]; then
    echo "🚨 URGENT: $critical_issues critical operational issues found!"
fi
echo ""
echo "🚀 Next: Implement the highest priority recommendations"
echo "   Focus on Infrastructure as Code and CI/CD if score < 70"
