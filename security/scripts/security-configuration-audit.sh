#!/bin/bash

# AWS Well-Architected Security - Configuration Audit Script
# This script performs a comprehensive security configuration audit

set -e

echo "=== AWS Security Configuration Audit ==="

# Check AWS CLI configuration
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured. Please run 'aws configure' first"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

echo "📋 Security Audit for Account: $ACCOUNT_ID in Region: $REGION"
echo "📅 Audit Date: $(date)"

# Create output directory
mkdir -p ../outputs
OUTPUT_FILE="../outputs/security-audit-$(date +%Y%m%d-%H%M%S).txt"

# Function to log output to both console and file
log_output() {
    echo "$1" | tee -a "$OUTPUT_FILE"
}

log_output "=== AWS Security Configuration Audit ==="
log_output "Account ID: $ACCOUNT_ID"
log_output "Region: $REGION"
log_output "Audit Date: $(date)"
log_output ""

# 1. IAM Security Assessment
log_output "=== 1. IAM SECURITY ASSESSMENT ==="

# Check root account access keys
log_output "Root Account Security:"
root_keys=$(aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent' --output text)
root_mfa=$(aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled' --output text)

if [ "$root_keys" = "1" ]; then
    log_output "🔴 CRITICAL: Root account has access keys - REMOVE IMMEDIATELY"
else
    log_output "✅ Root account has no access keys"
fi

if [ "$root_mfa" = "1" ]; then
    log_output "✅ Root account MFA is enabled"
else
    log_output "🔴 CRITICAL: Root account MFA is NOT enabled"
fi

# Check password policy
log_output ""
log_output "Password Policy:"
password_policy=$(aws iam get-account-password-policy --query 'PasswordPolicy' --output json 2>/dev/null)
if [ $? -eq 0 ]; then
    min_length=$(echo "$password_policy" | jq -r '.MinimumPasswordLength')
    require_symbols=$(echo "$password_policy" | jq -r '.RequireSymbols')
    require_numbers=$(echo "$password_policy" | jq -r '.RequireNumbers')
    require_uppercase=$(echo "$password_policy" | jq -r '.RequireUppercaseCharacters')
    require_lowercase=$(echo "$password_policy" | jq -r '.RequireLowercaseCharacters')
    
    log_output "✅ Password policy is configured"
    log_output "  Minimum length: $min_length"
    log_output "  Requires symbols: $require_symbols"
    log_output "  Requires numbers: $require_numbers"
    log_output "  Requires uppercase: $require_uppercase"
    log_output "  Requires lowercase: $require_lowercase"
    
    if [ "$min_length" -lt 8 ]; then
        log_output "🟡 WARNING: Consider increasing minimum password length to 8+"
    fi
else
    log_output "🔴 CRITICAL: No password policy configured"
fi

# Check users without MFA
log_output ""
log_output "Users without MFA:"
users_without_mfa=0
aws iam list-users --query 'Users[*].UserName' --output text | while read username; do
    if [ -n "$username" ]; then
        mfa_devices=$(aws iam list-mfa-devices --user-name "$username" --query 'MFADevices[*].SerialNumber' --output text)
        if [ -z "$mfa_devices" ]; then
            log_output "🔴 User without MFA: $username"
            users_without_mfa=$((users_without_mfa + 1))
        fi
    fi
done

# Check for overly permissive policies
log_output ""
log_output "Overly Permissive IAM Policies:"
aws iam list-policies --scope Local --query 'Policies[*].[PolicyName,Arn]' --output text | while read policy_name policy_arn; do
    if [ -n "$policy_name" ]; then
        policy_doc=$(aws iam get-policy-version \
            --policy-arn "$policy_arn" \
            --version-id $(aws iam get-policy --policy-arn "$policy_arn" --query 'Policy.DefaultVersionId' --output text) \
            --query 'PolicyVersion.Document' --output json 2>/dev/null)
        
        if echo "$policy_doc" | jq -r '.Statement[]' | grep -q '"Effect": "Allow".*"Action": "\*".*"Resource": "\*"'; then
            log_output "🔴 CRITICAL: Policy with admin permissions: $policy_name"
        fi
    fi
done

# 2. Network Security Assessment
log_output ""
log_output "=== 2. NETWORK SECURITY ASSESSMENT ==="

# Check VPC Flow Logs
log_output "VPC Flow Logs Status:"
vpcs=$(aws ec2 describe-vpcs --query 'Vpcs[*].VpcId' --output text)
for vpc_id in $vpcs; do
    flow_logs=$(aws ec2 describe-flow-logs --filters Name=resource-id,Values="$vpc_id" --query 'FlowLogs[*].FlowLogId' --output text)
    if [ -z "$flow_logs" ]; then
        log_output "🔴 CRITICAL: VPC $vpc_id has no Flow Logs enabled"
    else
        log_output "✅ VPC $vpc_id has Flow Logs enabled"
    fi
done

# Check for overly permissive security groups
log_output ""
log_output "Security Groups with Broad Access:"
aws ec2 describe-security-groups \
    --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]].[GroupId,GroupName,Description]' \
    --output text | while read group_id group_name description; do
    if [ -n "$group_id" ]; then
        # Check for SSH/RDP access from anywhere
        ssh_rdp_open=$(aws ec2 describe-security-groups \
            --group-ids "$group_id" \
            --query 'SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`] && (FromPort==`22` || FromPort==`3389`)]' \
            --output text)
        
        if [ -n "$ssh_rdp_open" ]; then
            log_output "🔴 CRITICAL: Security group $group_id allows SSH/RDP from 0.0.0.0/0"
        else
            log_output "🟡 WARNING: Security group $group_id allows some access from 0.0.0.0/0"
        fi
    fi
