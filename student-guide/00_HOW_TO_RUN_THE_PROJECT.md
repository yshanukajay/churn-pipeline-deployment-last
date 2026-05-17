# How to Run the Project — Complete Step-by-Step Guide

**Everything you need to go from a fresh clone to a fully running churn prediction system**

Hey there! 👋 This guide walks you through running the entire project from scratch — setting up your environment, starting all the services, watching data flow through the pipeline, and verifying everything is working. Follow the steps in order and you'll have the full system running in about 30–60 minutes.

---

## What You're Building

By the end of this guide, the following will all be running simultaneously:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    YOUR RUNNING SYSTEM                               │
│                                                                      │
│  MLflow (port 5001)  ← tracks all experiments & models              │
│                                                                      │
│  Airflow (port 8080) ← schedules pipelines automatically            │
│    ├── data_pipeline  → runs every hour   → uploads to S3           │
│    └── train_pipeline → runs every day    → trains & saves model    │
│                                                                      │
│  Kafka (port 8090 UI) ← real-time streaming                         │
│    ├── Producer       → streams customer events                     │
│    ├── Consumer       → downloads model from S3, predicts           │
│    └── Analytics      → stores predictions → PostgreSQL (RDS)       │
└─────────────────────────────────────────────────────────────────────┘
```

**Access URLs once running:**

| Service | URL | Credentials |
|---------|-----|-------------|
| Airflow UI | http://localhost:8080 | admin / admin |
| MLflow UI | http://localhost:5001 | none |
| Kafka UI | http://localhost:8090 | none |
| Flower (Celery monitor) | http://localhost:5555 | none |

---

## Prerequisites Checklist

Before you start, make sure you have all of these:

- [ ] **Docker Desktop** installed and running (at least 8GB RAM allocated)
- [ ] **AWS credentials** configured (`~/.aws/credentials`)
- [ ] **Python 3.10+** installed (for local pipeline runs)
- [ ] **Git** installed (project already cloned)
- [ ] `.env` file configured in the project root (see Step 1)
- [ ] At least **20GB free disk space** (Docker images are large)

**Check Docker RAM:**

Docker Desktop → Settings → Resources → Memory. Set it to at least **8GB**. Airflow + Kafka together need a lot of RAM.

---

## Table of Contents

1. [Configure Your Environment](#step-1-configure-your-environment)
2. [Build Docker Images](#step-2-build-docker-images)
3. [Start MLflow](#step-3-start-mlflow)
4. [Initialize and Start Airflow](#step-4-initialize-and-start-airflow)
5. [Run the ML Pipelines](#step-5-run-the-ml-pipelines)
6. [Start Kafka Streaming](#step-6-start-kafka-streaming)
7. [Verify Everything is Working](#step-7-verify-everything-is-working)
8. [Day-to-Day Usage](#day-to-day-usage)
9. [Stopping and Restarting](#stopping-and-restarting)
10. [Troubleshooting](#troubleshooting)

---

## Step 1: Configure Your Environment

The `.env` file is the single source of truth for all credentials and settings. Every Docker container reads from it.

### 1.1 — Check your `.env` file

The project ships with a `.env` already. Open it and verify these are filled in correctly:

```bash
# Open the .env file
cat .env
```

The critical fields are:

```bash
# AWS credentials — get these from AWS Console → IAM → Users → Security credentials
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here
AWS_DEFAULT_REGION=us-east-1
AWS_REGION=us-east-1

# S3 bucket — where data and models are stored
S3_BUCKET=your-bucket-name

# RDS (PostgreSQL) — where predictions are stored
RDS_HOST=your-rds-endpoint.rds.amazonaws.com
RDS_PORT=5432
RDS_USERNAME=postgres
RDS_PASSWORD=postgres
RDS_DB_NAME=churn-metadata
```

### 1.2 — Verify AWS credentials

```bash
# Test that your credentials work
aws sts get-caller-identity
```

You should see your AWS Account ID, UserID, and ARN. If you get an error, run:

```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region (us-east-1), Output format (json)
```

### 1.3 — Verify S3 bucket access

```bash
# List your S3 buckets
aws s3 ls

