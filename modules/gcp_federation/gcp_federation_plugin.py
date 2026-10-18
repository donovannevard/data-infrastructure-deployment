"""Keyless BigQuery access for every MWAA task (managed by Terraform).

MWAA runs tasks on Fargate, where Google's auth libraries can't read the
task's AWS role credentials by themselves. This listener runs in each task's
own process just before it executes and calls use_aws_role_for_gcp() from
dags/gcp/gcp_federation.py, so every task starts out authenticated to BigQuery
as the TRANSFORM service account, exactly as on EC2 Airflow. A task that needs
a different stage calls use_aws_role_for_gcp("extract") itself.
"""

import logging
import sys

from airflow.listeners import hookimpl
from airflow.plugins_manager import AirflowPlugin

log = logging.getLogger(__name__)


@hookimpl
def on_task_instance_running(previous_state, task_instance):
    # Never let credential setup fail a task that may not even use Google Cloud
    try:
        from gcp.gcp_federation import use_aws_role_for_gcp

        use_aws_role_for_gcp("transform")
    except Exception:
        log.warning("Could not set up keyless BigQuery credentials", exc_info=True)


class GcpFederationPlugin(AirflowPlugin):
    name = "gcp_federation"
    listeners = [sys.modules[__name__]]
