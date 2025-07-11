# Three-Tier Web Application - Well-Architected Reference

This reference architecture demonstrates how to implement a three-tier web application following AWS Well-Architected Framework principles across all six pillars.

## Architecture Overview

```
Internet Gateway
       |
   CloudFront CDN
       |
Application Load Balancer
       |
   Auto Scaling Group
   (Web/App Servers)
       |
   Database Tier
   (RDS + ElastiCache)
```

## Architecture Components

### Presentation Tier
- **Amazon CloudFront**: Global content delivery network
- **AWS WAF**: Web application firewall protection
- **Application Load Balancer**: Layer 7 load balancing
- **Auto Scaling Group**: Automatic capacity management

### Application Tier
- **Amazon EC2**: Compute instances for application logic
- **AWS Systems Manager**: Configuration and patch management
- **Amazon ECS/EKS**: Container orchestration (alternative)
- **AWS Lambda**: Serverless functions for specific tasks

### Data Tier
- **Amazon RDS**: Managed relational database
- **Amazon ElastiCache**: In-memory caching layer
- **Amazon S3**: Object storage for static assets
- **Amazon EBS**: Block storage for instances

## Well-Architected Implementation

### 1. Cost Optimization

#### Design Decisions
- **Right-sizing**: Use AWS Compute Optimizer recommendations
- **Reserved Capacity**: Purchase RIs for predictable workloads
- **Auto Scaling**: Scale based on demand to avoid over-provisioning
- **Storage Optimization**: Use appropriate storage classes

#### Implementation
```yaml
# Auto Scaling Configuration
AutoScalingGroup:
  MinSize: 2
  MaxSize: 10
  DesiredCapacity: 4
  TargetGroupARNs: 
    - !Ref ApplicationLoadBalancerTargetGroup
  HealthCheckType: ELB
  HealthCheckGracePeriod: 300
  
# Reserved Instance Strategy
ReservedInstances:
  InstanceType: m5.large
  Term: 1-year
  PaymentOption: Partial Upfront
  Coverage: 70% of baseline capacity
```

#### Cost Monitoring
- CloudWatch billing alerts
- AWS Cost Explorer analysis
- Monthly cost optimization reviews
- Resource tagging for cost allocation

### 2. Reliability

#### Design Decisions
- **Multi-AZ Deployment**: Distribute across availability zones
- **Auto Recovery**: Automatic instance replacement
- **Database Backup**: Automated backups and point-in-time recovery
- **Health Checks**: Comprehensive monitoring and alerting

#### Implementation
```yaml
# Multi-AZ RDS Configuration
DatabaseInstance:
  Engine: mysql
  EngineVersion: 8.0
  MultiAZ: true
  BackupRetentionPeriod: 7
  PreferredBackupWindow: "03:00-04:00"
  PreferredMaintenanceWindow: "sun:04:00-sun:05:00"
  
# Auto Scaling Health Checks
HealthCheck:
  Type: ELB
  GracePeriod: 300
  UnhealthyThreshold: 2
  HealthyThreshold: 2
```

#### Disaster Recovery
- **RTO**: 4 hours
- **RPO**: 1 hour
- Cross-region backup replication
- Documented recovery procedures

### 3. Security

#### Design Decisions
- **Defense in Depth**: Multiple security layers
- **Least Privilege**: Minimal required permissions
- **Encryption**: Data protection at rest and in transit
- **Network Isolation**: VPC with private subnets

#### Implementation
```yaml
# VPC Security Configuration
VPC:
  CidrBlock: 10.0.0.0/16
  EnableDnsHostnames: true
  EnableDnsSupport: true

PrivateSubnet:
  CidrBlock: 10.0.1.0/24
  AvailabilityZone: us-east-1a

SecurityGroup:
  GroupDescription: Web tier security group
  SecurityGroupIngress:
    - IpProtocol: tcp
      FromPort: 80
      ToPort: 80
      SourceSecurityGroupId: !Ref LoadBalancerSecurityGroup
```

#### Security Controls
- AWS WAF for application protection
- VPC Flow Logs for network monitoring
- CloudTrail for API logging
- GuardDuty for threat detection
- Config for compliance monitoring

### 4. Performance Efficiency

#### Design Decisions
- **CDN**: CloudFront for global content delivery
- **Caching**: ElastiCache for database query optimization
- **Load Balancing**: Distribute traffic efficiently
- **Instance Types**: Optimized for workload characteristics

#### Implementation
```yaml
# CloudFront Distribution
CloudFrontDistribution:
  DistributionConfig:
    Origins:
      - DomainName: !GetAtt LoadBalancer.DNSName
        Id: ALB-Origin
        CustomOriginConfig:
          HTTPPort: 80
          OriginProtocolPolicy: http-only
    DefaultCacheBehavior:
      TargetOriginId: ALB-Origin
      ViewerProtocolPolicy: redirect-to-https
      CachePolicyId: 4135ea2d-6df8-44a3-9df3-4b5a84be39ad
```

#### Performance Monitoring
- CloudWatch metrics and alarms
- X-Ray distributed tracing
- Real User Monitoring (RUM)
- Load testing with realistic scenarios

### 5. Operational Excellence

#### Design Decisions
- **Infrastructure as Code**: CloudFormation/CDK templates
- **CI/CD Pipeline**: Automated deployment process
- **Monitoring**: Comprehensive observability
- **Documentation**: Runbooks and procedures

