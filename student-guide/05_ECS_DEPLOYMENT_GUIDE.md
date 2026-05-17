# AWS ECS Deployment Guide - Instructor Reference

**Complete Technical Guide for Deploying ML Pipeline to AWS ECS with Fargate**

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Pre-Deployment Checklist](#pre-deployment-checklist)
5. [Deployment Process](#deployment-process)
6. [Post-Deployment Verification](#post-deployment-verification)
7. [Monitoring & Operations](#monitoring--operations)
8. [Troubleshooting](#troubleshooting)
9. [Cost Management](#cost-management)
10. [Teaching Notes](#teaching-notes)
11. [Common Student Issues](#common-student-issues)
12. [Advanced Topics](#advanced-topics)

---

## 📖 Overview

### What This Guide Covers

This guide provides complete instructions for deploying the Production ML Churn Prediction System to AWS ECS (Elastic Container Service) using Fargate launch type. It's designed for instructors who need to:

- Deploy the system for demonstration purposes
- Help students troubleshoot deployment issues
- Understand the complete architecture
- Manage costs effectively
- Teach production deployment best practices

### Deployment Summary

**Infrastructure:**
- AWS ECS Fargate (serverless containers)
- Application Load Balancer (ALB)
- RDS PostgreSQL (metadata storage)
- S3 (artifact storage)
- ECR (Docker image registry)
- CloudWatch (logging and monitoring)

**Services Deployed:**
- Airflow (webserver, scheduler, worker)
- MLflow tracking server
- Kafka services (producer, inference, analytics)
- Data and training pipelines (on-demand tasks)

**Estimated Time:**
- Initial setup: 2-3 hours
- Subsequent deployments: 30-45 minutes

**Estimated Cost:**
- ~$200-260/month (with all services running 24/7)
- Can be reduced to ~$50-100/month with scheduled shutdowns

---

## 🏗️ Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AWS CLOUD                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Internet Gateway                                                    │
│         │                                                            │
│         ▼                                                            │
│  ┌──────────────────────────────────────────────────────┐          │
│  │  Application Load Balancer (ALB)                     │          │
│  │  - churn-pipeline-alb                                │          │
│  │  - Port 80  → Airflow UI                             │          │
│  │  - Port 5001 → MLflow UI                             │          │
│  └────────────────────┬─────────────────────────────────┘          │
│                       │                                              │
│                       ▼                                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Target Groups                                                │  │
│  │  - churn-pipeline-airflow-tg (Port 8080)                     │  │
│  │  - churn-pipeline-mlflow-tg (Port 5001)                      │  │
│  └────────────────────┬─────────────────────────────────────────┘  │
│                       │                                              │
│                       ▼                                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  ECS Cluster: churn-pipeline-ecs (Fargate)                   │  │
│  │                                                                │  │
│  │  ┌─────────────────────────────────────────────────────────┐ │  │
│  │  │  Long-Running Services                                   │ │  │
│  │  │                                                           │ │  │
│  │  │  • airflow-webserver-v3    (1 task, 1vCPU, 2GB)         │ │  │
│  │  │  • airflow-scheduler-v2    (1 task, 0.5vCPU, 1GB)       │ │  │
│  │  │  • airflow-worker-v2       (1 task, 1vCPU, 2GB)         │ │  │
│  │  │  • mlflow-tracking         (1 task, 0.5vCPU, 1GB)       │ │  │
│  │  │  • kafka-producer          (1 task, 0.5vCPU, 512MB)     │ │  │
│  │  │  • kafka-inference         (1 task, 0.5vCPU, 1GB)       │ │  │
│  │  │  • kafka-analytics         (1 task, 0.5vCPU, 512MB)     │ │  │
│  │  └─────────────────────────────────────────────────────────┘ │  │
│  │                                                                │  │
│  │  ┌─────────────────────────────────────────────────────────┐ │  │
│  │  │  On-Demand Tasks (Triggered by Airflow)                  │ │  │
│  │  │                                                           │ │  │
│  │  │  • data-pipeline           (2vCPU, 4GB)                  │ │  │
│  │  │  • train-pipeline          (4vCPU, 8GB)                  │ │  │
│  │  └─────────────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                       │                                              │
│                       ▼                                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Supporting Services                                          │  │
│  │                                                                │  │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐ │  │
│  │  │ RDS PostgreSQL │  │   S3 Buckets   │  │   CloudWatch   │ │  │
│  │  │                │  │                │  │                │ │  │
│  │  │ • Airflow DB   │  │ • MLflow       │  │ • Logs         │ │  │
│  │  │ • MLflow DB    │  │   Artifacts    │  │ • Metrics      │ │  │
│  │  │ • Analytics DB │  │ • Model Files  │  │ • Alarms       │ │  │
│  │  └────────────────┘  └────────────────┘  └────────────────┘ │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Network Architecture

```
VPC: churn-pipeline-vpc (10.0.0.0/16)
│
├─ Public Subnets (3 AZs)
│  ├─ 10.0.1.0/24 (ap-south-1a)
│  ├─ 10.0.2.0/24 (ap-south-1b)
│  └─ 10.0.3.0/24 (ap-south-1c)
│  └─ Resources: ALB, NAT Gateways
│
└─ Private Subnets (3 AZs)
   ├─ 10.0.11.0/24 (ap-south-1a)
   ├─ 10.0.12.0/24 (ap-south-1b)
   └─ 10.0.13.0/24 (ap-south-1c)
   └─ Resources: ECS Tasks, RDS
```

### Security Groups

```
┌─────────────────────────────────────────────────────────┐
│  sg-alb (Load Balancer Security Group)                  │
│  Inbound:                                                │
│    - 0.0.0.0/0:80    (HTTP - Airflow UI)                │
│    - 0.0.0.0/0:5001  (HTTP - MLflow UI)                 │
│  Outbound:                                               │
│    - All traffic                                         │
└─────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│  sg-ecs (ECS Tasks Security Group)                      │
│  Inbound:                                                │
│    - sg-alb:8080     (Airflow from ALB)                 │
│    - sg-alb:5001     (MLflow from ALB)                  │
│    - sg-ecs:all      (Inter-task communication)         │
│  Outbound:                                               │
│    - All traffic                                         │
└─────────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│  sg-rds (RDS Security Group)                            │
│  Inbound:                                                │
│    - sg-ecs:5432     (PostgreSQL from ECS)              │
│  Outbound:                                               │
│    - All traffic                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 📋 Prerequisites

### AWS Account Requirements

**Required Services:**
- [x] AWS Account with admin access
- [x] AWS CLI installed and configured
- [x] Sufficient service limits:
  - ECS tasks: 50+
  - Fargate vCPUs: 20+
  - Elastic IPs: 3+
  - VPC: 1+
  - RDS instances: 1+

**Cost Considerations:**
- Free tier eligible: RDS db.t3.micro (750 hours/month)
- Fargate: ~$0.05/vCPU/hour + $0.005/GB/hour
- Data transfer: First 100GB/month free
- CloudWatch: First 5GB logs free

### Local Development Environment

**Required Tools:**
```bash
# 1. AWS CLI (v2.x)
aws --version
# aws-cli/2.x.x

# 2. Docker with AMD64 support
docker --version
# Docker version 24.x.x

docker buildx version
# github.com/docker/buildx v0.11.x

# 3. Git
git --version
# git version 2.x.x

# 4. jq (for JSON parsing)
jq --version
# jq-1.6
```

**AWS CLI Configuration:**
```bash
aws configure
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region name: ap-south-1
# Default output format: json

# Verify configuration
aws sts get-caller-identity
```

### AWS Resources to Create Before Deployment

**1. VPC and Networking** (or use existing):
- VPC with CIDR block
- 3 public subnets (for ALB)
- 3 private subnets (for ECS tasks)
- Internet Gateway
- NAT Gateways (optional, for private subnet internet access)
- Route tables

**2. RDS PostgreSQL Instance:**
```bash
# Instance details
Instance class: db.t3.micro (or larger)
Engine: PostgreSQL 14.x
Storage: 20GB gp3
Multi-AZ: No (for cost savings)
Public access: No

# Databases to create:
- airflow
- mlflow
- analytics
```

**3. S3 Bucket:**
```bash
# Bucket for MLflow artifacts
Bucket name: your-mlflow-artifacts-bucket
Region: ap-south-1
Versioning: Enabled (recommended)
Encryption: AES-256 (default)
```

**4. ECR Repositories** (created by deployment script):
- churn-pipeline/airflow
- churn-pipeline/mlflow
- churn-pipeline/data
- churn-pipeline/model
- churn-pipeline/kafka-producer
- churn-pipeline/kafka-inference
- churn-pipeline/kafka-analytics

---

## ✅ Pre-Deployment Checklist

### Infrastructure Checklist

```bash
# ☐ VPC created
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=churn-pipeline-vpc"

# ☐ Subnets created (3 public, 3 private)
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxx"

# ☐ RDS instance running
aws rds describe-db-instances --db-instance-identifier churn-pipeline-db

# ☐ S3 bucket created
aws s3 ls s3://your-mlflow-artifacts-bucket

# ☐ IAM user/role has necessary permissions
aws iam get-user
```

### Configuration Checklist

```bash
# ☐ Navigate to deployment directory
cd ecs-deployment

# ☐ Copy and edit environment file
cp 00_env.sh.example 00_env.sh
vim 00_env.sh

# ☐ Verify all variables are set
source 00_env.sh
echo $AWS_REGION
echo $ACCOUNT_ID
echo $VPC_ID
echo $RDS_HOST
echo $S3_BUCKET
```

### Docker Images Checklist

```bash
# ☐ All Dockerfiles exist
ls -la docker/Dockerfile.*

# ☐ Base dependencies installed
docker images | grep churn-pipeline

# ☐ Sufficient disk space for builds
df -h
# Need at least 20GB free
```

---

## 🚀 Deployment Process

### Phase 1: Environment Configuration

**Step 1.1: Edit `ecs-deployment/00_env.sh`**

```bash
cd ecs-deployment
vim 00_env.sh
```

**Critical variables to configure:**

```bash
#!/bin/bash

# ═══════════════════════════════════════════════════════════
# AWS CONFIGURATION
# ═══════════════════════════════════════════════════════════

export AWS_REGION="ap-south-1"

# ┌─────────────────────────────────────────────────────────┐
# │ HOW TO GET YOUR AWS ACCOUNT ID                         │
# └─────────────────────────────────────────────────────────┘

# Method 1: Using AWS CLI (recommended)
aws sts get-caller-identity --query Account --output text

# Method 2: From AWS Console
# Go to: AWS Console → Click your name (top-right) → Account ID shown

# Method 3: From IAM
# Go to: AWS Console → IAM → Dashboard → Account ID shown at top

export ACCOUNT_ID="123456789012"  # ← YOUR AWS ACCOUNT ID (from above)

# ═══════════════════════════════════════════════════════════
# NETWORK CONFIGURATION
# ═══════════════════════════════════════════════════════════

# ┌─────────────────────────────────────────────────────────┐
# │ HOW TO GET VPC AND SUBNET IDS USING AWS CLI            │
# └─────────────────────────────────────────────────────────┘

# Method 1: Get your default VPC ID
aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text

# Method 2: List all VPCs (if you have multiple)
aws ec2 describe-vpcs \
  --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock,IsDefault]' \
  --output table

# Method 3: Get VPC by name tag
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=my-vpc-name" \
  --query 'Vpcs[0].VpcId' \
  --output text

# ┌─────────────────────────────────────────────────────────┐
# │ HOW TO GET SUBNET IDS USING AWS CLI                    │
# └─────────────────────────────────────────────────────────┘

# Method 1: Get all subnets in your VPC
VPC_ID="vpc-xxxxx"  # Replace with your VPC ID from above

aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,MapPublicIpOnLaunch,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Method 2: Get PUBLIC subnets (MapPublicIpOnLaunch=true)
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
  --query 'Subnets[*].SubnetId' \
  --output text

# Method 3: Get PRIVATE subnets (MapPublicIpOnLaunch=false)
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=false" \
  --query 'Subnets[*].SubnetId' \
  --output text

# Method 4: Get subnets in JSON array format (for 00_env.sh)
# Public subnets
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
  --query 'Subnets[*].SubnetId' \
  --output json | jq -c '.'

# Private subnets
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=false" \
  --query 'Subnets[*].SubnetId' \
  --output json | jq -c '.'

# Method 5: One-liner to set environment variables (RECOMMENDED)
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text)

# ⚠️ IMPORTANT: If the commands below return empty arrays [], use Method 6 instead
export PUBLIC_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[*].SubnetId' --output json | jq -c '.')
export PRIVATE_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=false" --query 'Subnets[*].SubnetId' --output json | jq -c '.')

# Verify
echo "VPC ID: $VPC_ID"
echo "Public Subnets: $PUBLIC_SUBNETS"
echo "Private Subnets: $PRIVATE_SUBNETS"

# Method 6: If MapPublicIpOnLaunch is not set (returns empty arrays)
# Use ALL subnets for both PUBLIC and PRIVATE (works with any VPC)
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text)
export SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output json | jq -c '.')
export PUBLIC_SUBNETS="$SUBNETS"
export PRIVATE_SUBNETS="$SUBNETS"

# Verify
echo "VPC ID: $VPC_ID"
echo "All Subnets: $SUBNETS"
echo "Public Subnets (ALB): $PUBLIC_SUBNETS"
echo "Private Subnets (ECS): $PRIVATE_SUBNETS"

# ┌─────────────────────────────────────────────────────────┐
# │ TROUBLESHOOTING: Empty subnet arrays                   │
# └─────────────────────────────────────────────────────────┘

# If you get empty arrays [], it means your VPC doesn't have
# MapPublicIpOnLaunch attribute set. This is common and OK!

# Check what you actually have:
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]' \
  --output table

# For ECS Fargate deployment, you can safely use the same subnets
# for both ALB (public) and ECS tasks (private) because:
# ✅ Fargate handles networking automatically
# ✅ ALB provides public access
# ✅ ECS tasks communicate via Service Discovery
# ✅ Security groups control access

# ┌─────────────────────────────────────────────────────────┐
# │ MANUAL CONFIGURATION (if you prefer)                   │
# └─────────────────────────────────────────────────────────┘

export VPC_ID="vpc-xxxxx"  # ← YOUR VPC ID

# Public subnets (for ALB) - JSON array format
export PUBLIC_SUBNETS='["subnet-xxxxx","subnet-yyyyy","subnet-zzzzz"]'

# Private subnets (for ECS tasks) - JSON array format
export PRIVATE_SUBNETS='["subnet-aaaaa","subnet-bbbbb","subnet-ccccc"]'

# ═══════════════════════════════════════════════════════════
# RDS CONFIGURATION
# ═══════════════════════════════════════════════════════════

export RDS_HOST="churn-pipeline-db.xxxxx.ap-south-1.rds.amazonaws.com"
export RDS_PORT="5432"
export RDS_USER="admin"
export RDS_PASSWORD="your-secure-password"  # ← CHANGE THIS

# Database names
export RDS_DB="airflow"
export RDS_MLFLOW_DB="mlflow"
export RDS_ANALYTICS_DB="analytics"

# ═══════════════════════════════════════════════════════════
# S3 CONFIGURATION
# ═══════════════════════════════════════════════════════════

export S3_BUCKET="your-mlflow-artifacts-bucket"  # ← YOUR BUCKET NAME

# ═══════════════════════════════════════════════════════════
# PROJECT CONFIGURATION
# ═══════════════════════════════════════════════════════════

export PROJECT="churn-pipeline"

# ┌─────────────────────────────────────────────────────────┐
# │ ECR REGISTRY - Automatically Constructed               │
# └─────────────────────────────────────────────────────────┘

# ECR Registry URL format: {ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com
# This is automatically constructed from your ACCOUNT_ID and AWS_REGION
# Example: 123456789012.dkr.ecr.ap-south-1.amazonaws.com

export ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Verify it's correct
echo "ECR Registry: $ECR_REGISTRY"

# Expected output example:
# ECR Registry: 123456789012.dkr.ecr.ap-south-1.amazonaws.com

# ═══════════════════════════════════════════════════════════
# TASK RESOURCE ALLOCATION
# ═══════════════════════════════════════════════════════════

# Airflow Services
export AIRFLOW_WEB_CPU=1024      # 1 vCPU
export AIRFLOW_WEB_MEMORY=2048   # 2 GB
export AIRFLOW_SCHEDULER_CPU=512  # 0.5 vCPU
export AIRFLOW_SCHEDULER_MEMORY=1024  # 1 GB
export AIRFLOW_WORKER_CPU=1024   # 1 vCPU
export AIRFLOW_WORKER_MEMORY=2048  # 2 GB

# MLflow Service
export MLFLOW_CPU=512            # 0.5 vCPU
export MLFLOW_MEMORY=1024        # 1 GB

# Pipeline Tasks
export DATA_PIPELINE_CPU=2048    # 2 vCPU
export DATA_PIPELINE_MEMORY=4096  # 4 GB
export TRAIN_PIPELINE_CPU=4096   # 4 vCPU
export TRAIN_PIPELINE_MEMORY=8192  # 8 GB

# Kafka Services
export KAFKA_PRODUCER_CPU=512    # 0.5 vCPU
export KAFKA_PRODUCER_MEMORY=512  # 512 MB
export KAFKA_INFERENCE_CPU=512   # 0.5 vCPU
export KAFKA_INFERENCE_MEMORY=1024  # 1 GB
export KAFKA_ANALYTICS_CPU=512   # 0.5 vCPU
export KAFKA_ANALYTICS_MEMORY=512  # 512 MB
```

**Step 1.2: Load and verify environment:**

```bash
source 00_env.sh

# Verify critical variables
echo "AWS Region: $AWS_REGION"
echo "Account ID: $ACCOUNT_ID"
echo "VPC ID: $VPC_ID"
echo "RDS Host: $RDS_HOST"
echo "S3 Bucket: $S3_BUCKET"

# Save environment for later use
./00_env.sh > .env.out
```

---

### Phase 2: Build Docker Images

**Step 2.1: Build all images for AMD64 architecture**

```bash
# Use the automated build script
./rebuild_for_amd64.sh
```

**Or build individually for more control:**

```bash
# Navigate to project root
cd ..

# 1. Airflow Image
docker build --platform linux/amd64 \
  -f docker/Dockerfile.airflow \
  -t churn-pipeline/airflow:2.8.1-amazon \
  .

# 2. MLflow Image
docker build --platform linux/amd64 \
  -f docker/Dockerfile.mlflow \
  -t churn-pipeline/mlflow:latest \
  .

# 3. Data Pipeline
docker build --platform linux/amd64 \
  -f docker/Dockerfile.base \
  --target data-pipeline \
  -t churn-pipeline/data:latest \
  .

# 4. Training Pipeline
docker build --platform linux/amd64 \
  -f docker/Dockerfile.base \
  --target model-pipeline \
  -t churn-pipeline/model:latest \
  .

# 5. Kafka Producer
docker build --platform linux/amd64 \
  -f docker/Dockerfile.kafka-producer \
  -t kafka/churn-pipeline-producer:latest \
  .

# 6. Kafka Inference
docker build --platform linux/amd64 \
  -f docker/Dockerfile.kafka-inference \
  -t kafka/churn-pipeline-inference:latest \
  .

# 7. Kafka Analytics
docker build --platform linux/amd64 \
  -f docker/Dockerfile.kafka-analytics \
  -t kafka/churn-pipeline-analytics:latest \
  .
```

**Step 2.2: Verify images built successfully:**

```bash
docker images | grep churn-pipeline
docker images | grep kafka
```

**Expected output:**
```
churn-pipeline/airflow     2.8.1-amazon    xxxxx    10 minutes ago    2.1GB
churn-pipeline/mlflow      latest          xxxxx    8 minutes ago     1.2GB
churn-pipeline/data        latest          xxxxx    6 minutes ago     1.8GB
churn-pipeline/model       latest          xxxxx    4 minutes ago     2.5GB
kafka/churn-pipeline-producer    latest    xxxxx    2 minutes ago     800MB
kafka/churn-pipeline-inference   latest    xxxxx    1 minute ago      1.5GB
kafka/churn-pipeline-analytics   latest    xxxxx    30 seconds ago    800MB
```

---

### Phase 3: Push Images to ECR

**Step 3.1: Create ECR repositories**

```bash
cd ecs-deployment
./10_bootstrap.sh
```

**Step 3.2: Login to ECR**

```bash
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY}
```

**Step 3.3: Tag and push all images**

```bash
# Airflow
docker tag churn-pipeline/airflow:2.8.1-amazon \
  ${ECR_REGISTRY}/churn-pipeline/airflow:2.8.1-amazon
docker push ${ECR_REGISTRY}/churn-pipeline/airflow:2.8.1-amazon

# MLflow
docker tag churn-pipeline/mlflow:latest \
  ${ECR_REGISTRY}/churn-pipeline/mlflow:latest
docker push ${ECR_REGISTRY}/churn-pipeline/mlflow:latest

# Data Pipeline
docker tag churn-pipeline/data:latest \
  ${ECR_REGISTRY}/churn-pipeline/data:latest
docker push ${ECR_REGISTRY}/churn-pipeline/data:latest

# Training Pipeline
docker tag churn-pipeline/model:latest \
  ${ECR_REGISTRY}/churn-pipeline/model:latest
docker push ${ECR_REGISTRY}/churn-pipeline/model:latest

# Kafka Services
docker tag kafka/churn-pipeline-producer:latest \
  ${ECR_REGISTRY}/churn-pipeline/kafka-producer:latest
docker push ${ECR_REGISTRY}/churn-pipeline/kafka-producer:latest

docker tag kafka/churn-pipeline-inference:latest \
  ${ECR_REGISTRY}/churn-pipeline/kafka-inference:latest
docker push ${ECR_REGISTRY}/churn-pipeline/kafka-inference:latest

docker tag kafka/churn-pipeline-analytics:latest \
  ${ECR_REGISTRY}/churn-pipeline/kafka-analytics:latest
docker push ${ECR_REGISTRY}/churn-pipeline/kafka-analytics:latest
```

**Step 3.4: Verify images in ECR**

```bash
aws ecr describe-repositories --region ${AWS_REGION} \
  --query 'repositories[?contains(repositoryName, `churn-pipeline`)].repositoryName'

aws ecr list-images --repository-name churn-pipeline/model --region ${AWS_REGION}
```

---

### Phase 4: Infrastructure Setup

**Step 4.1: Create networking resources**

```bash
./20_networking.sh
```

**This creates:**
- Security groups (ALB, ECS, RDS)
- Security group rules
- Verifies VPC and subnets

**Step 4.2: Create IAM roles**

```bash
./30_iam.sh
```

**This creates:**
- ECS task execution role (pulls images from ECR)
- ECS task role (accesses S3, RDS, CloudWatch)
- Policies for S3, RDS, CloudWatch access

**Step 4.3: Create ECS cluster and load balancer**

```bash
./40_cluster_alb.sh
```

**This creates:**
- ECS cluster: `churn-pipeline-ecs`
- Application Load Balancer: `churn-pipeline-alb`
- Target groups:
  - `churn-pipeline-airflow-tg` (port 8080)
  - `churn-pipeline-mlflow-tg` (port 5001)
- Listeners:
  - Port 80 → Airflow target group
  - Port 5001 → MLflow target group

**Step 4.4: Verify infrastructure**

```bash
# Check ECS cluster
aws ecs describe-clusters --clusters ${PROJECT}-ecs --region ${AWS_REGION}

# Check load balancer
aws elbv2 describe-load-balancers --region ${AWS_REGION} \
  --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT}')]"

# Check target groups
aws elbv2 describe-target-groups --region ${AWS_REGION} \
  --query "TargetGroups[?contains(TargetGroupName, '${PROJECT}')]"

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers --region ${AWS_REGION} \
  --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT}')].DNSName" \
  --output text)
echo "ALB DNS: $ALB_DNS"

# Update 00_env.sh with ALB DNS
export MLFLOW_URL="http://${ALB_DNS}:5001"
export ALB_DNS="${ALB_DNS}"
```

---

### Phase 5: Register Task Definitions

**Step 5.1: Register all task definitions**

```bash
./50_register_tasks.sh
```

**This registers:**
- `churn-pipeline-airflow-web`
- `churn-pipeline-airflow-scheduler`
- `churn-pipeline-airflow-worker`
- `churn-pipeline-mlflow`
- `churn-pipeline-data`
- `churn-pipeline-train`
- `churn-pipeline-kafka-producer`
- `churn-pipeline-kafka-inference`
- `churn-pipeline-kafka-analytics`

**Step 5.2: Verify task definitions**

```bash
aws ecs list-task-definitions --region ${AWS_REGION} \
  --family-prefix churn-pipeline

# Check specific task definition
aws ecs describe-task-definition \
  --task-definition churn-pipeline-train \
  --region ${AWS_REGION} \
  --query 'taskDefinition.{Family:family,Revision:revision,CPU:cpu,Memory:memory}'
```

---

### Phase 6: Create ECS Services

**Step 6.1: Create long-running services**

```bash
./60_services.sh
```

**This creates:**
- `airflow-webserver-v3` (with ALB)
- `airflow-scheduler-v2`
- `airflow-worker-v2`
- `mlflow-tracking` (with ALB)
- `kafka-producer`
- `kafka-inference`
- `kafka-analytics`

**Step 6.2: Monitor service creation**

```bash
# Watch services start
watch -n 5 'aws ecs list-services --cluster ${PROJECT}-ecs --region ${AWS_REGION}'

# Check service status
aws ecs describe-services \
  --cluster ${PROJECT}-ecs \
  --services airflow-webserver-v3 mlflow-tracking \
  --region ${AWS_REGION} \
  --query 'services[*].[serviceName,status,runningCount,desiredCount]'
```

**Step 6.3: Wait for services to be healthy (5-10 minutes)**

```bash
# Check target group health
TG_ARN=$(aws elbv2 describe-target-groups \
  --region ${AWS_REGION} \
  --query "TargetGroups[?TargetGroupName=='${PROJECT}-airflow-tg'].TargetGroupArn" \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn ${TG_ARN} \
  --region ${AWS_REGION}

# Expected: TargetHealth.State = "healthy"
```

---

### Phase 7: Initialize Airflow

**Step 7.1: Initialize Airflow database**

```bash
./70_airflow_init.sh
```

**This runs:**
- `airflow db init`
- Creates admin user (username: admin, password: admin)

**Step 7.2: Set Airflow variables**

```bash
./80_airflow_vars.sh
```

**This sets:**
- `S3_BUCKET`
- `MLFLOW_TRACKING_URI`
- `RDS_HOST`, `RDS_USER`, `RDS_PASSWORD`
- `AWS_REGION`
- ECS cluster and task definition ARNs

---

### Phase 8: Verification

**Step 8.1: Access Airflow UI**

```bash
echo "Airflow UI: http://${ALB_DNS}"
echo "Username: admin"
echo "Password: admin"
```

Open in browser and verify:
- [x] Login works
- [x] DAGs are visible (`data_pipeline_dag`, `model_training_dag`)
- [x] Connections are configured
- [x] Variables are set

**Step 8.2: Access MLflow UI**

```bash
echo "MLflow UI: http://${ALB_DNS}:5001"
```

Open in browser and verify:
- [x] UI loads
- [x] "Churn Analysis" experiment exists

**Step 8.3: Check Kafka services**

```bash
# View Kafka service logs
aws logs tail /ecs/churn-pipeline \
  --follow \
  --filter-pattern "kafka-producer" \
  --region ${AWS_REGION} \
  --since 5m
```

---

## ✅ Post-Deployment Verification

### Comprehensive Health Check

```bash
#!/bin/bash
# health_check.sh

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ECS DEPLOYMENT HEALTH CHECK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

source 00_env.sh

echo ""
echo "1. ECS Cluster Status:"
aws ecs describe-clusters --clusters ${PROJECT}-ecs --region ${AWS_REGION} \
  --query 'clusters[0].{Status:status,RunningTasks:runningTasksCount,Services:activeServicesCount}'

echo ""
echo "2. Service Status:"
aws ecs list-services --cluster ${PROJECT}-ecs --region ${AWS_REGION} \
  --query 'serviceArns' --output table

echo ""
echo "3. Running Tasks:"
aws ecs list-tasks --cluster ${PROJECT}-ecs --region ${AWS_REGION} \
  --query 'taskArns' --output table

echo ""
echo "4. Target Group Health:"
for TG in airflow mlflow; do
  TG_ARN=$(aws elbv2 describe-target-groups --region ${AWS_REGION} \
    --query "TargetGroups[?TargetGroupName=='${PROJECT}-${TG}-tg'].TargetGroupArn" \
    --output text)
  echo "  ${TG} target group:"
  aws elbv2 describe-target-health --target-group-arn ${TG_ARN} --region ${AWS_REGION} \
    --query 'TargetHealthDescriptions[*].TargetHealth.State' --output text
done

echo ""
echo "5. Access URLs:"
ALB_DNS=$(aws elbv2 describe-load-balancers --region ${AWS_REGION} \
  --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT}')].DNSName" \
  --output text)
echo "  Airflow UI: http://${ALB_DNS}"
echo "  MLflow UI:  http://${ALB_DNS}:5001"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

### Run Test Pipeline

**Step 1: Trigger data pipeline via Airflow UI**

1. Open Airflow UI
2. Enable `data_pipeline_dag`
3. Click "Trigger DAG"
4. Monitor execution

**Step 2: Trigger training pipeline**

1. Enable `model_training_dag`
2. Click "Trigger DAG"
3. Monitor execution
4. Verify model logged to MLflow

**Step 3: Verify Kafka streaming**

```bash
# Check Kafka producer logs
aws logs tail /ecs/churn-pipeline \
  --follow \
  --filter-pattern "kafka-producer" \
  --region ${AWS_REGION} \
  --since 5m

# Check inference logs
aws logs tail /ecs/churn-pipeline \
  --follow \
  --filter-pattern "kafka-inference" \
  --region ${AWS_REGION} \
  --since 5m

# Check analytics logs
aws logs tail /ecs/churn-pipeline \
  --follow \
  --filter-pattern "kafka-analytics" \
  --region ${AWS_REGION} \
  --since 5m
```

**Step 4: Verify data in RDS**

```bash
# Connect to RDS
psql -h ${RDS_HOST} -U ${RDS_USER} -d ${RDS_ANALYTICS_DB}

# Check predictions table
SELECT COUNT(*) FROM churn_predictions;

# Check high-risk customers
SELECT COUNT(*) FROM high_risk_customers;

# Check metrics
SELECT * FROM churn_metrics_hourly ORDER BY hour DESC LIMIT 5;
```

---

## 📊 Monitoring & Operations

### CloudWatch Logs

**View all log streams:**

```bash
aws logs describe-log-streams \
  --log-group-name /ecs/churn-pipeline \
  --region ${AWS_REGION} \
  --order-by LastEventTime \
  --descending \
  --max-items 20
```

**Tail specific service logs:**

```bash
# Airflow webserver
aws logs tail /ecs/churn-pipeline \
  --follow \
  --filter-pattern "airflow-webserver" \
  --region ${AWS_REGION}

# Training pipeline
aws logs tail /ecs/churn-pipeline \
  --follow \
  --filter-pattern "train-pipeline" \
  --region ${AWS_REGION}

# Kafka inference
aws logs tail /ecs/churn-pipeline \
  --follow \
  --filter-pattern "kafka-inference" \
  --region ${AWS_REGION}
```

**Search for errors:**

```bash
aws logs filter-log-events \
  --log-group-name /ecs/churn-pipeline \
  --filter-pattern "ERROR" \
  --start-time $(($(date +%s) - 3600))000 \
  --region ${AWS_REGION}
```

### Service Health Monitoring

**Check service status:**

```bash
aws ecs describe-services \
  --cluster ${PROJECT}-ecs \
  --services airflow-webserver-v3 airflow-scheduler-v2 mlflow-tracking \
  --region ${AWS_REGION} \
  --query 'services[*].[serviceName,status,runningCount,desiredCount,deployments[0].rolloutState]'
```

**Check task health:**

```bash
# List running tasks
TASK_ARNS=$(aws ecs list-tasks \
  --cluster ${PROJECT}-ecs \
  --region ${AWS_REGION} \
  --query 'taskArns' \
  --output text)

# Describe tasks
aws ecs describe-tasks \
  --cluster ${PROJECT}-ecs \
  --tasks ${TASK_ARNS} \
  --region ${AWS_REGION} \
  --query 'tasks[*].[taskArn,lastStatus,healthStatus,cpu,memory]'
```

### Resource Utilization

**Check CPU and memory usage:**

```bash
# Get CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=${PROJECT}-ecs \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region ${AWS_REGION}
```

### Updating Services

**Update a service with new image:**

```bash
# 1. Build and push new image
docker build --platform linux/amd64 -f docker/Dockerfile.base \
  --target model-pipeline -t churn-pipeline/model:latest .
docker tag churn-pipeline/model:latest ${ECR_REGISTRY}/churn-pipeline/model:latest
docker push ${ECR_REGISTRY}/churn-pipeline/model:latest

# 2. Register new task definition revision
cd ecs-deployment
./50_register_tasks.sh

# 3. Update service (rolling deployment)
aws ecs update-service \
  --cluster ${PROJECT}-ecs \
  --service airflow-webserver-v3 \
  --force-new-deployment \
  --region ${AWS_REGION}

# 4. Monitor deployment
aws ecs describe-services \
  --cluster ${PROJECT}-ecs \
  --services airflow-webserver-v3 \
  --region ${AWS_REGION} \
  --query 'services[0].deployments'
```

**Restart a service:**

```bash
aws ecs update-service \
  --cluster ${PROJECT}-ecs \
  --service kafka-inference \
  --force-new-deployment \
  --region ${AWS_REGION}
```

**Scale a service:**

```bash
aws ecs update-service \
  --cluster ${PROJECT}-ecs \
  --service kafka-inference \
  --desired-count 2 \
  --region ${AWS_REGION}
```

---

## 🔧 Troubleshooting

### Common Issues and Solutions

#### Issue 1: Service Won't Start

**Symptoms:**
- Service shows 0 running tasks
- Tasks keep restarting
- "STOPPED" status in task list

**Diagnosis:**

```bash
# Get stopped tasks
STOPPED_TASKS=$(aws ecs list-tasks \
  --cluster ${PROJECT}-ecs \
  --desired-status STOPPED \
  --region ${AWS_REGION} \
  --query 'taskArns[0]' \
  --output text)

# Describe stopped task
aws ecs describe-tasks \
  --cluster ${PROJECT}-ecs \
  --tasks ${STOPPED_TASKS} \
  --region ${AWS_REGION} \
  --query 'tasks[0].{StoppedReason:stoppedReason,Containers:containers[*].{Name:name,ExitCode:exitCode,Reason:reason}}'
```

**Common causes and fixes:**

1. **Image pull error:**
   ```bash
   # Check ECR permissions
   aws ecr get-repository-policy --repository-name churn-pipeline/model --region ${AWS_REGION}
   
   # Verify task execution role has ECR permissions
   aws iam get-role-policy --role-name ecsTaskExecutionRole --policy-name ECRAccessPolicy
   ```

2. **Environment variable missing:**
   ```bash
   # Check task definition
   aws ecs describe-task-definition \
     --task-definition churn-pipeline-train \
     --region ${AWS_REGION} \
     --query 'taskDefinition.containerDefinitions[0].environment'
   ```

3. **Insufficient resources:**
   ```bash
   # Check service events
   aws ecs describe-services \
     --cluster ${PROJECT}-ecs \
     --services airflow-webserver-v3 \
     --region ${AWS_REGION} \
     --query 'services[0].events[0:10]'
   ```

#### Issue 2: Load Balancer Returns 503

**Symptoms:**
- ALB URL returns "503 Service Temporarily Unavailable"
- Target health checks failing

**Diagnosis:**

```bash
# Check target health
TG_ARN=$(aws elbv2 describe-target-groups \
  --region ${AWS_REGION} \
  --query "TargetGroups[?TargetGroupName=='${PROJECT}-airflow-tg'].TargetGroupArn" \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn ${TG_ARN} \
  --region ${AWS_REGION}
```

**Common causes and fixes:**

1. **No healthy targets:**
   - Wait for tasks to start (5-10 minutes)
   - Check task logs for startup errors

2. **Security group misconfiguration:**
   ```bash
   # Verify ALB can reach ECS tasks
   # ALB security group must allow outbound to ECS security group
   # ECS security group must allow inbound from ALB security group
   
   aws ec2 describe-security-groups \
     --group-ids sg-alb-xxxxx \
     --region ${AWS_REGION} \
     --query 'SecurityGroups[0].IpPermissionsEgress'
   ```

3. **Wrong health check path:**
   ```bash
   # Check target group health check settings
   aws elbv2 describe-target-groups \
     --target-group-arns ${TG_ARN} \
     --region ${AWS_REGION} \
     --query 'TargetGroups[0].{HealthCheckPath:HealthCheckPath,HealthCheckPort:HealthCheckPort,HealthCheckProtocol:HealthCheckProtocol}'
   ```

#### Issue 3: MLflow Not Connecting

**Symptoms:**
- Training pipeline logs show "Connection refused" to MLflow
- Models not appearing in MLflow UI

**Diagnosis:**

```bash
# Check MLFLOW_TRACKING_URI in task definition
aws ecs describe-task-definition \
  --task-definition churn-pipeline-train \
  --region ${AWS_REGION} \
  --query 'taskDefinition.containerDefinitions[0].environment[?name==`MLFLOW_TRACKING_URI`]'
```

**Fix:**

```bash
# Should be: http://ALB_DNS:5001
# NOT: http://mlflow-tracking.internal:5001

# Update 00_env.sh
export MLFLOW_URL="http://${ALB_DNS}:5001"

# Re-register task definitions
./50_register_tasks.sh

# Update services
aws ecs update-service \
  --cluster ${PROJECT}-ecs \
  --service airflow-worker-v2 \
  --force-new-deployment \
  --region ${AWS_REGION}
```

#### Issue 4: RDS Connection Timeout

**Symptoms:**
- Tasks fail with "connection timeout" to RDS
- Airflow can't initialize database

**Diagnosis:**

```bash
# Check RDS security group
RDS_SG=$(aws rds describe-db-instances \
  --db-instance-identifier churn-pipeline-db \
  --region ${AWS_REGION} \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

aws ec2 describe-security-groups \
  --group-ids ${RDS_SG} \
  --region ${AWS_REGION} \
  --query 'SecurityGroups[0].IpPermissions'
```

**Fix:**

```bash
# RDS security group must allow inbound from ECS security group
aws ec2 authorize-security-group-ingress \
  --group-id ${RDS_SG} \
  --protocol tcp \
  --port 5432 \
  --source-group ${SG_ECS_ID} \
  --region ${AWS_REGION}
```

#### Issue 5: High Costs

**Symptoms:**
- AWS bill higher than expected
- Fargate costs accumulating

**Diagnosis:**

```bash
# Check running tasks
aws ecs list-tasks --cluster ${PROJECT}-ecs --region ${AWS_REGION}

# Check task resource allocation
aws ecs describe-task-definition \
  --task-definition churn-pipeline-train \
  --region ${AWS_REGION} \
  --query 'taskDefinition.{CPU:cpu,Memory:memory}'

# Calculate monthly cost
# Cost = (vCPU * $0.04656 + Memory_GB * $0.00511) * hours_per_month
```

**Fixes:**

1. **Stop non-essential services:**
   ```bash
   # Stop Kafka services during off-hours
   aws ecs update-service \
     --cluster ${PROJECT}-ecs \
     --service kafka-producer \
     --desired-count 0 \
     --region ${AWS_REGION}
   ```

2. **Right-size tasks:**
   ```bash
   # Reduce training pipeline resources if not needed
   # Edit 00_env.sh
   export TRAIN_PIPELINE_CPU=2048  # Instead of 4096
   export TRAIN_PIPELINE_MEMORY=4096  # Instead of 8192
   
   # Re-register and update
   ./50_register_tasks.sh
   ```

3. **Use Spot instances for training:**
   ```bash
   # Modify task definition to use FARGATE_SPOT capacity provider
   # Can save up to 70% on training costs
   ```

---

## 💰 Cost Management

### Cost Breakdown

**Monthly Costs (All Services Running 24/7):**

| Service | vCPU | Memory (GB) | Hours/Month | Fargate Cost |
|---------|------|-------------|-------------|--------------|
| Airflow Web | 1.0 | 2.0 | 730 | $41.32 |
| Airflow Scheduler | 0.5 | 1.0 | 730 | $20.66 |
| Airflow Worker | 1.0 | 2.0 | 730 | $41.32 |
| MLflow | 0.5 | 1.0 | 730 | $20.66 |
| Kafka Producer | 0.5 | 0.5 | 730 | $18.69 |
| Kafka Inference | 0.5 | 1.0 | 730 | $20.66 |
| Kafka Analytics | 0.5 | 0.5 | 730 | $18.69 |
| **Subtotal** | **4.5** | **8.0** | | **$182.00** |

**Additional Costs:**
- RDS db.t3.micro: $15-25/month
- S3 storage (100GB): $2-3/month
- Data transfer: $5-15/month
- CloudWatch logs (5GB): Free
- **Total: ~$204-225/month**

### Cost Optimization Strategies

**1. Scheduled Shutdowns:**

```bash
#!/bin/bash
# stop_non_essential_services.sh

# Stop Kafka services (can restart when needed)
for SERVICE in kafka-producer kafka-inference kafka-analytics; do
  aws ecs update-service \
    --cluster ${PROJECT}-ecs \
    --service ${SERVICE} \
    --desired-count 0 \
    --region ${AWS_REGION}
done

# Savings: ~$58/month
```

**2. Use Fargate Spot for Training:**

```json
// taskdefs/train-pipeline.json.template
{
  "requiresCompatibilities": ["FARGATE"],
  "capacityProviderStrategy": [
    {
      "capacityProvider": "FARGATE_SPOT",
      "weight": 1,
      "base": 0
    }
  ]
}

// Savings: Up to 70% on training costs
```

**3. Right-Size Resources:**

```bash
# Monitor actual usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=airflow-webserver-v3 \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average \
  --region ${AWS_REGION}

# If average CPU < 30%, reduce allocation
```

**4. Use RDS Reserved Instances:**

```bash
# 1-year reserved instance: 40% savings
# 3-year reserved instance: 60% savings

aws rds purchase-reserved-db-instances-offering \
  --reserved-db-instances-offering-id xxxxx \
  --reserved-db-instance-id churn-pipeline-db-reserved
```

**5. Enable S3 Intelligent-Tiering:**

```bash
aws s3api put-bucket-intelligent-tiering-configuration \
  --bucket ${S3_BUCKET} \
  --id EntirePrefix \
  --intelligent-tiering-configuration '{
    "Id": "EntirePrefix",
    "Status": "Enabled",
    "Tierings": [
      {
        "Days": 90,
        "AccessTier": "ARCHIVE_ACCESS"
      },
      {
        "Days": 180,
        "AccessTier": "DEEP_ARCHIVE_ACCESS"
      }
    ]
  }'

# Savings: 40-95% on old artifacts
```

### Cost Monitoring

**Set up billing alerts:**

```bash
# Create SNS topic for alerts
aws sns create-topic --name billing-alerts --region us-east-1

# Subscribe to topic
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:${ACCOUNT_ID}:billing-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com \
  --region us-east-1

# Create billing alarm
aws cloudwatch put-metric-alarm \
  --alarm-name monthly-billing-alarm \
  --alarm-description "Alert when monthly bill exceeds $250" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --evaluation-periods 1 \
  --threshold 250 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:${ACCOUNT_ID}:billing-alerts \
  --region us-east-1
```

---

## 🎓 Teaching Notes

### Recommended Teaching Approach

**Week 1: Local Development**
- Students run system locally with Docker Compose
- Understand services and data flow
- No AWS costs

**Week 2: AWS Fundamentals**
- Introduce VPC, subnets, security groups
- Create RDS instance
- Create S3 bucket
- Estimated cost: $20-30

**Week 3: ECS Deployment**
- Build and push Docker images
- Deploy to ECS
- Monitor services
- Estimated cost: $50-100 (partial month)

**Week 4: Operations & Optimization**
- Monitoring with CloudWatch
- Cost optimization
- Troubleshooting
- Cleanup

### Student Lab Exercises

**Exercise 1: Deploy a Single Service**
- Task: Deploy only MLflow to ECS
- Learning: Task definitions, services, ALB
- Time: 1-2 hours

**Exercise 2: Scale Services**
- Task: Scale Kafka inference from 1 to 3 tasks
- Learning: Service scaling, load balancing
- Time: 30 minutes

**Exercise 3: Update Service**
- Task: Make code change, rebuild, redeploy
- Learning: Rolling deployments, zero-downtime updates
- Time: 1 hour

**Exercise 4: Debug Production Issue**
- Task: Intentionally break a service, debug using CloudWatch
- Learning: Troubleshooting, logs analysis
- Time: 1 hour

### Grading Rubric

**Deployment (40 points)**
- [ ] All services running (20 pts)
- [ ] Services accessible via ALB (10 pts)
- [ ] Proper security group configuration (10 pts)

**Monitoring (20 points)**
- [ ] CloudWatch logs enabled (10 pts)
- [ ] Can retrieve and interpret logs (10 pts)

**Operations (20 points)**
- [ ] Successfully update a service (10 pts)
- [ ] Successfully scale a service (10 pts)

**Cost Management (20 points)**
- [ ] Estimate monthly costs (10 pts)
- [ ] Implement one cost optimization (10 pts)

---

## 🔍 Common Student Issues

### Issue 1: "I don't have an AWS account"

**Solution:**
- AWS Free Tier provides 750 hours/month of t3.micro (RDS)
- Students can create account with credit card (no charges if within free tier)
- Alternative: Use AWS Educate or AWS Academy credits

### Issue 2: "My AWS bill is too high"

**Diagnosis:**
```bash
# Check what's running
aws ecs list-tasks --cluster ${PROJECT}-ecs --region ${AWS_REGION}

# Check RDS instances
aws rds describe-db-instances --region ${AWS_REGION}

# Check NAT Gateways (expensive!)
aws ec2 describe-nat-gateways --region ${AWS_REGION}
```

**Solution:**
- Stop all ECS services when not in use
- Delete NAT Gateways (use public subnets with assignPublicIp=ENABLED)
- Use RDS stop/start feature (stops for 7 days)

### Issue 3: "Docker build is too slow"

**Solution:**
```bash
# Use BuildKit
export DOCKER_BUILDKIT=1

# Use layer caching
docker build --cache-from ${ECR_REGISTRY}/churn-pipeline/model:latest \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  -t churn-pipeline/model:latest .

# Build on EC2 instance (faster network to ECR)
```

### Issue 4: "I can't access the Airflow UI"

**Checklist:**
```bash
# 1. Is the service running?
aws ecs describe-services \
  --cluster ${PROJECT}-ecs \
  --services airflow-webserver-v3 \
  --region ${AWS_REGION} \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# 2. Is the target healthy?
aws elbv2 describe-target-health --target-group-arn ${TG_ARN} --region ${AWS_REGION}

# 3. Is the ALB listener configured?
aws elbv2 describe-listeners \
  --load-balancer-arn ${ALB_ARN} \
  --region ${AWS_REGION}

# 4. Is the security group allowing traffic?
aws ec2 describe-security-groups --group-ids ${SG_ALB_ID} --region ${AWS_REGION}
```

### Issue 5: "Training pipeline fails with OOM"

**Solution:**
```bash
# Increase memory allocation
export TRAIN_PIPELINE_MEMORY=16384  # 16 GB

# Re-register task definition
./50_register_tasks.sh

# Or reduce batch size in training code
```

---

## 🚀 Advanced Topics

### Auto-Scaling

**Configure auto-scaling for Kafka inference:**

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/${PROJECT}-ecs/kafka-inference \
  --min-capacity 1 \
  --max-capacity 5 \
  --region ${AWS_REGION}

# Create scaling policy (target tracking)
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/${PROJECT}-ecs/kafka-inference \
  --policy-name cpu-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    },
    "ScaleOutCooldown": 60,
    "ScaleInCooldown": 60
  }' \
  --region ${AWS_REGION}
