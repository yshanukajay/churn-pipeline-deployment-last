"""
Data Pipeline DAG - Hourly
Uses DockerOperator to run churn-pipeline/data:latest container
"""

import os
import platform
from airflow import DAG
from datetime import datetime, timedelta
from airflow.providers.docker.operators.docker import DockerOperator

# Cross-platform Docker socket configuration
def get_docker_url():
    """
    Returns the appropriate Docker socket URL based on the platform.
    
    Returns:
        str: Docker socket URL
            - Linux/macOS: unix://var/run/docker.sock
            - Windows: npipe:////./pipe/docker_engine
    """
    system = platform.system()
    if system == "Windows":
        return "npipe:////./pipe/docker_engine"
    else:
        # Linux, macOS, WSL
        return "unix://var/run/docker.sock"

DOCKER_URL = get_docker_url()

default_args = {
    "owner": "ml_engineering_team",
    "retries": 2,
    "retry_delay": timedelta(minutes=1),
    "start_date": datetime(2026, 5, 16),
    "catchup": False
}

with DAG(
    dag_id="data_pipeline_hourly",
    default_args=default_args,
    schedule="0 * * * *",  # Every hour at minute 0
    max_active_runs=1,  # Prevent overlap
    dagrun_timeout=timedelta(minutes=50),
    description="Run data preprocessing pipeline hourly via DockerOperator with unified timestamp",
    tags=["ml_pipeline", "data_preprocessing", "pandas", "docker", "s3", "mlflow"]
) as dag:

    run_data_pipeline = DockerOperator(
        task_id="run_data_pipeline",
        image="churn-pipeline/data:latest",
        api_version="auto",
        auto_remove=True,
        docker_url=DOCKER_URL,  # Cross-platform compatible
        network_mode="churn-pipeline-network",
        mount_tmp_dir=False,  # Disable tmp mount for macOS Docker Desktop compatibility
        environment={
                    "AWS_ACCESS_KEY_ID": os.getenv("AWS_ACCESS_KEY_ID", ""),
                    "AWS_SECRET_ACCESS_KEY": os.getenv("AWS_SECRET_ACCESS_KEY", ""),
                    "AWS_REGION": os.getenv("AWS_DEFAULT_REGION", "us-east-1"),
                    "AWS_DEFAULT_REGION": os.getenv("AWS_DEFAULT_REGION", "us-east-1"),
                    "S3_BUCKET": os.getenv("S3_BUCKET"),
                    "MLFLOW_TRACKING_URI": "http://mlflow-tracking:5001",
                    "CONTAINERIZED": "true",
                    "USE_S3": "true",
                    "SKIP_S3_UPLOAD": "false"
                    },
        # Container uses entrypoint, so no command needed
        execution_timeout=timedelta(minutes=50),
    )

# Task explanation:
# - Runs churn-pipeline/data:latest container via DockerOperator
# - Executes data_pipeline.py with pandas engine
# - Generates NEW unified timestamp (force_new=True)
# - Uploads artifacts to S3: artifacts/data/<TIMESTAMP>/
# - Logs to MLflow with S3 manifest references
# - Environment variables:
#   - USE_S3=true: Force S3 usage
#   - SKIP_S3_UPLOAD=false: Ensure uploads happen
#   - MLFLOW_TRACKING_URI: MLflow server for tracking
# - Artifacts: X_train, X_test, y_train, y_test, encoders, scalers, metadata
# - Schedule: Hourly (0 * * * *) - matches ECS deployment