#### Implementation
```yaml
# CodePipeline Configuration
Pipeline:
  RoleArn: !GetAtt CodePipelineRole.Arn
  Stages:
    - Name: Source
      Actions:
        - Name: SourceAction
          ActionTypeId:
            Category: Source
            Owner: AWS
            Provider: S3
    - Name: Build
      Actions:
        - Name: BuildAction
          ActionTypeId:
            Category: Build
            Owner: AWS
            Provider: CodeBuild
    - Name: Deploy
      Actions:
        - Name: DeployAction
          ActionTypeId:
            Category: Deploy
            Owner: AWS
            Provider: CloudFormation
```

#### Operational Practices
- Automated deployment pipelines
- Blue/green deployment strategy
- Comprehensive logging and monitoring
- Regular operational reviews
- Incident response procedures

### 6. Sustainability

#### Design Decisions
- **Efficient Instance Types**: AWS Graviton processors
- **Serverless**: Lambda for event-driven workloads
- **Auto Scaling**: Right-size resources dynamically
- **Region Selection**: Choose regions with renewable energy

#### Implementation
```yaml
# Graviton-based Instances
LaunchTemplate:
  LaunchTemplateData:
    ImageId: ami-0abcdef1234567890  # Amazon Linux 2 ARM64
    InstanceType: m6g.large
    IamInstanceProfile:
      Arn: !GetAtt InstanceProfile.Arn
    UserData:
      Fn::Base64: !Sub |
        #!/bin/bash
        yum update -y
        # Application setup commands
```

#### Sustainability Practices
- Regular resource utilization reviews
- Automated shutdown of non-production environments
- Use of managed services to reduce overhead
- Carbon footprint monitoring and reporting

## Deployment Guide

### Prerequisites
- AWS CLI configured
- CloudFormation or CDK installed
- Appropriate IAM permissions

### Step 1: Network Infrastructure
```bash
# Deploy VPC and networking components
aws cloudformation create-stack \
  --stack-name three-tier-network \
  --template-body file://network-template.yaml \
  --parameters ParameterKey=Environment,ParameterValue=prod
```

### Step 2: Security Components
```bash
# Deploy security groups and IAM roles
aws cloudformation create-stack \
  --stack-name three-tier-security \
  --template-body file://security-template.yaml \
  --capabilities CAPABILITY_IAM
```

### Step 3: Database Tier
```bash
# Deploy RDS and ElastiCache
aws cloudformation create-stack \
  --stack-name three-tier-database \
  --template-body file://database-template.yaml \
  --parameters ParameterKey=DBPassword,ParameterValue=SecurePassword123
```

### Step 4: Application Tier
```bash
# Deploy EC2 instances and Auto Scaling
aws cloudformation create-stack \
  --stack-name three-tier-application \
  --template-body file://application-template.yaml
```

### Step 5: Presentation Tier
```bash
# Deploy load balancer and CloudFront
aws cloudformation create-stack \
  --stack-name three-tier-presentation \
  --template-body file://presentation-template.yaml
```

## Monitoring and Alerting

### Key Metrics
- **Application Performance**: Response time, throughput, error rate
- **Infrastructure Health**: CPU, memory, disk utilization
- **Security Events**: Failed login attempts, suspicious activity
- **Cost Metrics**: Daily spend, resource utilization

### Alerting Configuration
```yaml
# CloudWatch Alarms
HighCPUAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: High-CPU-Utilization
    MetricName: CPUUtilization
    Namespace: AWS/EC2
    Statistic: Average
    Period: 300
    EvaluationPeriods: 2
    Threshold: 80
    ComparisonOperator: GreaterThanThreshold
    AlarmActions:
      - !Ref SNSTopicArn
```

## Testing Strategy

### Load Testing
- Use AWS Load Testing Solution
- Test with realistic traffic patterns
- Validate auto-scaling behavior
- Measure performance under stress

### Security Testing
- Penetration testing
- Vulnerability assessments
- Configuration compliance checks
- Access control validation

### Disaster Recovery Testing
- Regular backup restoration tests
- Failover procedure validation
- Recovery time measurement
- Documentation updates

## Cost Optimization

### Monthly Cost Breakdown (Example)
- **Compute (EC2)**: $2,400 (40%)
- **Database (RDS)**: $1,800 (30%)
- **Storage (EBS/S3)**: $600 (10%)
- **Network (CloudFront/ALB)**: $720 (12%)
- **Other Services**: $480 (8%)
- **Total**: $6,000/month

### Optimization Opportunities
- Reserved Instances for 50% savings on compute
- Spot Instances for development environments
- S3 Intelligent Tiering for storage optimization
- CloudFront caching to reduce origin load

## Compliance and Governance

### Tagging Strategy
```yaml
Tags:
  - Key: Environment
    Value: Production
  - Key: Application
    Value: WebApp
  - Key: Owner
    Value: DevOps-Team
  - Key: CostCenter
    Value: Engineering
  - Key: Compliance
    Value: SOX-PCI
```

### Compliance Controls
- AWS Config rules for configuration compliance
- CloudTrail for audit logging
- GuardDuty for security monitoring
- Security Hub for centralized findings

## Troubleshooting Guide

### Common Issues
1. **High Response Times**: Check database performance, enable caching
2. **Auto Scaling Issues**: Verify health check configuration
3. **Security Group Blocks**: Review inbound/outbound rules
4. **Database Connectivity**: Check security groups and network ACLs

### Debugging Tools
- CloudWatch Logs for application logs
- X-Ray for distributed tracing
- VPC Flow Logs for network analysis
- AWS Systems Manager for instance access

---

This reference architecture provides a comprehensive example of implementing Well-Architected principles in a real-world scenario. Adapt the configuration based on your specific requirements and constraints.
