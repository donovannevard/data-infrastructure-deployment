"""Smoke test for keyless BigQuery access from Airflow (bigquery/ stack).

Upload to the DAG bucket, then trigger it from the Airflow UI:

    aws s3 cp examples/dags/bigquery_smoke_test.py s3://<dag-bucket>/dags/

It queries BigQuery through workload identity federation and logs which
identity BigQuery saw:

- as_default: no credential code at all, so it proves every task starts out
  as TRANSFORM (via the instance role on EC2, or the stack's plugin on MWAA)
- as_extract / as_transform: switching stage explicitly

No Google keys are involved, and nothing needs installing: on MWAA the stack
adds the BigQuery client library itself.
"""

from datetime import datetime

from airflow.decorators import dag, task


def _check_identity(stage: str) -> str:
    from google.cloud import bigquery

    row = next(iter(bigquery.Client().query("SELECT SESSION_USER() AS identity").result()))
    identity = row["identity"]
    print(f"BigQuery sees the {stage} task as: {identity}")
    if f"-{stage}@" not in identity:
        raise ValueError(f"Expected the {stage} service account, got {identity}")
    return identity


@dag(schedule=None, start_date=datetime(2026, 1, 1), catchup=False, tags=["smoke-test", "bigquery"])
def bigquery_smoke_test():
    @task
    def as_default() -> str:
        return _check_identity("transform")

    @task
    def query_as(stage: str) -> str:
        from gcp.gcp_federation import use_aws_role_for_gcp

        use_aws_role_for_gcp(stage)
        return _check_identity(stage)

    as_default()
    query_as.override(task_id="as_transform")("transform")
    query_as.override(task_id="as_extract")("extract")


bigquery_smoke_test()