# List contents of your project bucket
aws s3 ls s3://$S3_BUCKET/
```

If the bucket is empty, that's fine — the pipelines will create the folder structure automatically.

### 1.4 — Create the Docker network

All services communicate over a shared Docker network. Create it once:

```bash
docker network create churn-pipeline-network
```

If you see `Error: network with name churn-pipeline-network already exists` — that's fine, move on.

### 1.5 — Create local directories

```bash
make setup-dirs
```

This creates `artifacts/data/`, `artifacts/models/`, `data/raw/`, `data/processed/`, and `reports/`.

---

## Step 2: Build Docker Images

The project uses several custom Docker images. Build them all now so there are no delays later.

### 2.1 — Build the pipeline images (data + model + inference)

```bash
docker-compose -f docker-compose.yml build
```

This builds three images from `docker/Dockerfile.base`:
- `churn-pipeline/data:latest` — runs `data_pipeline.py`
- `churn-pipeline/model:latest` — runs `training_pipeline.py`
- `churn-pipeline/inference:latest` — runs `inference_pipeline.py`

⏱️ This takes **10–20 minutes** the first time (downloads Python, installs packages).

### 2.2 — Build the Airflow image

```bash
docker build -f docker/Dockerfile.airflow -t churn-pipeline/airflow:2.8.1-amazon .
```

This builds a custom Airflow image with the Docker provider (needed for DockerOperator) and Amazon provider (needed for AWS integration).

⏱️ This takes **5–10 minutes** the first time.

### 2.3 — Build the Kafka images

```bash
docker-compose -f docker-compose.kafka.yml build
```

This builds three images:
- `kafka/churn-pipeline-producer:latest` — streams customer events
- `kafka/churn-pipeline-inference:latest` — real-time predictions
- `kafka/churn-pipeline-analytics:latest` — saves to PostgreSQL

⏱️ This takes **5–10 minutes** the first time.

### 2.4 — Verify all images were built

```bash
docker images | grep churn-pipeline
```

You should see at least these images:

```
churn-pipeline/data          latest    ...
churn-pipeline/model         latest    ...
churn-pipeline/inference     latest    ...
churn-pipeline/airflow       2.8.1-amazon    ...
churn-pipeline/mlflow        latest    ...
```

And the Kafka images:
```
kafka/churn-pipeline-producer    latest    ...
kafka/churn-pipeline-inference   latest    ...
kafka/churn-pipeline-analytics   latest    ...
```

**If any images are missing**, re-run the build command for that group. Images are idempotent — re-running a build is safe.

---

## Step 3: Start MLflow

MLflow must come up first because both the Airflow pipelines and Kafka consumer log to it, and the `docker-compose.yml` sets it as a health dependency.

### 3.1 — Start MLflow

```bash
docker-compose -f docker-compose.yml up -d mlflow-tracking
```

### 3.2 — Wait for MLflow to be healthy

```bash
# Check the health status
docker ps | grep mlflow-tracking
```

Wait until you see `Up (healthy)` in the STATUS column. This typically takes 30–60 seconds.

You can also watch the logs:

```bash
docker logs mlflow-tracking
# Look for: "Listening at: http://0.0.0.0:5001"
```

### 3.3 — Open MLflow UI

Open http://localhost:5001 in your browser. You should see the MLflow Experiments page (empty at first — experiments will appear after pipelines run).

---

## Step 4: Initialize and Start Airflow

Airflow requires a one-time database initialization before its first run. After that, it's just a regular `up`.

### 4.1 — Initialize the Airflow database (first time only!)

```bash
docker-compose -f docker-compose.airflow.yml run --rm airflow-init
```

This does three things:
1. Runs `airflow db migrate` to create all tables in the local PostgreSQL
2. Creates the admin user (username: `admin`, password: `admin`)
3. Exits once done (the container is removed automatically via `--rm`)

You should see:
```
✅ Airflow init completed
```

⚠️ **Only run this once.** Running it again will reset DAG history. If you need to reset intentionally, use `make airflow-reset`.

### 4.2 — Start all Airflow services

```bash
docker-compose -f docker-compose.airflow.yml up -d
```

This starts 6 containers:
- `airflow-postgres` — local database (NOT the RDS used for predictions)
- `airflow-redis` — task queue broker
- `airflow-webserver` — web UI at port 8080
- `airflow-scheduler` — watches the clock and triggers DAGs
- `airflow-worker` — executes tasks (launches Docker containers)
- `airflow-flower` — Celery worker monitor at port 5555

### 4.3 — Wait for Airflow to be ready

```bash
# Check all containers are up
docker-compose -f docker-compose.airflow.yml ps
```

All services should show "Up". `airflow-postgres` and `airflow-redis` should show "(healthy)". Give it about 1–2 minutes.

You can watch the scheduler come online:
```bash
docker logs airflow-scheduler | tail -20
# Look for: "Launched DagFileProcessorManager"
```

### 4.4 — Open Airflow UI

Open http://localhost:8080 and log in with:
- **Username**: `admin`
- **Password**: `admin`

You should see two DAGs:
- `data_pipeline_hourly`
- `train_pipeline_daily`

Both will show as **paused** (grey toggle). This is intentional — DAGs start paused so you can review them before they run.

### 4.5 — Enable the DAGs

In the Airflow UI, toggle both DAGs to ON (blue):

1. Click the grey toggle next to `data_pipeline_hourly` → turns blue ✅
2. Click the grey toggle next to `train_pipeline_daily` → turns blue ✅

The scheduler will now trigger them on their defined schedules. You can also trigger them manually (see Step 5).

---

## Step 5: Run the ML Pipelines

You need to run the data pipeline first, then the training pipeline. The Kafka streaming consumer needs a trained model to function.

### Option A: Trigger via Airflow UI (recommended)

This is the proper production workflow — Airflow launches the containers and tracks the runs.

**Run the data pipeline:**
1. In Airflow UI, find `data_pipeline_hourly`
2. Click the ▶️ (Trigger DAG) button on the right
3. Click "Trigger" in the popup
4. Watch the run appear in the Grid View — it should turn green in 3–10 minutes

**Run the training pipeline (after data pipeline succeeds):**
1. Find `train_pipeline_daily`
2. Click the ▶️ button
3. Click "Trigger"
4. Watch the run — training takes longer, typically 5–15 minutes

**How to check progress:**
1. Click on `data_pipeline_hourly` → Grid View
2. The task square turns yellow (running) then green (success) or red (failed)
3. Click the square → click "Log" to see real-time output

### Option B: Run pipelines locally (simpler, no AWS)

If you want to quickly test without AWS or Airflow:

```bash
# Run data pipeline (saves to local artifacts/ folder)
make data-pipeline-local

