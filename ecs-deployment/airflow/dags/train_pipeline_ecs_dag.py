"""
Model Training Pipeline DAG - Hourly (ECS Version)
Uses EcsOperator to run churn-pipeline-train task on AWS ECS Fargate
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.amazon.aws.operators.ecs import EcsRunTaskOperator
from airflow.models import Variable

# Get ECS configuration from Airflow Variables
ECS_CLUSTER = Variable.get("ECS_CLUSTER")
ECS_PRIVATE_SUBNETS = Variable.get("ECS_PRIVATE_SUBNETS", deserialize_json=True)
ECS_SECURITY_GROUPS = Variable.get("ECS_SECURITY_GROUPS", deserialize_json=True)
TASK_DEF_TRAIN = Variable.get("TASK_DEF_TRAIN")  # churn-pipeline-train
AWS_REGION = Variable.get("AWS_REGION")

default_args = {
    "owner": "ml_engineering_team",
    "retries": 2,
    "retry_delay": timedelta(minutes=2),
    "start_date": datetime(2025, 10, 12),
    "catchup": False
}

with DAG(
    dag_id="train_pipeline_ecs_daily",
    default_args=default_args,
    schedule="0 0 * * *",  # Every day at midnight
    max_active_runs=1,  # Prevent overlap
    dagrun_timeout=timedelta(hours=2),
    description="Run model training pipeline every 24h on ECS Fargate",
    tags=["ml_pipeline", "model_training", "ecs", "fargate"]
) as dag:

    run_train_pipeline = EcsRunTaskOperator(
        task_id="run_train_pipeline_ecs",
        cluster=ECS_CLUSTER,
        task_definition=TASK_DEF_TRAIN,
        launch_type="FARGATE",
        region=AWS_REGION,
        network_configuration={
            "awsvpcConfiguration": {
                "subnets": ECS_PRIVATE_SUBNETS,
                "securityGroups": ECS_SECURITY_GROUPS,
                "assignPublicIp": "ENABLED"
            }
        },
        overrides={
            "containerOverrides": [
                {
                    "name": "train",
                    "command": [
                        "python",
                        "-m",
                        "pipelines.training_pipeline",
                        "--engine",
                        "sklearn",
                        "--model-type",
                        "random_forest"
                    ],
                    "environment": [
                        {"name": "SKIP_MLFLOW", "value": "false"},
                        {"name": "MLFLOW_TRACKING_URI", "value": "http://43.205.129.224:5001"},
                        {"name": "USE_S3", "value": "true"},
                        {"name": "SKIP_S3_UPLOAD", "value": "false"}
                    ]
                }
            ]
        },
        awslogs_group="/ecs/churn-pipeline",
        awslogs_stream_prefix="train-pipeline/train",
    )

# Task explanation:
# - Runs on ECS Fargate in private subnets
# - Uses churn-pipeline-train task definition
# - Executes training_pipeline.py with hyperparameters
# - Logs to CloudWatch: /ecs/churn-pipeline/train-pipeline/*
# - MLflow tracking enabled via environment variables
# - Model artifacts saved to S3

