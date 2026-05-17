# AWS ECS Deployment - Command Cheat Sheet

**All commands you need to deploy to AWS, step by step!**

Welcome! 👋 This guide provides every command you need to deploy your ML system to AWS ECS, in the exact order you should run them. Just copy, paste, and follow along!

---

## 📋 Table of Contents

1. [Before You Start](#before-you-start)
2. [Step 1: Check Your Tools](#step-1-check-your-tools)
3. [Step 2: Configure AWS](#step-2-configure-aws)
4. [Step 3: Set Up Environment](#step-3-set-up-environment)
5. [Step 4: Build Docker Images](#step-4-build-docker-images)
6. [Step 5: Push to AWS](#step-5-push-to-aws)
7. [Step 6: Create Infrastructure](#step-6-create-infrastructure)
8. [Step 7: Deploy Services](#step-7-deploy-services)
9. [Step 8: Initialize Airflow](#step-8-initialize-airflow)
10. [Step 9: Verify Everything Works](#step-9-verify-everything-works)
11. [Monitoring Your System](#monitoring-your-system)
12. [When Things Go Wrong](#when-things-go-wrong)
13. [Cleaning Up](#cleaning-up)

---

## 🎯 Before You Start

### What You Need

- ✅ AWS Account (free tier works!)
- ✅ Docker Desktop running
- ✅ AWS CLI installed
- ✅ At least 20GB free disk space
- ✅ 2-3 hours of time

### Important Notes

- **Copy-paste carefully!** Commands are case-sensitive
- **Wait for each step to complete** before moving to the next
- **Save your ALB DNS** - you'll need it to access services
- **Monitor costs** - set up billing alerts!

---

## Step 1: Check Your Tools

### Check Docker

```bash
docker --version
```

**You should see:**
```
Docker version 24.0.7, build afdd53b
```

**If not:** Install Docker Desktop from [docker.com](https://www.docker.com/products/docker-desktop/)

---

### Check AWS CLI

```bash
aws --version
```

**You should see:**
```
aws-cli/2.13.25 Python/3.11.6 ...
```

**If not:** Install AWS CLI:

**macOS:**
```bash
brew install awscli
```

**Windows:** Download from [AWS CLI installer](https://aws.amazon.com/cli/)

**Linux:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

---

### Check Disk Space

```bash
df -h .
```

**You should have at least 20GB free**

---

## Step 2: Configure AWS

### Set Up AWS Credentials

```bash
aws configure
```

**You'll be asked for:**

1. **AWS Access Key ID**: Get from AWS Console → IAM → Users → Security Credentials
2. **AWS Secret Access Key**: Shown when you create the access key
3. **Default region**: Type `ap-south-1` (or your preferred region)
4. **Default output format**: Type `json`

**Example:**
```
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: ap-south-1
Default output format [None]: json
```

---

### Verify AWS Connection

```bash
aws sts get-caller-identity
```

**You should see your AWS account info:**
```json
{
    "UserId": "AIDACKCEVSQ6C2EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

✅ **Success!** You're connected to AWS.

---

## Step 3: Set Up Environment

### Navigate to Deployment Folder

```bash
cd ecs-deployment
```

---

### Load Environment Variables

```bash
source 00_env.sh
```

**You should see:**
```
Environment variables loaded successfully
```

---

### Check Important Variables

```bash
echo "AWS Region: $AWS_REGION"
echo "Account ID: $ACCOUNT_ID"
echo "S3 Bucket: $S3_BUCKET"
echo "RDS Host: $RDS_HOST"
```

**Make sure these show your actual values, not empty!**

---

## Step 4: Build Docker Images

**⏱️ This takes 20-30 minutes. Be patient!**

### Go to Project Root

```bash
cd ..
```

---

### Build All Images (Automated)

```bash
cd ecs-deployment
./rebuild_for_amd64.sh
```

**This builds all 7 images for you!**

**You'll see lots of output like:**
```
[+] Building 245.3s (18/18) FINISHED
 => [internal] load build definition
 => [internal] load .dockerignore
 => [1/14] FROM docker.io/library/python:3.9-slim
 ...
 => => naming to docker.io/churn-pipeline/airflow:2.8.1-amazon
```

---

### Verify Images Built

```bash
docker images | grep -E "churn-pipeline|kafka"
```

**You should see 7 images:**
```
churn-pipeline/airflow     2.8.1-amazon   ...   2.1GB
churn-pipeline/mlflow      latest         ...   1.2GB
churn-pipeline/data        latest         ...   1.8GB
churn-pipeline/model       latest         ...   2.5GB
kafka/churn-pipeline-producer    latest   ...   800MB
kafka/churn-pipeline-inference   latest   ...   1.5GB
kafka/churn-pipeline-analytics   latest   ...   800MB
```

✅ **All images built successfully!**

---

## Step 5: Push to AWS

**⏱️ This takes 30-40 minutes (uploading ~10GB)**

### Create ECR Repositories

```bash
cd ecs-deployment
./10_bootstrap.sh
```

**You should see:**
```
Creating ECR repositories...
Created: churn-pipeline/airflow
Created: churn-pipeline/mlflow
Created: churn-pipeline/data
Created: churn-pipeline/model
Created: churn-pipeline/kafka-producer
Created: churn-pipeline/kafka-inference
Created: churn-pipeline/kafka-analytics
✅ All ECR repositories created successfully
```

---

### Login to ECR

```bash
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY}
```

**You should see:**
```
Login Succeeded
```

---

### Push All Images

**This takes a while! Go grab a coffee ☕**

```bash
# Airflow
docker tag churn-pipeline/airflow:2.8.1-amazon ${ECR_REGISTRY}/churn-pipeline/airflow:2.8.1-amazon
docker push ${ECR_REGISTRY}/churn-pipeline/airflow:2.8.1-amazon

# MLflow
docker tag churn-pipeline/mlflow:latest ${ECR_REGISTRY}/churn-pipeline/mlflow:latest
docker push ${ECR_REGISTRY}/churn-pipeline/mlflow:latest

# Data Pipeline
docker tag churn-pipeline/data:latest ${ECR_REGISTRY}/churn-pipeline/data:latest
docker push ${ECR_REGISTRY}/churn-pipeline/data:latest

# Training Pipeline
docker tag churn-pipeline/model:latest ${ECR_REGISTRY}/churn-pipeline/model:latest
docker push ${ECR_REGISTRY}/churn-pipeline/model:latest

# Kafka Services
docker tag kafka/churn-pipeline-producer:latest ${ECR_REGISTRY}/churn-pipeline/kafka-producer:latest
docker push ${ECR_REGISTRY}/churn-pipeline/kafka-producer:latest

docker tag kafka/churn-pipeline-inference:latest ${ECR_REGISTRY}/churn-pipeline/kafka-inference:latest
docker push ${ECR_REGISTRY}/churn-pipeline/kafka-inference:latest

docker tag kafka/churn-pipeline-analytics:latest ${ECR_REGISTRY}/churn-pipeline/kafka-analytics:latest
docker push ${ECR_REGISTRY}/churn-pipeline/kafka-analytics:latest
```

**For each image, you'll see:**
```
The push refers to repository [...]
5f70bf18a086: Pushed
a3b5c80a4eba: Pushed
...
latest: digest: sha256:abc123... size: 4567
```

✅ **All images pushed to AWS!**

---

## Step 6: Create Infrastructure

### Create Security Groups

```bash
./20_networking.sh
```

**You should see:**
```
Creating Networking Resources
✅ VPC verified
✅ Created ALB security group
✅ Created ECS security group
✅ Created RDS security group
✅ Networking setup complete
```

---

### Create IAM Roles

```bash
./30_iam.sh
```

**You should see:**
```
Creating IAM Roles
✅ Created task execution role
✅ Created task role
✅ IAM roles created successfully
```

---

### Create ECS Cluster and Load Balancer

```bash
./40_cluster_alb.sh
```

**You should see:**
```
Creating ECS Cluster and Load Balancer
✅ Created ECS cluster: churn-pipeline-ecs
✅ Created ALB: churn-pipeline-alb
✅ ALB DNS: churn-pipeline-alb-960480895.ap-south-1.elb.amazonaws.com
✅ Created Airflow target group
✅ Created MLflow target group
✅ Infrastructure setup complete

Access URLs:
  Airflow: http://churn-pipeline-alb-960480895.ap-south-1.elb.amazonaws.com
  MLflow:  http://churn-pipeline-alb-960480895.ap-south-1.elb.amazonaws.com:5001
```

**🎉 SAVE THESE URLs! You'll need them to access your services.**

---

## Step 7: Deploy Services

### Register Task Definitions

```bash
./50_register_tasks.sh
```

**You should see:**
```
Registering Task Definitions
✅ Registered: churn-pipeline-airflow-web:1
✅ Registered: churn-pipeline-airflow-scheduler:1
✅ Registered: churn-pipeline-airflow-worker:1
✅ Registered: churn-pipeline-mlflow:1
✅ Registered: churn-pipeline-data:1
✅ Registered: churn-pipeline-train:1
✅ Registered: churn-pipeline-kafka-producer:1
✅ Registered: churn-pipeline-kafka-inference:1
✅ Registered: churn-pipeline-kafka-analytics:1
✅ All task definitions registered successfully
```

---

### Create Services

**⏱️ This starts your services. They'll take 5-10 minutes to become healthy.**

```bash
./60_services.sh
```

**You should see:**
```
Creating ECS Services
✅ Created: airflow-webserver-v3
✅ Created: airflow-scheduler-v2
✅ Created: airflow-worker-v2
✅ Created: mlflow-tracking
✅ Created: kafka-producer
✅ Created: kafka-inference
✅ Created: kafka-analytics
✅ All services created successfully

⏳ Services are starting... This may take 5-10 minutes.
```

---

### Watch Services Start (Optional)

```bash
watch -n 5 'aws ecs describe-services \
  --cluster churn-pipeline-ecs \
  --services airflow-webserver-v3 mlflow-tracking \
  --region ap-south-1 \
  --query "services[*].[serviceName,status,runningCount,desiredCount]" \
  --output table'
```

**Press Ctrl+C to stop watching**

**Wait until you see:**
```
-------------------------------------------------------
|              DescribeServices                       |
+----------------------+--------+----------+----------+
|  airflow-webserver-v3|  ACTIVE|    1    |    1    |
|  mlflow-tracking     |  ACTIVE|    1    |    1    |
+----------------------+--------+----------+----------+
```

✅ **Services are running!**

---

## Step 8: Initialize Airflow

### Set Up Airflow Database

```bash
./70_airflow_init.sh
```

**You should see:**
```
Initializing Airflow
✅ Airflow init task started
⏳ Task status: PROVISIONING
⏳ Task status: PENDING
⏳ Task status: RUNNING
✅ Task status: STOPPED (Exit code: 0)
✅ Admin user created
✅ Airflow initialization complete

Credentials:
  Username: admin
  Password: admin
```

---

### Configure Airflow Variables

```bash
./80_airflow_vars.sh
```

**You should see:**
```
Setting Airflow Variables
✅ Set: S3_BUCKET
✅ Set: MLFLOW_TRACKING_URI
✅ Set: RDS_HOST
✅ Set: AWS_REGION
✅ All Airflow variables set successfully
```

---

## Step 9: Verify Everything Works

### Get Your Access URLs

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 DEPLOYMENT COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Access your services:"
echo ""
echo "Airflow UI: http://${ALB_DNS}"
echo "  Username: admin"
echo "  Password: admin"
echo ""
echo "MLflow UI:  http://${ALB_DNS}:5001"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

---

### Open Airflow in Browser

1. Copy the Airflow URL
2. Paste into your browser
3. Login with:
   - Username: `admin`
   - Password: `admin`

**You should see:**
- ✅ Airflow dashboard
- ✅ Two DAGs: `data_pipeline_dag`, `model_training_dag`

---

### Open MLflow in Browser

1. Copy the MLflow URL
2. Paste into your browser

**You should see:**
- ✅ MLflow dashboard
- ✅ "Churn Analysis" experiment

---

### Check Services Are Healthy

```bash
aws ecs describe-services \
  --cluster churn-pipeline-ecs \
  --services airflow-webserver-v3 mlflow-tracking kafka-inference \
  --region ${AWS_REGION} \
  --query 'services[*].[serviceName,status,runningCount,desiredCount]' \
  --output table
```

**You should see all services with runningCount = desiredCount:**
```
-------------------------------------------------------
|              DescribeServices                       |
+----------------------+--------+----------+----------+
|  airflow-webserver-v3|  ACTIVE|    1    |    1    |
|  mlflow-tracking     |  ACTIVE|    1    |    1    |
|  kafka-inference     |  ACTIVE|    1    |    1    |
+----------------------+--------+----------+----------+
```

✅ **Everything is working!**

---

## 🎯 Running Your First Pipeline

### Run Data Pipeline via Airflow UI

1. Open Airflow UI
2. Find `data_pipeline_dag`
3. Toggle the switch to **ON** (enable it)
4. Click the **Play button** → **Trigger DAG**
5. Watch it run in the **Graph** view

**You should see:**
- ✅ Tasks turning green (success)
- ✅ Data being processed
- ✅ Artifacts saved to S3

---

### Run Training Pipeline

1. Find `model_training_dag`
2. Toggle the switch to **ON**
3. Click **Trigger DAG**
4. Watch it run

**After it completes:**
1. Open MLflow UI
2. Click on "Churn Analysis" experiment
3. You should see your trained model!

🎉 **Congratulations! Your ML system is running in the cloud!**

---

## 📊 Monitoring Your System

### View Logs

**Airflow logs:**
```bash
aws logs tail /ecs/churn-pipeline \
  --follow \
  --filter-pattern "airflow-webserver" \
  --region ${AWS_REGION}
```

**Training pipeline logs:**
```bash
aws logs tail /ecs/churn-pipeline \
  --follow \
  --filter-pattern "train-pipeline" \
  --region ${AWS_REGION}
```

**Kafka inference logs:**
```bash
aws logs tail /ecs/churn-pipeline \
  --follow \
  --filter-pattern "kafka-inference" \
  --region ${AWS_REGION}
```

**Press Ctrl+C to stop viewing logs**

---

### Check Service Status

```bash
aws ecs describe-services \
  --cluster churn-pipeline-ecs \
  --services airflow-webserver-v3 mlflow-tracking \
  --region ${AWS_REGION} \
  --query 'services[*].[serviceName,status,runningCount]' \
  --output table
```

---

### Check Costs (Important!)

```bash
# Go to AWS Console → Billing Dashboard
# Or set up billing alerts
```

**Expected monthly cost:** ~$200-260 if running 24/7

**💡 Tip:** Stop services when not using them to save money!

---

## 🔧 When Things Go Wrong

### Service Won't Start

**Check what went wrong:**

```bash
# Get stopped tasks
STOPPED_TASKS=$(aws ecs list-tasks \
  --cluster churn-pipeline-ecs \
  --desired-status STOPPED \
  --region ${AWS_REGION} \
  --query 'taskArns[0]' \
  --output text)

# See why it stopped
aws ecs describe-tasks \
  --cluster churn-pipeline-ecs \
  --tasks ${STOPPED_TASKS} \
  --region ${AWS_REGION} \
  --query 'tasks[0].stoppedReason'
```

**Common issues:**
- **"Image not found"** → Push images to ECR again
- **"Out of memory"** → Increase memory in task definition
- **"Can't connect to RDS"** → Check security groups

---

### Can't Access Airflow UI

**Checklist:**

1. **Wait 10 minutes** - Services take time to start
2. **Check service is running:**
   ```bash
   aws ecs describe-services \
     --cluster churn-pipeline-ecs \
     --services airflow-webserver-v3 \
     --region ${AWS_REGION}
   ```
3. **Check target health:**
   ```bash
   TG_ARN=$(aws elbv2 describe-target-groups --region ${AWS_REGION} \
     --query "TargetGroups[?TargetGroupName=='churn-pipeline-airflow-tg'].TargetGroupArn" \
     --output text)
   
   aws elbv2 describe-target-health --target-group-arn ${TG_ARN} --region ${AWS_REGION}
   ```
   **Should show:** `"State": "healthy"`

4. **Check URL is correct** - Should be `http://` not `https://`

---

### Training Pipeline Fails

**Check logs:**
```bash
aws logs tail /ecs/churn-pipeline \
  --follow \
  --filter-pattern "train-pipeline" \
  --region ${AWS_REGION}
```

**Common issues:**
- **Out of memory** → Increase `TRAIN_PIPELINE_MEMORY` in `00_env.sh`
- **Can't connect to MLflow** → Check `MLFLOW_TRACKING_URI`
- **Can't access S3** → Check IAM role permissions

---

### Restart a Service

```bash
aws ecs update-service \
  --cluster churn-pipeline-ecs \
  --service kafka-inference \
  --force-new-deployment \
  --region ${AWS_REGION}
```

---

## 🧹 Cleaning Up

**⚠️ IMPORTANT: Run this to avoid charges!**

### Quick Cleanup (Recommended)

```bash
cd ecs-deployment
./99_cleanup_all.sh
```

**This deletes:**
- ✅ All ECS services
- ✅ ECS cluster
- ✅ Load balancer
- ✅ Target groups
- ✅ Security groups
- ✅ ECR repositories
- ✅ CloudWatch logs

**NOT deleted** (delete manually if needed):
- RDS database (~$15-25/month)
- S3 bucket (~$2-3/month)

---

### Delete RDS (Optional)

```bash
aws rds delete-db-instance \
  --db-instance-identifier churn-pipeline-db \
  --skip-final-snapshot \
  --region ${AWS_REGION}
```

---

### Delete S3 Bucket (Optional)

```bash
aws s3 rb s3://your-mlflow-bucket --force --region ${AWS_REGION}
```

---

### Verify Cleanup

```bash
# Check ECS clusters (should be empty)
aws ecs list-clusters --region ${AWS_REGION}

# Check load balancers (should be empty)
aws elbv2 describe-load-balancers --region ${AWS_REGION} \
  --query "LoadBalancers[?contains(LoadBalancerName, 'churn-pipeline')]"
```

**You should see empty results: `[]`**

✅ **Cleanup complete! No more charges.**

---

## 📚 Quick Command Reference

### Most Used Commands

**Check service status:**
```bash
aws ecs describe-services --cluster churn-pipeline-ecs \
  --services airflow-webserver-v3 --region ap-south-1
```

**View logs:**
```bash
aws logs tail /ecs/churn-pipeline --follow --region ap-south-1
```

**Restart service:**
```bash
aws ecs update-service --cluster churn-pipeline-ecs \
  --service kafka-inference --force-new-deployment --region ap-south-1
```

**Stop service (save money):**
```bash
aws ecs update-service --cluster churn-pipeline-ecs \
  --service kafka-producer --desired-count 0 --region ap-south-1
```

**Start service again:**
```bash
aws ecs update-service --cluster churn-pipeline-ecs \
  --service kafka-producer --desired-count 1 --region ap-south-1
```

---

## 🎓 What You Learned

Congratulations! 🎉 You just:

- ✅ Built Docker images for production (AMD64)
- ✅ Pushed images to AWS ECR
- ✅ Created AWS infrastructure (VPC, IAM, ECS, ALB)
- ✅ Deployed 7 services to AWS ECS
- ✅ Ran ML pipelines in the cloud
- ✅ Monitored services with CloudWatch
- ✅ Managed cloud costs
- ✅ Cleaned up resources

**You're now a cloud deployment pro!** 🚀

---

## 💡 Tips & Tricks

### Save Money

1. **Stop services when not using:**
   ```bash
   aws ecs update-service --cluster churn-pipeline-ecs \
     --service kafka-producer --desired-count 0 --region ap-south-1
   ```

2. **Stop RDS when not using:**
   ```bash
   aws rds stop-db-instance --db-instance-identifier churn-pipeline-db --region ap-south-1
   ```

3. **Set up billing alerts** in AWS Console

### Make It Faster

1. **Use `./rebuild_for_amd64.sh`** instead of building images one by one
2. **Build on a fast internet connection** for pushing to ECR
3. **Use `watch` command** to monitor services without refreshing

### Troubleshoot Like a Pro

1. **Always check logs first:**
   ```bash
   aws logs tail /ecs/churn-pipeline --follow --region ap-south-1
   ```

2. **Check service events:**
   ```bash
   aws ecs describe-services --cluster churn-pipeline-ecs \
     --services airflow-webserver-v3 --region ap-south-1 \
     --query 'services[0].events[0:5]'
   ```

3. **Google the error message** - someone else has probably solved it!

---

## ❓ FAQ

**Q: How long does deployment take?**  
A: First time: 2-3 hours. After that: 30-45 minutes.

**Q: Can I stop services to save money?**  
A: Yes! Use `--desired-count 0` to stop services.

**Q: What if I run out of disk space?**  
A: Delete old Docker images: `docker system prune -a`

**Q: Can I deploy to a different region?**  
A: Yes! Change `AWS_REGION` in `00_env.sh`.

**Q: How do I update a service?**  
A: Rebuild image, push to ECR, run `./50_register_tasks.sh`, then force new deployment.

**Q: Is this production-ready?**  
A: Yes! But add monitoring, alerting, and auto-scaling for real production.

---

## 🆘 Need Help?

**If you're stuck:**

1. Check the troubleshooting section above
2. Review the logs
3. Ask your instructor
4. Check AWS documentation
5. Search Stack Overflow

**Remember:** Everyone gets stuck sometimes. Don't give up! 💪

---

**Last Updated**: 2025-01-26  
**Version**: 1.0  
**Maintained By**: Production ML Systems Course Team  
**Questions?** Ask your instructor!

Happy Deploying! 🚀


