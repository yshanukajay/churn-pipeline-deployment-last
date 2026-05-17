#!/bin/bash
################################################################################
# SCRIPT: 30_iam.sh
# PURPOSE: Create IAM roles and policies for ECS tasks
#
# WHAT THIS SCRIPT DOES:
# ----------------------
# 1. Creates Task Execution Role (for ECS to pull images and write logs)
# 2. Creates Task Role (for containers to access AWS services like S3, RDS)
# 3. Attaches necessary policies for S3, RDS, CloudWatch, Secrets Manager
#
# WHY WE NEED THIS:
# ----------------
# - ECS needs permission to pull Docker images from ECR
# - ECS needs permission to write container logs to CloudWatch
# - Containers need permission to access S3 (for artifacts), RDS (for database)
# - IAM roles provide secure, temporary credentials (no hardcoded keys!)
#
# PREREQUISITES:
# -------------
# - 00_env.sh configured with PROJECT name and AWS_REGION
# - AWS CLI configured with IAM permissions
# - Understanding of IAM roles vs policies
#
# STUDENT NOTE:
# ------------
# IAM Roles = "Job descriptions" for AWS services
# Think of it like giving your containers a security badge that grants
# specific permissions. No passwords needed - AWS handles it automatically!
#
# Two types of roles:
# 1. Task Execution Role: What ECS needs (pull images, write logs)
# 2. Task Role: What YOUR CODE needs (access S3, RDS, etc.)
################################################################################

set -euo pipefail  # Exit on error, undefined variables, or pipe failures

# Disable AWS CLI pager for non-interactive execution
export AWS_PAGER=""

# Unset AWS_PROFILE to use environment variables for authentication
unset AWS_PROFILE 2>/dev/null || true

# Load environment variables
source "$(dirname "$0")/00_env.sh"
[[ -f "$(dirname "$0")/.env.out" ]] && source "$(dirname "$0")/.env.out"

echo "🔐 Step 3: IAM Roles Configuration"
echo "==================================="
echo ""
echo "📚 WHAT WE'RE DOING:"
echo "   1. Creating Task Execution Role (for ECS platform)"
echo "   2. Creating Task Role (for your application code)"
echo "   3. Attaching policies for S3, RDS, CloudWatch access"
echo ""

# ============================================
# STEP 1: Create Task Execution Role
# ============================================
# WHAT: Role for ECS Fargate platform to manage containers
# WHY: ECS needs permission to pull images from ECR and write logs
# HOW: Create role with trust policy, attach AWS managed policies
echo "Creating Task Execution Role..."
echo ""
echo "💡 STUDENT NOTE:"
echo "   Task Execution Role = Permissions for ECS (not your code)"
echo "   Allows ECS to: pull Docker images, write CloudWatch logs, read secrets"
echo ""

EXEC_ROLE_NAME="${PROJECT}-task-execution-role"

# Check if role exists
if aws iam get-role --role-name "$EXEC_ROLE_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${GREEN}✅ Task execution role exists: $EXEC_ROLE_NAME${NC}"
    EXEC_ROLE_ARN=$(aws iam get-role --role-name "$EXEC_ROLE_NAME" --region "$AWS_REGION" --query 'Role.Arn' --output text)
else
    # Create trust policy
    cat > /tmp/task-execution-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    # Create role
    EXEC_ROLE_ARN=$(aws iam create-role \
        --role-name "$EXEC_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/task-execution-trust.json \
        --region "$AWS_REGION" \
        --query 'Role.Arn' \
        --output text)

    # Attach AWS managed policy
    aws iam attach-role-policy \
        --role-name "$EXEC_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
        --region "$AWS_REGION"

    # Add Secrets Manager access
    cat > /tmp/exec-role-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${RDS_PASSWORD_SECRET_ARN}",
        "${FERNET_KEY_SECRET_ARN}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name "$EXEC_ROLE_NAME" \
        --policy-name "ExecutionRolePolicy" \
        --policy-document file:///tmp/exec-role-policy.json \
        --region "$AWS_REGION"

    echo -e "${GREEN}✅ Created task execution role: $EXEC_ROLE_ARN${NC}"
fi
echo ""

# ============================================
# Step 2: Create Task Role
# ============================================
echo "Creating Task Role..."

TASK_ROLE_NAME="${PROJECT}-task-role"

# Check if role exists
if aws iam get-role --role-name "$TASK_ROLE_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${GREEN}✅ Task role exists: $TASK_ROLE_NAME${NC}"
    TASK_ROLE_ARN=$(aws iam get-role --role-name "$TASK_ROLE_NAME" --region "$AWS_REGION" --query 'Role.Arn' --output text)
else
    # Create role
    TASK_ROLE_ARN=$(aws iam create-role \
        --role-name "$TASK_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/task-execution-trust.json \
        --region "$AWS_REGION" \
        --query 'Role.Arn' \
        --output text)

    # Add comprehensive task policy
    cat > /tmp/task-role-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}",
        "arn:aws:s3:::${S3_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${RDS_PASSWORD_SECRET_ARN}",
        "${FERNET_KEY_SECRET_ARN}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:GetLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:RunTask",
        "ecs:DescribeTasks",
        "ecs:StopTask"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": [
        "${EXEC_ROLE_ARN}",
        "arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT}-task-role"
      ]
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name "$TASK_ROLE_NAME" \
        --policy-name "TaskRolePolicy" \
        --policy-document file:///tmp/task-role-policy.json \
        --region "$AWS_REGION"

    echo -e "${GREEN}✅ Created task role: $TASK_ROLE_ARN${NC}"
fi
echo ""

# ============================================
# Step 3: Update .env.out
# ============================================
echo "💾 Saving outputs..."

cat >> "$(dirname "$0")/.env.out" << EOF

# IAM Roles (from 30_iam.sh)
export EXEC_ROLE_ARN="${EXEC_ROLE_ARN}"
export TASK_ROLE_ARN="${TASK_ROLE_ARN}"
export EXEC_ROLE_NAME="${EXEC_ROLE_NAME}"
export TASK_ROLE_NAME="${TASK_ROLE_NAME}"
EOF

echo -e "${GREEN}✅ Saved to .env.out${NC}"
echo ""

# Cleanup temp files
rm -f /tmp/task-execution-trust.json /tmp/exec-role-policy.json /tmp/task-role-policy.json

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "🎉 IAM Setup Complete!"
echo "=========================================="
echo ""
echo "Task Execution Role:"
echo "  ✅ Name: $EXEC_ROLE_NAME"
echo "  ✅ ARN:  $EXEC_ROLE_ARN"
echo ""
echo "Task Role:"
echo "  ✅ Name: $TASK_ROLE_NAME"
echo "  ✅ ARN:  $TASK_ROLE_ARN"
echo ""
echo "Permissions:"
echo "  ✅ ECR pull"
echo "  ✅ CloudWatch Logs"
echo "  ✅ Secrets Manager"
echo "  ✅ S3 access to ${S3_BUCKET}"
echo "  ✅ ECS RunTask (for Airflow)"
echo ""
echo -e "${YELLOW}📝 Next step: ./40_cluster_alb.sh${NC}"