# Run training pipeline (reads from local artifacts/)
make train-pipeline-local
```

⚠️ Local mode skips S3 uploads. The Kafka consumer won't find the model in S3, so this is only for testing the pipeline code itself.

### Option C: Run pipelines with S3 directly

```bash
# Run data pipeline (uploads to S3)
make data-pipeline

# Run training pipeline (downloads data from S3, uploads model to S3)
make train-pipeline
```

### 5.3 — Verify the pipelines ran successfully

**Check S3 for artifacts:**
```bash
aws s3 ls s3://$S3_BUCKET/artifacts/ --recursive --human-readable
```

You should see folders like:
```
artifacts/data/<TIMESTAMP>/X_train.pkl
artifacts/data/<TIMESTAMP>/X_test.pkl
artifacts/data/<TIMESTAMP>/y_train.pkl
artifacts/data/<TIMESTAMP>/scaler.pkl
artifacts/train/<TIMESTAMP>/churn_model.pkl
artifacts/train/<TIMESTAMP>/model_metadata.json
```

**Check MLflow for experiment runs:**

Open http://localhost:5001. You should see:
- An experiment called `data_pipeline` with at least one run
- An experiment called `training_pipeline` with a run showing accuracy, AUC, and other metrics

Click on a run to see the parameters and metrics logged.

---

## Step 6: Start Kafka Streaming

Now that a trained model exists in S3, you can start the real-time streaming pipeline.

### 6.1 — Set up the analytics database table

The analytics service writes to a PostgreSQL table on RDS. Create it first:

```bash
make setup-analytics-tables
```

This runs `sql/create_analytics_tables.sql` against your RDS instance to create the `churn_predictions` table.

If you get a connection error, check that your RDS credentials in `.env` are correct and that the RDS security group allows connections from your IP.

### 6.2 — Start all Kafka services

```bash
docker-compose -f docker-compose.kafka.yml up -d
```

This starts:
- `kafka-broker` — the Kafka message broker (KRaft mode, no Zookeeper)
- `kafka-ui` — web UI at port 8090
- `kafka-producer` — streams customer events from the CSV at 10 events/second
- `kafka-inference` — reads events, loads the model from S3, makes predictions
- `kafka-analytics` — reads predictions, writes to PostgreSQL (RDS)

### 6.3 — Wait for Kafka to be healthy

```bash
docker ps | grep kafka-broker
# Wait for: Up (healthy)
```

It takes about 30 seconds for the broker to initialize.

Then check that all services are running:
```bash
docker-compose -f docker-compose.kafka.yml ps
```

All should show "Up".

### 6.4 — Open Kafka UI

Open http://localhost:8090 in your browser.

Navigate to **Topics** in the left sidebar. After a minute or two, you should see:
- `customer-events` — messages being produced
- `predictions` — messages being consumed and predicted

Click on `customer-events` → **Messages** tab to see live customer events flowing through.

### 6.5 — Watch the logs

```bash
# Producer: sending events
docker logs kafka-producer -f