```

### Blue-Green Deployment

**Set up CodeDeploy for blue-green deployments:**

```bash
# Create CodeDeploy application
aws deploy create-application \
  --application-name ${PROJECT}-app \
  --compute-platform ECS \
  --region ${AWS_REGION}

# Create deployment group
aws deploy create-deployment-group \
  --application-name ${PROJECT}-app \
  --deployment-group-name ${PROJECT}-dg \
  --service-role-arn arn:aws:iam::${ACCOUNT_ID}:role/CodeDeployServiceRole \
  --ecs-services clusterName=${PROJECT}-ecs,serviceName=airflow-webserver-v3 \
  --load-balancer-info targetGroupInfoList=[{name=${PROJECT}-airflow-tg}] \
  --blue-green-deployment-configuration '{
    "terminateBlueInstancesOnDeploymentSuccess": {
      "action": "TERMINATE",
      "terminationWaitTimeInMinutes": 5
    },
    "deploymentReadyOption": {
      "actionOnTimeout": "CONTINUE_DEPLOYMENT"
    }
  }' \
  --region ${AWS_REGION}
```

### CI/CD Integration

**GitHub Actions workflow for ECS deployment:**

```yaml
# .github/workflows/deploy-ecs.yml
name: Deploy to ECS

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-south-1
      
      - name: Login to ECR
        uses: aws-actions/amazon-ecr-login@v1
      
      - name: Build and push image
        run: |
          docker build --platform linux/amd64 \
            -f docker/Dockerfile.base \
            --target model-pipeline \
            -t ${{ secrets.ECR_REGISTRY }}/churn-pipeline/model:${{ github.sha }} .
          docker push ${{ secrets.ECR_REGISTRY }}/churn-pipeline/model:${{ github.sha }}
      
      - name: Update ECS service
        run: |
          aws ecs update-service \
            --cluster churn-pipeline-ecs \
            --service airflow-worker-v2 \
            --force-new-deployment
