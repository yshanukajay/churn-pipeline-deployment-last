# Apache Airflow Orchestration - A Practical Guide

**Learn how to schedule and automate your ML pipelines using Apache Airflow**

Hey there! 👋 Welcome to the Airflow orchestration guide. By the end of this guide, you'll understand how to automate your churn prediction pipeline so that data preprocessing runs every hour and model training runs every day — completely hands-off. Don't worry if you've never used Airflow before - we'll start from the basics and build up gradually.

---

## What You'll Learn

By the end of this guide, you'll be able to:
- Explain what Airflow is and why we use it
- Understand the Airflow architecture (Webserver, Scheduler, Worker, Celery)
- Set up Airflow using Docker Compose
- Read and understand DAGs (Directed Acyclic Graphs)
- Trigger and monitor pipeline runs from the Airflow UI
- Understand how DAGs use DockerOperator to run your ML containers
- Troubleshoot common Airflow issues

**Time to Complete**: 2-3 hours (including hands-on practice)

---

## Prerequisites

Before starting, make sure you have:
- [x] Docker and Docker Compose installed
- [x] Basic understanding of Python
- [x] The project code cloned on your machine
- [x] MLflow and the churn pipeline Docker images built

Don't worry if you're not an expert — we'll guide you through everything!

---

## Table of Contents