# Consumer (inference): loading model, making predictions
docker logs kafka-inference -f

# Analytics: writing to RDS
docker logs kafka-analytics -f
```

A healthy producer looks like:
```
✅ Connected to Kafka at kafka:9092
✅ Produced 10 events
✅ Produced 20 events
...
```

A healthy inference service looks like:
```
🚀 Consumer started, waiting for messages...
✅ Loaded model from S3: churn_model.pkl
📦 Collected 1000 messages
✅ Processed batch in 245ms
📤 Published 1000 predictions
```

### 6.6 — Verify predictions are reaching the database

```bash
# Connect to RDS and count predictions
PGPASSWORD=$RDS_PASSWORD psql -h $RDS_HOST -U $RDS_USERNAME -d analytics -c "SELECT COUNT(*) FROM churn_predictions;"
```

The count should increase every time you run this command.

To see recent predictions:
```bash
PGPASSWORD=$RDS_PASSWORD psql -h $RDS_HOST -U $RDS_USERNAME -d analytics -c "
SELECT customer_id, prediction, ROUND(probability::numeric, 2) as probability, predicted_at
FROM churn_predictions
ORDER BY predicted_at DESC
LIMIT 10;
"
```

---

## Step 7: Verify Everything is Working

Run through this checklist to confirm the full system is healthy.

### 7.1 — Check all containers

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

Expected output (all should show "Up"):

```
NAMES                   STATUS
mlflow-tracking         Up (healthy)
airflow-webserver       Up
airflow-scheduler       Up
airflow-worker          Up
airflow-flower          Up
airflow-postgres        Up (healthy)
airflow-redis           Up (healthy)
kafka-broker            Up (healthy)
kafka-ui                Up
kafka-producer          Up
kafka-inference         Up
kafka-analytics         Up
```

### 7.2 — Check each UI

| UI | URL | What to verify |
|----|-----|----------------|
| **MLflow** | http://localhost:5001 | See experiment runs with metrics (accuracy, AUC) |
| **Airflow** | http://localhost:8080 | Both DAGs toggled ON, recent runs show green |
| **Kafka UI** | http://localhost:8090 | `customer-events` and `predictions` topics exist with growing message counts |
| **Flower** | http://localhost:5555 | At least 1 worker showing as "Online" |

### 7.3 — Quick health check script

Run this in one go to see the status of everything:

```bash
./run_local.sh --status
```

Output will show which services are running and their URLs.

### 7.4 — End-to-end data flow check

Confirm data flows all the way from Kafka through to the database:

```bash
# 1. Check producer is sending events
docker logs kafka-producer --tail 5
# Should show: "✅ Produced N events"

# 2. Check consumer is making predictions
docker logs kafka-inference --tail 5
# Should show: "✅ Processed batch in Xms"

# 3. Check predictions are in database
PGPASSWORD=$RDS_PASSWORD psql -h $RDS_HOST -U $RDS_USERNAME -d analytics \
  -c "SELECT COUNT(*), MAX(predicted_at) FROM churn_predictions;"