```

### Secrets Management

**Use AWS Secrets Manager:**

```bash
# Store RDS password
aws secretsmanager create-secret \
  --name ${PROJECT}/rds/password \
  --secret-string "${RDS_PASSWORD}" \
  --region ${AWS_REGION}

# Update task definition to use secret
# taskdefs/train-pipeline.json.template
{
  "secrets": [
    {
      "name": "RDS_PASSWORD",
      "valueFrom": "arn:aws:secretsmanager:ap-south-1:${ACCOUNT_ID}:secret:${PROJECT}/rds/password"
    }
  ]
}
```

---

## 🧹 Cleanup

### Complete Cleanup Script

```bash
#!/bin/bash
# cleanup_all.sh

set -e

source 00_env.sh

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "CLEANING UP ALL ECS RESOURCES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Scale down all services to 0
echo "Scaling down services..."
for SERVICE in airflow-webserver-v3 airflow-scheduler-v2 airflow-worker-v2 \
               mlflow-tracking kafka-producer kafka-inference kafka-analytics; do
  aws ecs update-service \
    --cluster ${PROJECT}-ecs \
    --service ${SERVICE} \
    --desired-count 0 \
    --region ${AWS_REGION} 2>/dev/null || true
done

sleep 30

# 2. Delete services
echo "Deleting services..."
for SERVICE in airflow-webserver-v3 airflow-scheduler-v2 airflow-worker-v2 \
               mlflow-tracking kafka-producer kafka-inference kafka-analytics; do
  aws ecs delete-service \
    --cluster ${PROJECT}-ecs \
    --service ${SERVICE} \
    --force \
    --region ${AWS_REGION} 2>/dev/null || true