done

# Check default security groups
log_output ""
log_output "Default Security Groups:"
aws ec2 describe-security-groups \
    --filters Name=group-name,Values=default \
    --query 'SecurityGroups[*].[GroupId,VpcId]' \
    --output text | while read group_id vpc_id; do
    if [ -n "$group_id" ]; then
        # Check if default SG has any rules
        inbound_rules=$(aws ec2 describe-security-groups --group-ids "$group_id" --query 'SecurityGroups[0].IpPermissions' --output text)
        outbound_rules=$(aws ec2 describe-security-groups --group-ids "$group_id" --query 'SecurityGroups[0].IpPermissionsEgress' --output text)
        
        if [ -n "$inbound_rules" ] || [ -n "$outbound_rules" ]; then
            log_output "🟡 WARNING: Default security group $group_id (VPC: $vpc_id) has active rules"
        else
            log_output "✅ Default security group $group_id has no active rules"
        fi
    fi
done

# 3. Data Protection Assessment
log_output ""
log_output "=== 3. DATA PROTECTION ASSESSMENT ==="

# Check S3 bucket encryption
log_output "S3 Bucket Encryption Status:"
aws s3api list-buckets --query 'Buckets[*].Name' --output text | while read bucket; do
    if [ -n "$bucket" ]; then
        encryption=$(aws s3api get-bucket-encryption --bucket "$bucket" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text 2>/dev/null)
        if [ -z "$encryption" ] || [ "$encryption" = "None" ]; then
            log_output "🔴 CRITICAL: Bucket $bucket is not encrypted"
        else
            log_output "✅ Bucket $bucket encrypted with $encryption"
        fi
        
        # Check public access
        public_access=$(aws s3api get-public-access-block --bucket "$bucket" --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' --output text 2>/dev/null)
        if [ -z "$public_access" ] || echo "$public_access" | grep -q "False"; then
            log_output "🔴 CRITICAL: Bucket $bucket may have public access"
        else
            log_output "✅ Bucket $bucket has public access blocked"
        fi
    fi
done

# Check EBS volume encryption
log_output ""
log_output "EBS Volume Encryption Status:"
unencrypted_volumes=$(aws ec2 describe-volumes --query 'Volumes[?Encrypted==`false`].[VolumeId,Size,State]' --output text)
if [ -n "$unencrypted_volumes" ]; then
    log_output "🔴 CRITICAL: Unencrypted EBS volumes found:"
    echo "$unencrypted_volumes" | while read volume_id size state; do
        log_output "  Volume: $volume_id ($size GB, $state)"
    done
else
    log_output "✅ All EBS volumes are encrypted"
fi

# Check RDS encryption
log_output ""
log_output "RDS Instance Encryption Status:"
unencrypted_rds=$(aws rds describe-db-instances --query 'DBInstances[?StorageEncrypted==`false`].[DBInstanceIdentifier,Engine]' --output text)
if [ -n "$unencrypted_rds" ]; then
    log_output "🔴 CRITICAL: Unencrypted RDS instances found:"
    echo "$unencrypted_rds" | while read db_instance engine; do
        log_output "  Instance: $db_instance ($engine)"
    done
else
    log_output "✅ All RDS instances are encrypted"
fi

# 4. Monitoring and Logging Assessment
log_output ""
log_output "=== 4. MONITORING AND LOGGING ASSESSMENT ==="

# Check CloudTrail
log_output "CloudTrail Configuration:"
trails=$(aws cloudtrail describe-trails --query 'trailList[*].[Name,IsLogging,IsMultiRegionTrail,IncludeGlobalServiceEvents,LogFileValidationEnabled]' --output text)
if [ -z "$trails" ]; then
    log_output "🔴 CRITICAL: No CloudTrail trails configured"
else
    echo "$trails" | while read trail_name is_logging multi_region global_events log_validation; do
        log_output "Trail: $trail_name"
        if [ "$is_logging" = "True" ]; then
            log_output "  ✅ Logging: Enabled"
        else
            log_output "  🔴 CRITICAL: Logging: Disabled"
        fi
        
        if [ "$multi_region" = "True" ]; then
            log_output "  ✅ Multi-region: Enabled"
        else
            log_output "  🟡 WARNING: Multi-region: Disabled"
        fi
        
        if [ "$log_validation" = "True" ]; then
            log_output "  ✅ Log file validation: Enabled"
        else
            log_output "  🟡 WARNING: Log file validation: Disabled"
        fi
    done
fi

# Check GuardDuty
log_output ""
log_output "GuardDuty Status:"
detectors=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null)
if [ -z "$detectors" ] || [ "$detectors" = "None" ]; then
    log_output "🔴 CRITICAL: GuardDuty is not enabled"