1. [Why Do We Need Airflow?](#why-do-we-need-airflow)
2. [Understanding DAGs](#understanding-dags)
3. [The Complete System Overview](#the-complete-system-overview)
4. [Airflow Architecture Deep Dive](#airflow-architecture-deep-dive)
5. [Setting Up Airflow](#setting-up-airflow)
6. [The Data Pipeline DAG](#the-data-pipeline-dag)
7. [The Model Training DAG](#the-model-training-dag)
8. [Using the Airflow UI](#using-the-airflow-ui)
9. [Monitoring with Flower](#monitoring-with-flower)
10. [Running Everything Together](#running-everything-together)
11. [Troubleshooting Guide](#troubleshooting-guide)

---

## Why Do We Need Airflow?

Let's start with a simple question: **Why can't we just use a cron job to schedule our pipelines?**

Imagine you have two scripts:
1. `data_pipeline.py` — runs every hour to process customer data
2. `model_training.py` — runs every day to retrain the churn model

### The Cron Approach (Simple but Fragile)

```
# crontab
0 * * * *  python data_pipeline.py
0 0 * * *  python model_training.py
```

**Problems with this approach:**
1. **No visibility**: Did the job run? Did it fail? You have to check logs manually
2. **No retries**: If it fails at 3am, it just doesn't run until tomorrow
3. **No dependencies**: What if data pipeline is still running when training starts?
4. **Hard to debug**: Stack traces buried in log files
5. **No history**: You can't easily see what ran last Tuesday and what it produced

### The Airflow Approach (Orchestrated)

```
Airflow Scheduler → Triggers DAG → DockerOperator → Runs Container → Logs → UI
```

**Benefits of this approach:**
1. **Full visibility**: See every run, success/failure, duration, logs — all in a web UI
2. **Automatic retries**: Failed run? Airflow retries 2 times with configurable delays
3. **Dependency management**: Training DAG can only run after data DAG succeeds
4. **History & lineage**: See exactly what ran, when, and what it produced in S3/MLflow
5. **Alerting**: Configure email/Slack alerts on failure

Think of Airflow like an **air traffic controller**:
- DAGs are flight plans (what to run and when)
- The Scheduler is the controller watching the clock
- Workers are the planes actually doing the work
- The UI is the radar screen showing everything in real time

---

## Understanding DAGs

A **DAG** (Directed Acyclic Graph) is just a Python file that describes:
- **What** tasks to run
- **When** to run them (schedule)
- **In what order** tasks depend on each other

### A Simple DAG Example

```python
with DAG(
    dag_id="my_pipeline",           # Unique name
    schedule="0 * * * *",           # Every hour (cron syntax)
    start_date=datetime(2025, 1, 1),
    catchup=False                   # Don't backfill old runs
) as dag:

    task_a = DockerOperator(...)    # Step 1: Preprocess data
    task_b = DockerOperator(...)    # Step 2: Train model

    task_a >> task_b                # task_b runs AFTER task_a
```

### Cron Schedule Syntax

Airflow uses standard cron syntax:

```
┌───── minute (0-59)
│ ┌──── hour (0-23)
│ │ ┌─── day of month (1-31)
│ │ │ ┌── month (1-12)
│ │ │ │ ┌─ day of week (0-6, Sun=0)
│ │ │ │ │
0 * * * *   → Every hour at minute 0
0 0 * * *   → Every day at midnight
0 9 * * 1   → Every Monday at 9am
*/15 * * * * → Every 15 minutes
```

**In our project:**
- Data pipeline: `0 * * * *` → every hour
- Training pipeline: `0 0 * * *` → every day at midnight

---

## The Complete System Overview

Here's how Airflow fits into the bigger picture:

```
┌───────────────────────────────────────────────────────────┐
│  AIRFLOW SCHEDULER                                         │
│  • Watches the clock                                       │
│  • Triggers DAGs on schedule                              │
│  • Sends tasks to Celery queue                            │
└──────────────────────┬────────────────────────────────────┘
                       │
                       ↓ Puts tasks into Redis queue
┌───────────────────────────────────────────────────────────┐
│  CELERY WORKER                                             │
│  • Picks up tasks from queue                              │
│  • Runs DockerOperator                                    │
│  • Launches ML pipeline containers                        │
└──────────────────────┬────────────────────────────────────┘
                       │
          ┌────────────┴────────────┐
          ↓                         ↓
┌──────────────────┐   ┌──────────────────────────┐
│  data container  │   │  model container          │
│  data_pipeline   │   │  training_pipeline.py     │
│  (hourly)        │   │  (daily)                  │
└────────┬─────────┘   └──────────┬───────────────┘
         │                         │
         ↓                         ↓
┌──────────────────────────────────────────────────┐
│  S3 + MLflow                                      │
│  • Preprocessed data saved with timestamp        │
│  • Trained model saved with timestamp            │
│  • Metrics, params, artifacts tracked            │
└──────────────────────────────────────────────────┘
         │
         ↓ Model available for Kafka consumer
┌──────────────────────────────────────────────────┐
│  Kafka Streaming Pipeline                         │
│  • Consumer downloads latest model from S3       │
│  • Makes real-time predictions                   │
└──────────────────────────────────────────────────┘
```

### How the Two Pipelines Relate

**Data pipeline runs every hour:**
- Reads raw CSV from S3 (or local)
- Cleans and encodes features
- Splits into train/test sets
- Saves preprocessed data to `s3://your-bucket/artifacts/data/<TIMESTAMP>/`
- Logs run to MLflow

**Model training runs every 24 hours:**
- Picks up the latest preprocessed data from S3
- Trains a new churn model
- Saves model to `s3://your-bucket/artifacts/train/<TIMESTAMP>/`
- Logs metrics (accuracy, AUC) to MLflow
- The Kafka consumer then uses this latest model for predictions!

---

## Airflow Architecture Deep Dive

Our setup uses **CeleryExecutor** — the production-grade way to run Airflow. Let's understand each component.

### The Five Components

#### 1. **Airflow Webserver** (Your Control Panel)
- Provides the web UI at `http://localhost:8080`
- Shows DAG runs, task logs, schedules
- Does NOT run tasks itself — just shows status
- Think of it as the dashboard of a car (not the engine)

#### 2. **Airflow Scheduler** (The Brain)
- Reads all DAG files and watches the clock
- When a schedule triggers, it creates a "DAG run"
- Sends task instances to the Celery queue (via Redis)
- Monitors task state and updates the database
- Think of it as the engine management system

#### 3. **Celery Worker** (The Muscle)
- Listens to the Redis task queue
- Actually executes tasks (runs DockerOperator)
- Can have multiple workers for parallel execution
- Reports status back to PostgreSQL
- Think of it as the engine itself

#### 4. **Redis** (The Message Queue)
- Holds the task queue between Scheduler and Worker
- Fast, in-memory store
- When Scheduler says "run this task", it goes into Redis
- Worker picks it up and executes

#### 5. **PostgreSQL** (The Memory)
- Stores all Airflow metadata:
  - DAG definitions
  - DAG run history
  - Task states (success/failed/running)
  - Logs pointers
- This is how Airflow remembers what ran last time

### How They Work Together

```
                      ┌───────────────────────┐
                      │  PostgreSQL            │
                      │  (metadata & history)  │
                      └──────────┬────────────┘
                                 │ read/write
                    ┌────────────┼────────────┐
                    ↓            ↓             ↓
             ┌──────────┐  ┌──────────┐  ┌─────────┐
             │Webserver │  │Scheduler │  │ Worker  │
             │(UI only) │  │(triggers)│  │(runs it)│
             └──────────┘  └────┬─────┘  └────┬────┘
                                │              │
                                ↓ push         ↑ pop
                         ┌──────────────┐
                         │   Redis      │
                         │ (task queue) │
                         └──────────────┘
```

### Flower (Bonus Monitoring)
- Web UI at `http://localhost:5555`
- Shows Celery worker status in real-time
- How many tasks are active, reserved, completed
- Think of it as a task manager for your workers

---

## Setting Up Airflow

Now let's get our hands dirty! Airflow runs via Docker Compose in our project.

### Understanding the Docker Compose Setup

Our `docker-compose.airflow.yml` has **6 services**:

| Service | Container Name | Purpose | Port |
|---------|---------------|---------|------|
| `airflow-postgres` | `airflow-postgres` | Metadata DB | internal |
| `airflow-redis` | `airflow-redis` | Task queue | internal |
| `airflow-webserver` | `airflow-webserver` | Web UI | 8080 |
| `airflow-scheduler` | `airflow-scheduler` | DAG scheduler | — |
| `airflow-worker` | `airflow-worker` | Task executor | — |
| `airflow-init` | `airflow-init` | One-time setup | — |
| `airflow-flower` | `airflow-flower` | Worker monitor | 5555 |

### Important Configuration Details

**The CeleryExecutor setup:**

```yaml
AIRFLOW__CORE__EXECUTOR: CeleryExecutor
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@airflow-postgres:5432/airflow
AIRFLOW__CELERY__BROKER_URL: redis://airflow-redis:6379/0
AIRFLOW__CELERY__RESULT_BACKEND: db+postgresql://airflow:airflow@airflow-postgres:5432/airflow
```

This wires all the components together:
- Executor = Celery (use workers, not local processes)
- DB = our local Postgres (NOT the RDS that holds predictions)
- Broker = Redis (task queue)
- Result backend = Postgres (where task results are stored)

**Docker socket mount (crucial for DockerOperator):**

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

This gives Airflow workers access to your Docker daemon so they can launch ML containers. Without this, DockerOperator won't work!

**DAGs volume mount:**

```yaml
volumes:
  - ./airflow/dags:/opt/airflow/dags
```

Your DAG files are mounted into the container. Any edits to files in `airflow/dags/` are picked up automatically by Airflow (within ~30 seconds).

### First-Time Setup

**Step 1**: Make sure the Docker network exists
```bash
docker network create churn-pipeline-network
```

**Step 2**: Build the Airflow image (uses `docker/Dockerfile.airflow`)
```bash
docker build -f docker/Dockerfile.airflow -t churn-pipeline/airflow:2.8.1-amazon .
```

**Step 3**: Initialize the database (run once)
```bash
docker-compose -f docker-compose.airflow.yml run --rm airflow-init
```

You should see:
```
✅ Airflow init completed
```

This creates:
- All Airflow database tables
- Admin user (username: `admin`, password: `admin`)

**Step 4**: Start all Airflow services
```bash
docker-compose -f docker-compose.airflow.yml up -d
```

**Step 5**: Verify all containers are running
```bash
docker-compose -f docker-compose.airflow.yml ps
```

Should show:
```
NAME                   STATUS          PORTS
airflow-flower         Up              0.0.0.0:5555->5555/tcp
airflow-postgres       Up (healthy)    5432/tcp
airflow-redis          Up (healthy)    6379/tcp
airflow-scheduler      Up
airflow-webserver      Up              0.0.0.0:8080->8080/tcp
airflow-worker         Up
```

**Step 6**: Open the UI
```bash
open http://localhost:8080
# Login: admin / admin
```

---

## The Data Pipeline DAG

Let's walk through `airflow/dags/data_pipeline_dag.py` step by step.

### Full DAG Walkthrough

```python
from airflow import DAG
from airflow.providers.docker.operators.docker import DockerOperator
```

We import `DockerOperator` — this is the key! Instead of running Python code directly, Airflow will launch a Docker container with your ML pipeline code inside.

### Default Arguments

```python
default_args = {
    "owner": "ml_engineering_team",
    "retries": 2,                              # Retry failed tasks twice
    "retry_delay": timedelta(minutes=1),       # Wait 1 min between retries
    "start_date": datetime(2025, 10, 12),      # When the DAG becomes active
    "catchup": False                           # Don't run missed schedules
}
```

**Why `catchup=False`?**

Without this, if Airflow was down for a week, it would try to run 168 missed hourly runs all at once when it comes back up. With `catchup=False`, it just picks up from the current time.

### DAG Definition

```python
with DAG(
    dag_id="data_pipeline_hourly",     # Unique ID — shown in UI
    default_args=default_args,
    schedule="0 * * * *",              # Every hour at :00
    max_active_runs=1,                 # Never run two data pipelines at once!
    dagrun_timeout=timedelta(minutes=50),  # Kill run if it takes > 50 min
    description="Run data preprocessing pipeline hourly",
    tags=["ml_pipeline", "data_preprocessing", "docker", "s3"]
) as dag:
```

**Why `max_active_runs=1`?**

Imagine two data pipeline runs happening simultaneously — they might write to the same S3 timestamp path and corrupt each other. By limiting to 1 active run, we prevent overlap.

### The DockerOperator Task

```python
run_data_pipeline = DockerOperator(
    task_id="run_data_pipeline",
    image="churn-pipeline/data:latest",   # The Docker image to run
    api_version="auto",
    auto_remove=True,                      # Clean up container after run
    docker_url=DOCKER_URL,                # Connect to Docker daemon
    network_mode="churn-pipeline-network", # Same network as MLflow
    mount_tmp_dir=False,                   # macOS compatibility fix
    environment={
        "AWS_ACCESS_KEY_ID": os.getenv("AWS_ACCESS_KEY_ID", ""),
        "AWS_SECRET_ACCESS_KEY": os.getenv("AWS_SECRET_ACCESS_KEY", ""),
        "S3_BUCKET": os.getenv("S3_BUCKET"),
        "MLFLOW_TRACKING_URI": "http://mlflow-tracking:5001",
        "USE_S3": "true",
        "SKIP_S3_UPLOAD": "false"
    },
    execution_timeout=timedelta(minutes=50),
)
```

**What actually happens when this task runs:**

1. Airflow worker calls Docker daemon via the socket
2. Docker pulls (or finds locally) `churn-pipeline/data:latest`
3. Container starts with all those environment variables injected
4. `data_pipeline.py` runs inside the container
5. Artifacts are uploaded to S3
6. MLflow run is logged
7. Container exits with code 0 (success) or non-zero (failure)
8. Worker reports result back to Scheduler
9. Container is automatically removed (`auto_remove=True`)

**Why pass environment variables like this?**

The container needs AWS credentials to write to S3, and needs the MLflow URI to log runs. These come from your `.env` file via `os.getenv()`. The Airflow containers themselves have these variables, and they pass them through to the ML containers they launch.

### Cross-Platform Docker URL

```python
def get_docker_url():
    system = platform.system()
    if system == "Windows":
        return "npipe:////./pipe/docker_engine"
    else:
        return "unix://var/run/docker.sock"
```

Windows uses named pipes for Docker, while Mac/Linux use Unix sockets. This function handles both automatically so the same DAG works on any machine.

---

## The Model Training DAG

The training DAG (`airflow/dags/model_training_dag.py`) follows the same pattern but with different timing and container.

### Key Differences from Data DAG

| Setting | Data Pipeline | Training Pipeline |
|---------|--------------|-------------------|
| `dag_id` | `data_pipeline_hourly` | `train_pipeline_daily` |
| `schedule` | `0 * * * *` (hourly) | `0 0 * * *` (daily at midnight) |
| `retry_delay` | 1 minute | 2 minutes |
| `dagrun_timeout` | 50 minutes | 2 hours |
| `image` | `churn-pipeline/data:latest` | `churn-pipeline/model:latest` |
| `execution_timeout` | 50 minutes | 2 hours |

**Why longer timeouts for training?**

Training involves:
- Downloading preprocessed data from S3
- Training multiple ML models (Logistic Regression, Random Forest, XGBoost, etc.)
- Cross-validation for hyperparameter tuning
- Uploading model artifacts to S3

This takes much longer than preprocessing!

### The Data → Training Relationship

Notice that the training DAG is completely independent — it runs on its own `0 0 * * *` schedule. It doesn't have an explicit dependency on the data DAG in Airflow (no `task_a >> task_b` between the two DAGs).

Instead, the dependency is **implicit via S3**:
- Data DAG runs hourly and always pushes fresh preprocessed data to S3
- Training DAG runs at midnight, reads the latest data from S3
- By midnight, data from today has been preprocessed and waiting in S3

This is called **"eventual consistency"** — services are loosely coupled through shared storage rather than direct dependencies.

---

## Using the Airflow UI

The web UI at `http://localhost:8080` is your command center. Let's explore it.

### DAGs List View

After logging in, you'll see all your DAGs. For each DAG you can see:
- **Toggle**: Pause/unpause a DAG (paused = won't run on schedule)
- **DAG ID**: The name defined in your Python file
- **Schedule**: When it runs (e.g., "Every hour")
- **Last Run**: Timestamp of the most recent run
- **Recent Tasks**: Color-coded summary of last few runs (green=success, red=failed)

**Key actions from this view:**
- Click the ▶️ button to trigger a manual run immediately
- Click the ⏸️ toggle to pause a DAG without deleting it
- Click the DAG name to go into the detail view

### DAG Detail View

Click on `data_pipeline_hourly` to open it. You'll see:

#### Grid View (Default)
- Each column = one DAG run (ordered by time)
- Each row = one task
- Color shows status: green (success), red (failed), yellow (running), grey (queued)

#### Graph View
- Shows task dependencies as a flowchart
- For our single-task DAGs, just one box
- More useful for complex multi-step pipelines

#### Calendar View
- See which days had successful/failed runs at a glance
- Useful for spotting patterns (does it fail every Monday?)

### Triggering a Manual Run

Want to run the data pipeline right now without waiting for the schedule?

**Method 1: From DAGs List**
1. Find `data_pipeline_hourly`
2. Click the ▶️ (Trigger DAG) button
3. Optionally add configuration JSON
4. Click "Trigger"

**Method 2: From DAG Detail View**
1. Click "Trigger DAG" button in the top right
2. Same as above

**What happens:**
1. A new DAG run appears in Grid View (yellow = queued/running)
2. Scheduler picks it up and sends to Celery queue
3. Worker launches the Docker container
4. Task turns green (success) or red (failure)

### Viewing Task Logs

When something goes wrong (or even when it succeeds), check the logs:

1. Click on a run in Grid View
2. Click on a task square
3. Click "Log" in the popup

You'll see everything the container printed to stdout/stderr — including any errors from `data_pipeline.py` or `training_pipeline.py`.

**Tip**: Always check logs first when debugging!

### Clearing and Re-running a Task

If a task failed and you've fixed the issue, you can re-run just that task:

1. Click on the failed task square (red)
2. Click "Clear" in the popup
3. Confirm

Airflow will re-queue that task and run it again. No need to re-trigger the whole DAG!

---

## Monitoring with Flower

Flower provides a real-time view of your Celery workers at `http://localhost:5555`.

### Starting Flower

It starts automatically with the docker-compose command, but if you need to start it separately:
```bash
docker-compose -f docker-compose.airflow.yml up -d airflow-flower
```

### What You Can See in Flower

#### Workers Tab
- How many workers are active
- Worker hostname and status
- Tasks processed / failed counts
- Worker uptime

#### Tasks Tab
- Currently active tasks (tasks running right now)
- Reserved tasks (queued, waiting for a worker)
- Task history

**Why Flower is useful:**

If a task is stuck in "queued" state in the Airflow UI but never starts running, Flower will show you if:
- The worker is offline → restart the worker
- There are too many active tasks → the worker is busy
- The queue is not being processed → Redis connection issue

---

## Running Everything Together

Let's put it all together and start the complete Airflow stack!

### Step-by-Step Startup

**Step 1**: Make sure the Docker network exists
```bash
docker network create churn-pipeline-network
# Ignore "already exists" error
```

**Step 2**: Make sure MLflow is running (Airflow logs to it)
```bash
docker-compose up -d mlflow-tracking
# Check it's up
docker ps | grep mlflow
```

**Step 3**: Make sure your ML images are built
```bash
docker images | grep churn-pipeline
# Should show churn-pipeline/data:latest and churn-pipeline/model:latest
```

If not built:
```bash
make build  # or check your project's build commands
```

**Step 4**: Initialize Airflow (first time only!)
```bash
docker-compose -f docker-compose.airflow.yml run --rm airflow-init
```

**Step 5**: Start all Airflow services
```bash
docker-compose -f docker-compose.airflow.yml up -d
```

**Step 6**: Verify health
```bash
docker-compose -f docker-compose.airflow.yml ps
```

All should show "Up". `airflow-postgres` and `airflow-redis` should be "(healthy)".

**Step 7**: Open the UIs
```bash
# Airflow UI
open http://localhost:8080   # admin / admin

# Celery Flower (worker monitor)
open http://localhost:5555
```

**Step 8**: Enable your DAGs (they start paused!)

In the Airflow UI:
1. Find `data_pipeline_hourly` → click the toggle to turn it ON (blue)
2. Find `train_pipeline_daily` → click the toggle to turn it ON (blue)

**Step 9**: Trigger a test run manually
1. Click ▶️ next to `data_pipeline_hourly`
2. Watch the run in Grid View
3. Check logs to confirm it uploaded to S3

### What to Watch For

**In Airflow UI (http://localhost:8080):**
- DAG runs appear as columns in Grid View
- Green = success, Red = failed, Yellow = running, Light blue = queued
- Last Run timestamp updates after each run

**In Flower (http://localhost:5555):**
- Active tasks: should show the running DockerOperator
- Task count increases with each run

**In Docker:**
```bash
# Watch Airflow logs
docker logs -f airflow-scheduler
docker logs -f airflow-worker
```

**In MLflow (http://localhost:5001):**
- After a successful data pipeline run, a new experiment entry appears
- After a successful training run, a new model is registered

---

## Troubleshooting Guide

### Common Issues and How to Fix Them

#### Issue 1: DAGs Not Appearing in UI

**Symptoms:**
- You expect to see `data_pipeline_hourly` but it's not in the list

**Solution:**
```bash
# Check if dag files are valid Python
python airflow/dags/data_pipeline_dag.py
# Any import errors? Fix them.

# Check scheduler is parsing DAGs
docker logs airflow-scheduler | grep "data_pipeline"
# Look for parse errors
```

Common causes:
- Syntax error in the DAG file
- Missing Python import
- DAG file not in the mounted volume

#### Issue 2: Task Stuck in "Queued" State

**Symptoms:**
- Task shows as queued (light blue) in UI for more than 2 minutes
- Never transitions to "running"

**Solution:**
```bash
# Check if worker is running
docker ps | grep airflow-worker

# Check worker logs
docker logs airflow-worker | tail -50

# Check Redis connection
docker exec airflow-worker redis-cli -h airflow-redis ping
# Should return: PONG

# Restart worker if needed
docker-compose -f docker-compose.airflow.yml restart airflow-worker
```

#### Issue 3: DockerOperator Fails with "Cannot Connect to Docker"

**Symptoms:**
```
Error: Got a permission error trying to connect to the Docker socket
```

**Solution:**
```bash
# Check Docker socket is mounted
docker inspect airflow-worker | grep docker.sock
# Should show: /var/run/docker.sock:/var/run/docker.sock

# Check socket permissions
ls -la /var/run/docker.sock
# Should show: srw-rw---- (group: docker)

# Add airflow user to docker group (may require rebuild)
# Or on Linux, set the socket permissions:
sudo chmod 666 /var/run/docker.sock
```

#### Issue 4: ML Container Fails (Task Red)

**Symptoms:**
- Task shows as failed (red)
- Logs show an error from `data_pipeline.py` or `training_pipeline.py`

**Solution:**
1. Click on the failed task in Airflow UI
2. Click "Log"
3. Read the actual error — is it:
   - **S3 access denied?** → Check AWS credentials in `.env`
   - **MLflow connection refused?** → Make sure MLflow container is running
   - **Model not found?** → Run data pipeline first, then training pipeline

```bash
# Check if the image exists locally
docker images | grep churn-pipeline/data

# Try running the container manually to see the error
docker run --rm \
  --network churn-pipeline-network \
  -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  -e S3_BUCKET=$S3_BUCKET \
  -e MLFLOW_TRACKING_URI=http://mlflow-tracking:5001 \
  -e USE_S3=true \
  churn-pipeline/data:latest
```

Running it manually shows the raw output without Airflow in the way.

#### Issue 5: Airflow DB Connection Error

**Symptoms:**
```
sqlalchemy.exc.OperationalError: could not connect to server
```

**Solution:**
```bash
# Check postgres is healthy
docker ps | grep airflow-postgres
# Should show: Up (healthy)

# Check postgres logs
docker logs airflow-postgres | tail -20

# If postgres isn't healthy, restart it
docker-compose -f docker-compose.airflow.yml restart airflow-postgres

# Then restart scheduler and webserver
docker-compose -f docker-compose.airflow.yml restart airflow-scheduler airflow-webserver
```

#### Issue 6: "No module named airflow" in Worker

**Symptoms:**
```
ModuleNotFoundError: No module named 'airflow'
```

**Solution:**
```bash
# Check PYTHONPATH in worker
docker exec airflow-worker env | grep PYTHONPATH
# Should be: PYTHONPATH=/opt/app/src:/opt/app/utils

# The PYTHONPATH must NOT shadow the airflow installation
# If it shows /opt/airflow in PYTHONPATH, that's the bug
```

Our `docker-compose.airflow.yml` intentionally sets:
```yaml
PYTHONPATH: "/opt/app/src:/opt/app/utils"
```
This avoids accidentally shadowing the installed Airflow package.

#### Issue 7: Flower Shows No Workers

**Symptoms:**
- Flower UI shows 0 active workers
- Tasks sit in queued forever

**Solution:**
```bash
# Check if worker is connected to Redis
docker logs airflow-worker | grep -i "celery"
# Should show: "celery@airflow-worker ready"

# Check Redis is reachable from worker
docker exec airflow-worker redis-cli -h airflow-redis ping
# Should return: PONG

# Restart flower and worker
docker-compose -f docker-compose.airflow.yml restart airflow-flower airflow-worker
```

### Debugging Tips

**1. Always check logs in this order:**
```bash
# 1. Scheduler (is it triggering runs?)
docker logs airflow-scheduler | tail -50

# 2. Worker (is it running tasks?)
docker logs airflow-worker | tail -50

# 3. The specific task log (what did the container print?)
# → Airflow UI → DAG → Task → Log
```

**2. Test your DAG syntax before deploying:**
```bash
# Validate a DAG file
python -c "
import airflow
from airflow.dags.data_pipeline_dag import *
print('DAG loaded successfully')
"
```

**3. Check if your ML container works independently:**
```bash
docker run --rm --network churn-pipeline-network \
  -e USE_S3=true \
  -e S3_BUCKET=$S3_BUCKET \
  churn-pipeline/data:latest
```

**4. Reset Airflow completely (nuclear option):**
```bash
# Stop everything
docker-compose -f docker-compose.airflow.yml down

# Remove Airflow's postgres volume (⚠️ deletes all run history!)
docker volume rm airflow-postgres-data

# Re-initialize
docker-compose -f docker-compose.airflow.yml run --rm airflow-init

# Start fresh
docker-compose -f docker-compose.airflow.yml up -d
```

---

## Key Takeaways

Congratulations! You've now learned:

✅ **What Airflow is**: A workflow orchestration platform for scheduling and monitoring pipelines  
✅ **Why we use it**: Visibility, retries, monitoring, and dependency management  
✅ **DAGs**: Python files that define what to run, when, and in what order  
✅ **CeleryExecutor**: How Airflow distributes work across workers via Redis  
✅ **DockerOperator**: How Airflow launches your ML containers without coupling code  
✅ **Airflow UI**: How to monitor, trigger, and debug runs  
✅ **Flower**: How to monitor Celery workers in real time  
✅ **Troubleshooting**: How to debug the most common Airflow issues  

### Real-World Skills

You can now:
- Explain Airflow's architecture to a teammate
- Set up a scheduled ML pipeline from scratch
- Monitor pipeline health without looking at log files
- Debug failures using Airflow's built-in tools
- Scale to multiple workers for parallel pipeline execution

### How Airflow and Kafka Work Together

Now you can see the full picture:

```
Airflow (every hour)   → Fresh preprocessed data in S3
Airflow (every day)    → Retrained model in S3
Kafka Consumer         → Downloads latest model from S3 automatically
                       → Makes real-time predictions using fresh model
```

Airflow handles the **batch** side (scheduled retraining), while Kafka handles the **real-time** side (live predictions). Together they form a complete production ML system!

### Next Steps

1. **Experiment**: Add a second task to the data DAG that validates data quality
2. **Dependencies**: Try linking two tasks with `task_a >> task_b`
3. **Alerts**: Configure email alerts on DAG failure (Airflow → Admin → Connections → SMTP)
4. **Scale**: Start a second Airflow worker and watch Flower show both workers
5. **ECS**: Check out the ECS deployment DAGs in `ecs-deployment/airflow/dags/` to see how this runs in production on AWS!

---

## Additional Resources

### Official Documentation
- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [DockerOperator Reference](https://airflow.apache.org/docs/apache-airflow-providers-docker/stable/operators/docker.html)
- [CeleryExecutor Guide](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/executor/celery.html)
- [Cron Expression Reference](https://crontab.guru/)

### Video Tutorials
- Search YouTube for "Apache Airflow Tutorial for Beginners"
- Look for "Airflow CeleryExecutor Docker Setup"

### Practice Ideas
- Add a data validation task before model training
- Create a DAG that sends a Slack notification when a new model is trained
- Schedule a weekly report DAG that queries your RDS predictions table

---

**Last Updated**: October 2025  
**Maintained by**: Production ML Systems Course Team  
**Questions?** Check the troubleshooting section or ask your instructor!

Happy Orchestrating! 🚀
