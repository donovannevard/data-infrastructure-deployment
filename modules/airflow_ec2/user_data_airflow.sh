#!/bin/bash
set -euo pipefail

# Install Docker, cron and the Docker Compose v2 CLI plugin (Amazon Linux 2023;
# the AWS CLI is preinstalled, cron is not)
dnf update -y
dnf install -y docker cronie
systemctl enable --now docker crond
usermod -a -G docker ec2-user
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Declare working variables
AIRFLOW_HOME_DIR="/opt/airflow"
DAG_DIR="$AIRFLOW_HOME_DIR/dags"
BUCKET="${dag_bucket}"
mkdir -p "$DAG_DIR"
chown -R 50000:0 "$AIRFLOW_HOME_DIR" # the uid the official Airflow image runs as
cd "$AIRFLOW_HOME_DIR"

# Initial sync
aws s3 sync "s3://$BUCKET/dags" "$DAG_DIR" --region ${aws_region}

# Install cron job to keep updated
cat <<CRON > /etc/cron.d/airflow-dag-sync
*/5 * * * * root /usr/bin/aws s3 sync s3://$BUCKET/dags $DAG_DIR --region ${aws_region}
CRON

# Declare the docker compose file
cat > docker-compose.yml << 'COMPOSE'
x-airflow-env: &airflow-env
  AIRFLOW__CORE__EXECUTOR: LocalExecutor
  AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:${postgres_password}@postgres/airflow
  AIRFLOW__CORE__LOAD_EXAMPLES: "false"
  AIRFLOW__SCHEDULER__DAG_DIR_LIST_INTERVAL: "30"

services:
  postgres:
    image: postgres:13-alpine
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: ${postgres_password}
      POSTGRES_DB: airflow
    volumes:
      - postgres_db:/var/lib/postgresql/data
    restart: always

  webserver:
    image: apache/airflow:2.9.3-python3.11
    command: webserver
    environment: *airflow-env
    volumes:
      - /opt/airflow/dags:/opt/airflow/dags
    ports:
      - "8080:8080"
    depends_on:
      - postgres
    restart: always

  scheduler:
    image: apache/airflow:2.9.3-python3.11
    command: scheduler
    environment: *airflow-env
    volumes:
      - /opt/airflow/dags:/opt/airflow/dags
    depends_on:
      - postgres
    restart: always

volumes:
  postgres_db:
COMPOSE

# Initialise the metadata DB, create the admin user, then start Airflow
docker compose run --rm webserver airflow db migrate
docker compose run --rm webserver airflow users create \
  --email '${admin_email}' \
  --username admin \
  --password '${admin_password}' \
  --firstname admin \
  --lastname admin \
  --role Admin
docker compose up -d
echo "Airflow started! Web UI available via the ALB."