# Should show: a growing count and a recent timestamp
```

---

## Day-to-Day Usage

Once everything is running, here's what happens automatically and what you do manually.

### What runs automatically

| What | When | How |
|------|------|-----|
| Data preprocessing | Every hour | Airflow `data_pipeline_hourly` DAG |
| Model retraining | Every day at midnight | Airflow `train_pipeline_daily` DAG |
| Real-time predictions | Continuously, 24/7 | Kafka inference service |
| Predictions saved to RDS | Continuously | Kafka analytics service |

### Useful day-to-day commands

```bash
# Check all service status at a glance
./run_local.sh --status

# View any service's logs interactively (choose from a menu)
./run_local.sh --logs

# Trigger a manual data pipeline run right now
# → Airflow UI → data_pipeline_hourly → ▶️

# Check Kafka consumer lag (is inference keeping up?)
docker exec kafka-broker kafka-consumer-groups \
  --bootstrap-server kafka:9092 \
  --group churn-consumer-group \
  --describe

# See how many predictions are in the database today
PGPASSWORD=$RDS_PASSWORD psql -h $RDS_HOST -U $RDS_USERNAME -d analytics \
  -c "SELECT COUNT(*) FROM churn_predictions WHERE predicted_at > NOW() - INTERVAL '1 hour';"

# Check S3 artifacts
aws s3 ls s3://$S3_BUCKET/artifacts/ --recursive --human-readable

# Check MLflow for latest model metrics
# → Open http://localhost:5001 → Experiments → training_pipeline
```

---

## Stopping and Restarting

### Stop everything cleanly

```bash
./run_local.sh --stop
```

This stops Kafka, Airflow, and MLflow in the right order. All data is preserved.

### Stop individual stacks

```bash
# Stop only Kafka
docker-compose -f docker-compose.kafka.yml down

# Stop only Airflow
docker-compose -f docker-compose.airflow.yml down

# Stop only MLflow
docker-compose -f docker-compose.yml down
```

### Restart everything

If services have already been initialized (Airflow DB already set up), restart without reinitializing:

```bash
# Start MLflow first
docker-compose -f docker-compose.yml up -d mlflow-tracking

# Then Airflow (no init needed on restart)
docker-compose -f docker-compose.airflow.yml up -d

# Then Kafka
docker-compose -f docker-compose.kafka.yml up -d
```

Or use the one-liner which handles everything:

```bash
./run_local.sh --skip-build
```

### Pause streaming without stopping

To temporarily pause Kafka without losing container state:

```bash
make pause-kafka
```

To resume:

```bash
make resume-kafka
```

To pause Airflow DAGs from the CLI:

```bash
docker exec airflow-scheduler airflow dags pause data_pipeline_hourly
docker exec airflow-scheduler airflow dags pause train_pipeline_daily
```

To unpause:

```bash
docker exec airflow-scheduler airflow dags unpause data_pipeline_hourly
docker exec airflow-scheduler airflow dags unpause train_pipeline_daily
```

---

## Troubleshooting

### Problem: Docker build fails

```bash
# Clear Docker build cache and retry
docker builder prune -f
docker-compose -f docker-compose.yml build --no-cache
```

If a specific package fails to install, check `requirements.txt` for version conflicts.

### Problem: MLflow won't start

```bash
docker logs mlflow-tracking | tail -30
```

Common causes:
- S3 bucket doesn't exist → create it: `aws s3 mb s3://$S3_BUCKET`
- Invalid AWS credentials → run `aws sts get-caller-identity` to verify

### Problem: Airflow stuck at "Queued" (tasks never run)

```bash
# Check if the worker is alive
docker logs airflow-worker | tail -20
# Look for: "celery@airflow-worker ready"

# Check Redis connection
docker exec airflow-worker redis-cli -h airflow-redis ping
# Should return: PONG

# Restart the worker
docker-compose -f docker-compose.airflow.yml restart airflow-worker
```

### Problem: Airflow task fails (red in UI)

Click the red task → click **Log** → read the actual error message. The most common causes are:

- **S3 access denied** → check `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in `.env`
- **MLflow connection refused** → make sure MLflow is running: `docker ps | grep mlflow`
- **Docker image not found** → check images exist: `docker images | grep churn-pipeline`

You can test the container manually to see the error without Airflow:

```bash
docker run --rm \
  --network churn-pipeline-network \
  -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  -e S3_BUCKET=$S3_BUCKET \
  -e MLFLOW_TRACKING_URI=http://mlflow-tracking:5001 \
  -e USE_S3=true \
  churn-pipeline/data:latest
