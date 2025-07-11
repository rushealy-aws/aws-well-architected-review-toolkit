# Troubleshooting Guide

This guide provides solutions to common issues and challenges you may encounter while using the AWS Well-Architected Review Toolkit.

## Table of Contents

1. [Setup and Configuration Issues](#setup-and-configuration-issues)
2. [AWS CLI and Permissions Issues](#aws-cli-and-permissions-issues)
3. [Script Execution Problems](#script-execution-problems)
4. [Assessment Tool Issues](#assessment-tool-issues)
5. [Data Collection Problems](#data-collection-problems)
6. [Performance Issues](#performance-issues)
7. [Common Error Messages](#common-error-messages)
8. [Best Practices for Troubleshooting](#best-practices-for-troubleshooting)
9. [Getting Additional Help](#getting-additional-help)

## Setup and Configuration Issues

### Issue: Setup Script Fails to Run

**Symptoms:**
- Permission denied errors
- Script not found errors
- Bash command not recognized

**Solutions:**

1. **Make script executable:**
   ```bash
   chmod +x shared/scripts/setup-environment.sh
   ```

2. **Run with explicit bash:**
   ```bash
   bash shared/scripts/setup-environment.sh
   ```

3. **Check file path:**
   ```bash
   ls -la shared/scripts/setup-environment.sh
   pwd  # Verify you're in the correct directory
   ```

4. **Windows/WSL specific:**
   ```bash
   # Convert line endings if needed
   dos2unix shared/scripts/setup-environment.sh
   ```

### Issue: Environment Variables Not Set

**Symptoms:**
- Scripts can't find AWS account information
- Missing configuration values

**Solutions:**

1. **Source the environment file:**
   ```bash
   source .env
   # or
   . .env
   ```

2. **Manually set variables:**
   ```bash
   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export AWS_DEFAULT_REGION=$(aws configure get region)
   ```

3. **Check AWS CLI configuration:**
   ```bash
   aws configure list
   aws sts get-caller-identity
   ```

## AWS CLI and Permissions Issues

### Issue: AWS CLI Not Configured

**Symptoms:**
- "Unable to locate credentials" error
- "The config profile could not be found" error

**Solutions:**

1. **Configure AWS CLI:**
   ```bash
   aws configure
   # Enter your Access Key ID, Secret Access Key, Region, and Output format
   ```

2. **Use environment variables:**
   ```bash
   export AWS_ACCESS_KEY_ID=your-access-key
   export AWS_SECRET_ACCESS_KEY=your-secret-key
   export AWS_DEFAULT_REGION=us-east-1
   ```

3. **Use AWS profiles:**
   ```bash
   aws configure --profile myprofile
   export AWS_PROFILE=myprofile
   ```

4. **Use IAM roles (EC2/Lambda):**
   ```bash
   # No configuration needed if running on EC2 with IAM role
   aws sts get-caller-identity
   ```

### Issue: Insufficient Permissions

**Symptoms:**
- "AccessDenied" errors
- "UnauthorizedOperation" errors
- Scripts fail with permission errors

**Solutions:**

1. **Check current permissions:**
   ```bash
   aws iam get-user
   aws iam list-attached-user-policies --user-name YOUR_USERNAME
   aws iam list-user-policies --user-name YOUR_USERNAME
   ```

2. **Required IAM policies for Well-Architected reviews:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "wellarchitected:*",
           "cloudwatch:ListMetrics",
           "cloudwatch:GetMetricStatistics",
           "ec2:Describe*",
           "iam:List*",
           "iam:Get*",
           "s3:ListAllMyBuckets",
           "s3:GetBucketLocation",
           "ce:GetCostAndUsage",
           "ce:GetUsageReport",
           "support:DescribeCases"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

3. **Use least privilege principle:**
   - Start with read-only permissions
   - Add specific permissions as needed
   - Use AWS managed policies where appropriate

### Issue: Multi-Account Access

**Symptoms:**
- Can't access resources in other accounts
- Cross-account role assumption fails

**Solutions:**

1. **Set up cross-account roles:**
   ```bash
   # Assume role in target account
   aws sts assume-role \
     --role-arn "arn:aws:iam::TARGET-ACCOUNT:role/WellArchitectedRole" \
     --role-session-name "ReviewSession"
   ```

2. **Use AWS CLI profiles for multiple accounts:**
   ```bash
   # ~/.aws/config
   [profile account1]
   role_arn = arn:aws:iam::111111111111:role/WellArchitectedRole
   source_profile = default
   
   [profile account2]
   role_arn = arn:aws:iam::222222222222:role/WellArchitectedRole
   source_profile = default
   ```

## Script Execution Problems

### Issue: Scripts Hang or Take Too Long

**Symptoms:**
- Scripts run indefinitely
- No output for extended periods
- Timeout errors

**Solutions:**

1. **Add timeout to commands:**
   ```bash
   timeout 300 aws ec2 describe-instances
   ```

2. **Use pagination for large datasets:**
   ```bash
   aws ec2 describe-instances --max-items 100 --starting-token $token
   ```

3. **Run scripts with verbose output:**
   ```bash
   bash -x script-name.sh
   ```

4. **Check for infinite loops:**
   - Review script logic
   - Add debug output
   - Test with smaller datasets

### Issue: Script Output Errors

**Symptoms:**
- JSON parsing errors
- Malformed output files
- Missing data in reports

**Solutions:**

1. **Validate JSON output:**
   ```bash
   aws ec2 describe-instances | jq '.'
   ```

2. **Handle empty responses:**
   ```bash
   result=$(aws ec2 describe-instances --query 'Reservations[].Instances[]')
   if [ "$result" = "[]" ]; then
     echo "No instances found"
   fi
   ```

3. **Add error handling:**
   ```bash
   if ! aws ec2 describe-instances > instances.json 2>&1; then
     echo "Failed to get instance information"
     exit 1
   fi
   ```

### Issue: Permission Denied on Output Files

**Symptoms:**
- Can't write to output directories
- File creation fails

**Solutions:**

1. **Check directory permissions:**
   ```bash
   ls -la outputs/
   mkdir -p outputs reports logs
   chmod 755 outputs reports logs
   ```

2. **Use relative paths:**
   ```bash
   # Instead of absolute paths, use relative
   ./outputs/report.txt
   ```

3. **Check disk space:**
   ```bash
   df -h
   ```

## Assessment Tool Issues

### Issue: Well-Architected Tool Access Problems

**Symptoms:**
- Can't create workloads
- Can't access existing reviews
- Tool interface errors

**Solutions:**

1. **Verify service availability:**
   ```bash
   aws wellarchitected list-workloads --max-results 1
   ```

2. **Check region availability:**
   ```bash
   # Well-Architected Tool is available in specific regions
   aws wellarchitected list-workloads --region us-east-1
   ```

3. **Clear browser cache:**
   - Clear cookies and cache for AWS Console
   - Try incognito/private browsing mode
   - Try different browser

### Issue: Workload Creation Fails

**Symptoms:**
- Validation errors during workload creation
- Required fields not accepting input
- Timeout during creation

**Solutions:**

1. **Check input validation:**
   - Workload name: 3-100 characters, unique
   - Description: 3-250 characters
   - Environment: Select from dropdown
   - Regions: Valid AWS regions

2. **Use API instead of console:**
   ```bash
   aws wellarchitected create-workload \
     --workload-name "MyWorkload" \
     --description "Test workload for review" \
     --environment PRODUCTION \
     --aws-regions us-east-1
   ```

3. **Check for existing workloads:**
   ```bash
   aws wellarchitected list-workloads
   ```

## Data Collection Problems

### Issue: Incomplete Data Collection

**Symptoms:**
- Missing metrics or configurations
- Partial assessment results
- Empty output files

**Solutions:**

1. **Check service limits:**
   ```bash
   aws service-quotas get-service-quota \
     --service-code ec2 \
     --quota-code L-1216C47A
   ```

2. **Use pagination:**
   ```bash
   aws ec2 describe-instances --max-items 50
   ```

3. **Verify resource existence:**
   ```bash
   aws ec2 describe-instances --dry-run
   ```

4. **Check regional resources:**
   ```bash
   for region in us-east-1 us-west-2 eu-west-1; do
     echo "Checking region: $region"
     aws ec2 describe-instances --region $region
   done
   ```

### Issue: Rate Limiting

**Symptoms:**
- "Throttling" errors
- "RequestLimitExceeded" errors
- Slow API responses

**Solutions:**

1. **Add delays between API calls:**
   ```bash
   sleep 1  # Wait 1 second between calls
   ```

2. **Use exponential backoff:**
   ```bash
   retry_count=0
   max_retries=5
   while [ $retry_count -lt $max_retries ]; do
     if aws ec2 describe-instances; then
       break
     fi
     sleep $((2 ** retry_count))
     retry_count=$((retry_count + 1))
   done
   ```

3. **Request limit increases:**
   - Contact AWS Support for higher limits
   - Use AWS Service Quotas console

## Performance Issues

### Issue: Slow Assessment Execution

**Symptoms:**
- Scripts take hours to complete
- High CPU or memory usage
- System becomes unresponsive

**Solutions:**

1. **Optimize API calls:**
   ```bash
   # Use filters to reduce data
   aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"
   ```

2. **Parallel processing:**
   ```bash
   # Run multiple assessments in parallel
   ./cost-assessment.sh &
   ./security-assessment.sh &
   wait
   ```

3. **Use local caching:**
   ```bash
   # Cache API responses
   if [ ! -f instances.json ]; then
     aws ec2 describe-instances > instances.json
   fi
   ```

4. **Limit scope:**
   - Focus on specific regions
   - Filter by tags or resource types
   - Use time-based filters

## Common Error Messages

### "NoCredentialsError"

**Cause:** AWS credentials not configured
**Solution:**
```bash
aws configure
# or
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
```

### "InvalidUserID.NotFound"

**Cause:** IAM user doesn't exist or wrong account
**Solution:**
```bash
aws sts get-caller-identity  # Verify current user
aws iam get-user  # Check user details
```

### "UnauthorizedOperation"

**Cause:** Insufficient IAM permissions
**Solution:**
- Review and update IAM policies
- Check resource-based policies
- Verify account boundaries

### "RequestLimitExceeded"

**Cause:** API rate limiting
**Solution:**
- Add delays between calls
- Implement retry logic
- Request limit increases

### "ValidationException"

**Cause:** Invalid input parameters
**Solution:**
- Check parameter formats
- Verify required fields
- Review API documentation

## Best Practices for Troubleshooting

### Systematic Approach

1. **Reproduce the issue:**
   - Document exact steps
   - Note error messages
   - Check system state

2. **Isolate the problem:**
   - Test individual components
   - Use minimal test cases
   - Check dependencies

3. **Gather information:**
   - Check logs and output
   - Verify configurations
   - Test permissions

4. **Apply solutions incrementally:**
   - Make one change at a time
   - Test after each change
   - Document what works

### Debugging Techniques

1. **Enable verbose output:**
   ```bash
   set -x  # Enable debug mode
   aws --debug ec2 describe-instances
   ```

2. **Use logging:**
   ```bash
   exec > >(tee -a debug.log)
   exec 2>&1
   ```

3. **Test components individually:**
   ```bash
   # Test AWS CLI
   aws sts get-caller-identity
   
   # Test permissions
   aws iam get-user
   
   # Test specific service
   aws ec2 describe-instances --max-items 1
   ```

### Documentation

1. **Keep detailed logs:**
   - Error messages and stack traces
   - Configuration settings
   - Steps taken to resolve

2. **Create runbooks:**
   - Document common issues
   - Include step-by-step solutions
   - Update based on new issues

3. **Share knowledge:**
   - Update team documentation
   - Create internal wikis
   - Contribute to community resources

## Getting Additional Help

### AWS Support Resources

1. **AWS Documentation:**
   - [AWS CLI User Guide](https://docs.aws.amazon.com/cli/latest/userguide/)
   - [Well-Architected Tool User Guide](https://docs.aws.amazon.com/wellarchitected/latest/userguide/)
   - [IAM User Guide](https://docs.aws.amazon.com/iam/latest/userguide/)

2. **AWS Support:**
   - Basic Support: Documentation and forums
   - Developer Support: Technical support during business hours
   - Business/Enterprise Support: 24/7 technical support

3. **Community Resources:**
   - [AWS Forums](https://forums.aws.amazon.com/)
   - [Stack Overflow](https://stackoverflow.com/questions/tagged/amazon-web-services)
   - [AWS Reddit Community](https://www.reddit.com/r/aws/)

### Professional Services

1. **AWS Professional Services:**
   - Well-Architected Reviews
   - Architecture guidance
   - Implementation support

2. **AWS Partners:**
   - Certified consulting partners
   - Specialized expertise
   - Local support

3. **Training and Certification:**
   - AWS Training and Certification
   - Online courses and labs
   - Hands-on workshops

### Internal Escalation

1. **Team Resources:**
   - Senior engineers and architects
   - DevOps and platform teams
   - Security and compliance teams

2. **Management Support:**
   - Resource allocation
   - Priority adjustment
   - External help authorization

3. **Vendor Support:**
   - Third-party tool vendors
   - Consulting partners
   - System integrators

---

**Remember:** Most issues have been encountered by others before. Don't hesitate to search for solutions online and engage with the AWS community for help.