else
    detector_status=$(aws guardduty get-detector --detector-id "$detectors" --query 'Status' --output text)
    if [ "$detector_status" = "ENABLED" ]; then
        log_output "✅ GuardDuty is enabled and active"
    else
        log_output "🔴 CRITICAL: GuardDuty is not active"
    fi
fi

# Check Security Hub
log_output ""
log_output "Security Hub Status:"
security_hub=$(aws securityhub describe-hub --query 'HubArn' --output text 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$security_hub" ]; then
    log_output "✅ Security Hub is enabled"
else
    log_output "🟡 WARNING: Security Hub is not enabled"
fi

# Check Config
log_output ""
log_output "AWS Config Status:"
config_recorders=$(aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[*].[name,recordingGroup.allSupported]' --output text 2>/dev/null)
if [ -z "$config_recorders" ]; then
    log_output "🟡 WARNING: AWS Config is not enabled"
else
    echo "$config_recorders" | while read recorder_name all_supported; do
        log_output "✅ Config recorder: $recorder_name (All resources: $all_supported)"
    done
fi

# 5. Access Control Assessment
log_output ""
log_output "=== 5. ACCESS CONTROL ASSESSMENT ==="

# Check for unused access keys
log_output "Access Key Usage Analysis:"
aws iam list-users --query 'Users[*].UserName' --output text | while read username; do
    if [ -n "$username" ]; then
        aws iam list-access-keys --user-name "$username" --query 'AccessKeyMetadata[*].[AccessKeyId,Status,CreateDate]' --output text | while read access_key_id status create_date; do
            if [ -n "$access_key_id" ]; then
                # Check last used date
                last_used=$(aws iam get-access-key-last-used --access-key-id "$access_key_id" --query 'AccessKeyLastUsed.LastUsedDate' --output text 2>/dev/null)
                if [ "$last_used" = "None" ] || [ -z "$last_used" ]; then
                    log_output "🟡 WARNING: Access key $access_key_id for user $username has never been used"
                else
                    # Check if key is old (>90 days since last use)
                    last_used_epoch=$(date -d "$last_used" +%s 2>/dev/null || echo "0")
                    current_epoch=$(date +%s)
                    days_since_use=$(( (current_epoch - last_used_epoch) / 86400 ))
                    
                    if [ $days_since_use -gt 90 ]; then
                        log_output "🟡 WARNING: Access key $access_key_id for user $username not used for $days_since_use days"
                    fi
                fi
            fi
        done
    fi
done

# Check for inline policies
log_output ""
log_output "Inline Policies (should be avoided):"
aws iam list-users --query 'Users[*].UserName' --output text | while read username; do
    if [ -n "$username" ]; then
        inline_policies=$(aws iam list-user-policies --user-name "$username" --query 'PolicyNames[*]' --output text)
        if [ -n "$inline_policies" ]; then
            log_output "🟡 WARNING: User $username has inline policies: $inline_policies"
        fi
    fi
done

# 6. Compliance and Governance
log_output ""
log_output "=== 6. COMPLIANCE AND GOVERNANCE ==="

# Check for resource tagging
log_output "Resource Tagging Compliance:"
untagged_ec2=0
total_ec2=0

aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,Tags]' --output text | while read instance_id tags; do
    if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
        total_ec2=$((total_ec2 + 1))
        if [ -z "$tags" ] || [ "$tags" = "None" ]; then
            untagged_ec2=$((untagged_ec2 + 1))
            log_output "🟡 WARNING: Untagged EC2 instance: $instance_id"
        fi
    fi
done

# Check cost allocation tags
log_output ""
log_output "Cost Allocation Tags:"
cost_tags=$(aws ce list-cost-allocation-tags --status Active --query 'CostAllocationTags[*].TagKey' --output text 2>/dev/null)
if [ -z "$cost_tags" ]; then
    log_output "🟡 WARNING: No cost allocation tags are activated"
else
    log_output "✅ Active cost allocation tags: $cost_tags"
fi

# 7. Security Score Summary
log_output ""
log_output "=== 7. SECURITY SCORE SUMMARY ==="

# Calculate basic security score based on key findings
score=100
critical_issues=0
warning_issues=0

# Deduct points for critical issues
if [ "$root_keys" = "1" ]; then
    score=$((score - 20))
    critical_issues=$((critical_issues + 1))
fi

if [ "$root_mfa" != "1" ]; then
    score=$((score - 15))
    critical_issues=$((critical_issues + 1))
fi

# Check if CloudTrail is properly configured
if [ -z "$trails" ]; then
    score=$((score - 15))
    critical_issues=$((critical_issues + 1))
fi

# Check if GuardDuty is enabled
if [ -z "$detectors" ] || [ "$detectors" = "None" ]; then
    score=$((score - 10))
    warning_issues=$((warning_issues + 1))
fi

log_output "SECURITY SCORE: $score/100"
log_output ""
log_output "CRITICAL ISSUES: $critical_issues"
log_output "WARNING ISSUES: $warning_issues"
log_output ""

# 8. Prioritized Recommendations
log_output "=== 8. PRIORITIZED SECURITY RECOMMENDATIONS ==="

log_output "🔴 CRITICAL (Fix Immediately):"
if [ "$root_keys" = "1" ]; then
    log_output "□ Remove root account access keys"
fi
if [ "$root_mfa" != "1" ]; then
    log_output "□ Enable MFA for root account"
fi
log_output "□ Enable CloudTrail in all regions with log file validation"
log_output "□ Encrypt all unencrypted EBS volumes and RDS instances"
log_output "□ Remove overly permissive security groups (0.0.0.0/0 for SSH/RDP)"
log_output "□ Enable S3 bucket encryption and block public access"
log_output ""

log_output "🟡 HIGH PRIORITY (Fix This Week):"
log_output "□ Enable GuardDuty for threat detection"
log_output "□ Enable Security Hub for centralized security findings"
log_output "□ Configure password policy if not present"
log_output "□ Enable MFA for all IAM users"
log_output "□ Enable VPC Flow Logs for all VPCs"
log_output "□ Review and remove unused access keys"
log_output ""

log_output "🟢 MEDIUM PRIORITY (Fix This Month):"
log_output "□ Enable AWS Config for compliance monitoring"
log_output "□ Implement resource tagging strategy"
log_output "□ Replace inline policies with managed policies"
log_output "□ Set up cost allocation tags"
log_output "□ Regular access reviews and cleanup"
log_output ""

log_output "ONGOING SECURITY PRACTICES:"
log_output "□ Regular security assessments (monthly)"
log_output "□ Security training for team members"
log_output "□ Incident response plan testing"
log_output "□ Security monitoring and alerting"
log_output "□ Keep up with AWS security best practices"

log_output ""
log_output "=== SECURITY AUDIT COMPLETE ==="
log_output "Full report saved to: $OUTPUT_FILE"

echo ""
echo "✅ Security configuration audit completed!"
echo "📄 Full report saved to: $OUTPUT_FILE"
echo "🔒 Security Score: $score/100"
echo ""
if [ $critical_issues -gt 0 ]; then
    echo "🚨 URGENT: $critical_issues critical security issues found - address immediately!"
fi
echo ""
echo "🚀 Next: Run the IAM policy analysis script"
echo "   ./iam-policy-analysis.sh"
