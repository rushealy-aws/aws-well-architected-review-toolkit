#!/bin/bash

# AWS Well-Architected Review Toolkit - Environment Setup Script
# This script sets up the necessary AWS CLI configuration and permissions

set -e

echo "=== AWS Well-Architected Review Toolkit Setup ==="

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first:"
    echo "   https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

echo "✅ AWS CLI is installed"

# Check AWS CLI configuration
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured. Please run 'aws configure' first"
    exit 1
fi

echo "✅ AWS CLI is configured"

# Get current AWS account and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

echo "📋 Current AWS Configuration:"
echo "   Account ID: $ACCOUNT_ID"
echo "   Region: $REGION"

# Check required permissions
echo "🔍 Checking AWS permissions..."

# Check Well-Architected Tool permissions
if aws wellarchitected list-workloads --max-results 1 &> /dev/null; then
    echo "✅ Well-Architected Tool access confirmed"
else
    echo "⚠️  Warning: Limited Well-Architected Tool access"
fi

# Check CloudWatch permissions
if aws cloudwatch list-metrics --max-records 1 &> /dev/null; then
    echo "✅ CloudWatch access confirmed"
else
    echo "⚠️  Warning: Limited CloudWatch access"
fi

# Check EC2 permissions
if aws ec2 describe-instances --max-items 1 &> /dev/null; then
    echo "✅ EC2 access confirmed"
else
    echo "⚠️  Warning: Limited EC2 access"
fi

# Create local directories for outputs
mkdir -p outputs
mkdir -p reports
mkdir -p logs

echo "📁 Created local directories for outputs"

# Set up environment variables
cat > .env << EOF
# AWS Well-Architected Review Toolkit Environment Variables
AWS_ACCOUNT_ID=$ACCOUNT_ID
AWS_DEFAULT_REGION=$REGION
TOOLKIT_VERSION=1.0.0
REVIEW_DATE=$(date +%Y-%m-%d)
EOF

echo "✅ Environment setup completed!"
echo ""
echo "🚀 You're ready to start your Well-Architected reviews!"
echo "   Navigate to any pillar directory and follow the GUIDE.md instructions"
echo ""
echo "📚 Available pillars:"
echo "   - cost-optimization/"
echo "   - reliability/"
echo "   - security/"
echo "   - performance-efficiency/"
echo "   - operational-excellence/"
echo "   - sustainability/"