done

sleep 60

# 3. Delete cluster
echo "Deleting ECS cluster..."
aws ecs delete-cluster --cluster ${PROJECT}-ecs --region ${AWS_REGION}

# 4. Delete load balancer
echo "Deleting load balancer..."
ALB_ARN=$(aws elbv2 describe-load-balancers --region ${AWS_REGION} \
  --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT}')].LoadBalancerArn" \
  --output text)
aws elbv2 delete-load-balancer --load-balancer-arn ${ALB_ARN} --region ${AWS_REGION}

sleep 30

# 5. Delete target groups
echo "Deleting target groups..."
for TG in airflow mlflow; do
  TG_ARN=$(aws elbv2 describe-target-groups --region ${AWS_REGION} \
    --query "TargetGroups[?TargetGroupName=='${PROJECT}-${TG}-tg'].TargetGroupArn" \
    --output text)
  aws elbv2 delete-target-group --target-group-arn ${TG_ARN} --region ${AWS_REGION}
done

# 6. Delete security groups
echo "Deleting security groups..."
sleep 60  # Wait for ENIs to be released
for SG in alb ecs rds; do
  SG_ID=$(aws ec2 describe-security-groups --region ${AWS_REGION} \
    --filters "Name=group-name,Values=${PROJECT}-${SG}-sg" \
    --query 'SecurityGroups[0].GroupId' --output text)
  aws ec2 delete-security-group --group-id ${SG_ID} --region ${AWS_REGION} 2>/dev/null || true
