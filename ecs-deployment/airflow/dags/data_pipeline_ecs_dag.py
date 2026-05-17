"""
Data Pipeline DAG - Every 10 minutes (ECS Version)
Uses EcsOperator to run churn-pipeline-data task on AWS ECS Fargate
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.amazon.aws.operators.ecs import EcsRunTaskOperator
from airflow.models import Variable

# Get ECS configuration from Airflow Variables
# These are set by 80_airflow_vars.sh during deployment
ECS_CLUSTER = Variable.get("ECS_CLUSTER")
ECS_PRIVATE_SUBNETS = Variable.get("ECS_PRIVATE_SUBNETS", deserialize_json=True)
ECS_SECURITY_GROUPS = Variable.get("ECS_SECURITY_GROUPS", deserialize_json=True)
TASK_DEF_DATA = Variable.get("TASK_DEF_DATA")  # churn-pipeline-data
AWS_REGION = Variable.get("AWS_REGION")

default_args = {
    "owner": "ml_engineering_team",
    "retries": 2,
    "retry_delay": timedelta(minutes=1),
    "start_date": datetime(2025, 10, 12),
    "catchup": False
}

with DAG(
    dag_id="data_pipeline_ecs_hourly",
    default_args=default_args,
    schedule="0 * * * *",  # Every hour at minute 0
    max_active_runs=1,  # Prevent overlap
    dagrun_timeout=timedelta(minutes=50),
    description="Run data preprocessing pipeline hourly on ECS Fargate",
    tags=["ml_pipeline", "data_preprocessing", "ecs", "fargate"]
) as dag:

    run_data_pipeline = EcsRunTaskOperator(
        task_id="run_data_pipeline_ecs",
        cluster=ECS_CLUSTER,
        task_definition=TASK_DEF_DATA,
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
                    "name": "data",
                    "command": [
                        "python3",
                        "-m",
                        "pipelines.data_pipeline",
                        "--engine",
                        "pandas"
                    ]
                }
            ]
        },
        awslogs_group="/ecs/churn-pipeline",
        awslogs_stream_prefix="data-pipeline/data",
    )

# Task explanation:
# - Runs on ECS Fargate in private subnets
# - Uses churn-pipeline-data task definition
# - Executes data_pipeline.py with pandas engine
# - Logs to CloudWatch: /ecs/churn-pipeline/data-pipeline/*
# - Auto-terminates after completion
# - Inherits all environment variables from task definition