```

### Problem: Kafka inference fails — "model not found"

```bash
docker logs kafka-inference | grep -i "error\|model\|s3"
```

The consumer downloads the model from S3 on startup. If no model exists yet:

```bash
# Run training pipeline first (this uploads the model to S3)
make train-pipeline

# Then restart the inference service
docker-compose -f docker-compose.kafka.yml restart kafka-inference
```

### Problem: Kafka consumer lag is growing

```bash
docker exec kafka-broker kafka-consumer-groups \
  --bootstrap-server kafka:9092 \
  --group churn-consumer-group \
  --describe
```

If LAG > 1000 and growing:
- Reduce producer rate in `docker-compose.kafka.yml`: `--rate 5` instead of `--rate 10`
- Or restart the inference service (it may have gotten stuck)

```bash
docker-compose -f docker-compose.kafka.yml restart kafka-inference
```

### Problem: RDS connection refused from analytics service

```bash
docker logs kafka-analytics | tail -20
```

Check that:
1. RDS is running: `aws rds describe-db-instances --query 'DBInstances[0].DBInstanceStatus'`
2. Your IP is allowed in the RDS security group (AWS Console → RDS → Security Group → Inbound Rules)
3. Credentials in `.env` match your RDS instance

### Problem: "churn-pipeline-network not found"

```bash
docker network create churn-pipeline-network
```

Then restart whichever service failed.

### Nuclear reset (start completely fresh)

⚠️ This deletes ALL local Docker data for this project. Use only if nothing else works.

```bash
# Stop everything
./run_local.sh --stop

# Remove all project containers, images, and volumes
make docker-clean-all

# Rebuild from scratch
docker-compose -f docker-compose.yml build
docker build -f docker/Dockerfile.airflow -t churn-pipeline/airflow:2.8.1-amazon .
docker-compose -f docker-compose.kafka.yml build

# Re-initialize Airflow
docker-compose -f docker-compose.airflow.yml run --rm airflow-init

# Start everything
docker-compose -f docker-compose.yml up -d mlflow-tracking
docker-compose -f docker-compose.airflow.yml up -d
docker-compose -f docker-compose.kafka.yml up -d
```

---

## Quick Reference Card

Copy and keep this handy:

```bash
# ─────────────────────────────────────────
# FIRST TIME SETUP
# ─────────────────────────────────────────
docker network create churn-pipeline-network
make setup-dirs
docker-compose -f docker-compose.yml build
docker build -f docker/Dockerfile.airflow -t churn-pipeline/airflow:2.8.1-amazon .
docker-compose -f docker-compose.kafka.yml build
docker-compose -f docker-compose.airflow.yml run --rm airflow-init  # ONCE ONLY

# ─────────────────────────────────────────
# START (after first-time setup is done)
# ─────────────────────────────────────────
docker-compose -f docker-compose.yml up -d mlflow-tracking
docker-compose -f docker-compose.airflow.yml up -d
docker-compose -f docker-compose.kafka.yml up -d
# → Trigger data DAG in Airflow UI, then training DAG

# ─────────────────────────────────────────
# CHECK STATUS
# ─────────────────────────────────────────
./run_local.sh --status
docker ps --format "table {{.Names}}\t{{.Status}}"

# ─────────────────────────────────────────
# STOP
# ─────────────────────────────────────────
./run_local.sh --stop

# ─────────────────────────────────────────
# RESTART (no re-init needed)
# ─────────────────────────────────────────
./run_local.sh --skip-build

# ─────────────────────────────────────────
# URLS
# ─────────────────────────────────────────
# Airflow:  http://localhost:8080  (admin/admin)
# MLflow:   http://localhost:5001
# Kafka UI: http://localhost:8090
# Flower:   http://localhost:5555
```

---

**Last Updated**: October 2025  
**Maintained by**: Production ML Systems Course Team  
**Questions?** Check the troubleshooting section, read the service-specific guides in `student-guide/`, or ask your instructor!

Happy Building! 🚀