done

# 7. Deregister task definitions (optional - they don't cost anything)
echo "Deregistering task definitions..."
for FAMILY in airflow-web airflow-scheduler airflow-worker mlflow data train \
              kafka-producer kafka-inference kafka-analytics; do
  TASK_DEFS=$(aws ecs list-task-definitions --family-prefix ${PROJECT}-${FAMILY} \
    --region ${AWS_REGION} --query 'taskDefinitionArns' --output text)
  for TD in ${TASK_DEFS}; do
    aws ecs deregister-task-definition --task-definition ${TD} --region ${AWS_REGION}
  done
done

# 8. Delete ECR repositories (optional - keeps images)
echo "Deleting ECR repositories..."
for REPO in airflow mlflow data model kafka-producer kafka-inference kafka-analytics; do
  aws ecr delete-repository \
    --repository-name ${PROJECT}/${REPO} \
    --force \
    --region ${AWS_REGION} 2>/dev/null || true
done

# 9. Delete CloudWatch log group
echo "Deleting CloudWatch logs..."
aws logs delete-log-group --log-group-name /ecs/${PROJECT} --region ${AWS_REGION}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ CLEANUP COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Note: RDS instance and S3 bucket were NOT deleted."
echo "To delete manually:"
echo "  aws rds delete-db-instance --db-instance-identifier churn-pipeline-db --skip-final-snapshot"
echo "  aws s3 rb s3://${S3_BUCKET} --force"
```

---

## 📚 Additional Resources

### AWS Documentation
- [ECS Developer Guide](https://docs.aws.amazon.com/ecs/)
- [Fargate User Guide](https://docs.aws.amazon.com/AmazonECS/latest/userguide/what-is-fargate.html)
- [Application Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)

### Best Practices
- [ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/intro.html)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

### Cost Optimization
- [AWS Cost Optimization](https://aws.amazon.com/pricing/cost-optimization/)
- [Fargate Spot](https://aws.amazon.com/fargate/pricing/)

---

**Last Updated**: 2025-01-26  
**Version**: 1.0  
**Maintained By**: Production ML Systems Course Team  
**Questions?** Contact the instructor or open an issue on GitHub.


