# Testing guide

`make check` verifies every combination offline: `terraform validate` plus
`terraform test` with mocked providers. That proves the configuration is
internally consistent, but mocks can't prove that Snowflake, Google Cloud, AWS
or Fivetran accept every setting. This guide walks through applying each
combination for real against trial accounts, checking it did what it should,
and tearing it down again.

Budget 15–20 minutes for a combination without MWAA, and about 90 minutes with
it (MWAA takes 40–50 minutes to create and 20–25 to delete).

Four runs exercise every module, and all four have been completed against real
accounts: `snowflake/` with Fivetran and EC2 Airflow, `redshift/` with Fivetran
and MWAA, and `bigquery/` with Fivetran and each Airflow option (combos 1/5, 4,
8 and 9 below). Re-run the relevant ones after changing a module or bumping a
provider.

## Before you start

- **Use sandbox/trial accounts, not a real client's:** an AWS account you're
  happy to spin infrastructure up in, a Snowflake trial, a Google Cloud project
  with billing enabled, and a Fivetran trial. Nothing here touches existing
  resources, but Redshift, MWAA and the NAT gateway cost real money per hour.
- **Make teardown clean:** set `redshift_skip_final_snapshot = true` or
  `bigquery_delete_contents_on_destroy = true` for test runs, so destroy leaves
  nothing behind.
- **Always run `terraform destroy` when you're done with a combination,**
  before moving to the next one. See the
  [Redshift](https://aws.amazon.com/redshift/pricing/) and
  [MWAA](https://aws.amazon.com/managed-workflows-for-apache-airflow/pricing/)
  pricing pages for your region.
- **Never commit `terraform.tfvars` or `terraform.tfstate`:** both contain
  plaintext secrets once you apply for real. They're already gitignored.
- **One stack at a time:** the stacks don't share state, but AWS resources are
  named from `aws_prefix`, and IAM role names must be unique per account.
- **Keep your IP stable:** turn off VPNs for the whole run. Redshift and EC2
  Airflow allow only the CIDRs you list.

## General flow for every combination

```bash
cd snowflake   # or redshift, bigquery
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars for this combination (see the table below)
terraform init
terraform plan     # read it before applying
terraform apply
# verify (see the per-component checklists below)
terraform destroy
```

If `terraform apply` fails partway through, fix the cause and run it again:
Terraform picks up where it left off.

---

## Combinations to run through

Cheapest and fastest first, so problems surface before expensive infrastructure
is involved.

| # | Directory | `use_fivetran` | `use_airflow` | `airflow_type` | Notes |
|---|-----------|----------------|---------------|----------------|-------|
| 1 | `snowflake/` | `true` | `false` | — | The default combination: start here |
| 2 | `redshift/` | `true` | `false` | — | First combination that touches AWS |
| 3 | `snowflake/` | `true` | `true` | `mwaa` | |
| 4 | `redshift/` | `true` | `true` | `mwaa` | |
| 5 | `snowflake/` or `redshift/` | `true` | `true` | `ec2` | HTTP only (`airflow_ec2_enable_https = false`) |
| 6 | any | `false` | `false` | — | A bare warehouse with no ingestion tool |
| 7 | `redshift/` | `true` | `true` | `ec2` | `airflow_ec2_enable_https = true`: needs a domain you control |
| 8 | `bigquery/` | `true` | `true` | `ec2` | Set `bigquery_transform_impersonators` to your Google identity |
| 9 | `bigquery/` | `true` | `true` | `mwaa` | As 8; exercises the MWAA credentials plugin and requirements |

You don't need all nine: 1, 4, 5, 8 and 9 cover every module. 6 and 7 are
lower priority.

---

## Per-component verification

### Snowflake (combos 1, 3, 5, 6)
```bash
terraform output -json snowflake
```
Log into Snowflake as `ACCOUNTADMIN` (or your Terraform user) and confirm:
- [ ] Databases `EXTRACT`, `TRANSFORM` and `ANALYSIS` exist, each with a schema of the same name
- [ ] Warehouses `EXTRACT_WH` (X-Small), `TRANSFORM_WH` (Medium) and `ANALYSIS_WH` (X-Small), all with `auto_suspend = 60`
- [ ] Roles `ADMIN_ROLE`, `EXTRACT_ROLE`, `TRANSFORM_ROLE`, `LOAD_ROLE` and `ANALYST_ROLE` exist
- [ ] Users `EXTRACT`, `TRANSFORM` and `LOAD` exist, each with `must_change_password = false`
- [ ] As `EXTRACT`, you can create tables in `EXTRACT.EXTRACT` but get a permission error touching `TRANSFORM` or `ANALYSIS`
- [ ] A table created in `EXTRACT.EXTRACT` by `EXTRACT` is readable by `TRANSFORM` (future grants), which can't write to it
- [ ] A view created in `ANALYSIS.ANALYSIS` by `TRANSFORM` is readable by `LOAD`

### Redshift (combos 2, 4, 5, 7)
```bash
terraform output -json redshift_connection   # host + admin credentials
terraform output -json redshift              # service users
```
Connect with `psql` or any SQL client using the admin credentials. From a
laptop, this needs `redshift_publicly_accessible = true` with your IP in
`redshift_allowed_cidrs`, which Terraform itself needs to create the users and
grants.
- [ ] The database is named `<aws_prefix>_database`, with hyphens turned into underscores (e.g. `acme_co_database`)
- [ ] Schemas `extract`, `transform` and `analysis` exist
- [ ] `SELECT groname, grolist FROM pg_group;` shows `extract_group`, `transform_group`, `load_group`, `admin_group` and `analyst_group`, with the right user in each (`admin_group` holds the master user)
- [ ] As `extract`, you can create tables in `extract` but not in `transform` or `analysis`
- [ ] A table created in `extract` by `extract` is readable by `transform` (default privileges)

### BigQuery (combos 8, 9)
```bash
gcloud auth application-default login   # credentials Terraform uses
gcloud auth login                       # credentials the checks below use
terraform output -json bigquery
terraform output dbt_profile_hint
```
- [ ] Datasets `extract`, `transform` and `analysis` exist in your project, in the location you chose
- [ ] Service accounts `dwh-extract`, `dwh-transform` and `dwh-load` exist, each with an empty **Keys** tab (IAM → Service accounts)
- [ ] `TRANSFORM` is scoped correctly. This helper runs a query as a given service account through the BigQuery API:
  ```bash
  PROJECT=$(terraform output -json bigquery | jq -r .project_id)
  LOCATION=$(terraform output -json bigquery | jq -r .location)
  bq_as() {  # usage: bq_as <stage> '<sql>'
    SA=$(terraform output -json bigquery | jq -r ".service_accounts.$1")
    jq -n --arg q "$2" --arg l "$LOCATION" '{query: $q, useLegacySql: false, location: $l}' |
      curl -s -X POST "https://bigquery.googleapis.com/bigquery/v2/projects/$PROJECT/queries" \
        -H "Authorization: Bearer $(gcloud auth print-access-token --impersonate-service-account=$SA)" \
        -H "Content-Type: application/json" -d @- | jq '.error.message // "OK"'
  }
  bq_as transform 'CREATE TABLE transform.grant_test AS SELECT 1 AS id'     # "OK"
  bq_as transform 'CREATE TABLE `extract`.grant_test AS SELECT 1 AS id'     # access denied
  ```
  `EXTRACT` is a reserved word in BigQuery SQL, hence the backticks. IAM changes
  can take a minute or two to apply, so retry once if the first query is denied.
- [ ] dbt builds as `TRANSFORM` with no key: a profile with `method: oauth` and the `impersonate_service_account` from `dbt_profile_hint`

### Fivetran (all combinations with `use_fivetran = true`)
```bash
terraform output fivetran_group_id
terraform output fivetran_destination_id
```
- [ ] A new group (default `snowflake_warehouse`, `redshift_warehouse` or `bigquery_warehouse`) has a destination of the right type and region
- [ ] Snowflake and Redshift: the destination uses the `EXTRACT` service user, not an admin user (check its connection settings in the Fivetran UI)
- [ ] BigQuery: no key is uploaded, and the group's Fivetran service account has BigQuery User on your project (IAM page)
- [ ] The destination's connection test passes. For Redshift, add [Fivetran's IPs for your `fivetran_region`](https://fivetran.com/docs/using-fivetran/ips) to `redshift_allowed_cidrs` first
- [ ] A real source connector's first sync lands in the extract layer (`EXTRACT` database, `extract` schema, or a per-connector BigQuery dataset)

### MWAA Airflow (combos 3, 4, 9)
```bash
terraform output airflow_mwaa_webserver_url
```
- [ ] The environment shows `AVAILABLE` in the AWS console
- [ ] **Open Airflow UI** in the MWAA console (or `aws mwaa create-web-login-token`) gets you in
- [ ] A DAG uploaded to the bucket's `dags/` prefix appears within a couple of minutes, and a run of it succeeds. Tasks are triggered and inspected from the CLI with MWAA's REST API, e.g.:
  ```bash
  aws mwaa invoke-rest-api --name <env-name> --method POST \
    --path /dags/<dag_id>/dagRuns --body '{"logical_date": null}'
  ```
- [ ] With Redshift: the execution role's IAM policy includes `redshift-data:ExecuteStatement`
- [ ] The five `airflow-<env-name>-*` CloudWatch log groups have 30-day retention, and are gone after `terraform destroy`
- [ ] With BigQuery (combo 9): the environment lists `requirements.txt` and `plugins.zip`, and the [smoke-test DAG](../examples/dags/bigquery_smoke_test.py) succeeds in all three tasks. `as_default` contains no credential code, so its success proves the plugin authenticates tasks as `TRANSFORM`

### EC2 Airflow (combos 5, 7, 8)
```bash
terraform output airflow_ec2_url
terraform output airflow_ec2_admin_username
terraform output airflow_ec2_admin_password
```
- [ ] The URL loads the Airflow login screen within about 10 minutes of the apply finishing (the instance installs Docker and starts Airflow on boot)
- [ ] The admin credentials log you in. If the UI never comes up, connect with SSM Session Manager and check `/var/log/cloud-init-output.log`
- [ ] A DAG uploaded to the bucket's `dags/` prefix appears within 5 minutes (the instance syncs on a cron)
- [ ] Combo 7 (HTTPS): the ACM certificate is `ISSUED` and the URL loads over `https://`. Without a Route53 zone ID, add the DNS record from `terraform output airflow_ec2_acm_validation_record`, wait for validation, then re-apply
- [ ] Combo 8 (BigQuery): the [smoke-test DAG](../examples/dags/bigquery_smoke_test.py) succeeds in all three tasks, logging the `dwh-transform` and `dwh-extract` service accounts:
  ```bash
  aws s3 cp examples/dags/bigquery_smoke_test.py s3://<dag-bucket>/dags/
  ```

---

## Troubleshooting

**Snowflake auth errors:** check `snowflake_account_identifier` is in
`ORGNAME-ACCOUNTNAME` form (Snowsight → account menu → *Connect a tool to
Snowflake*), not the legacy locator (`abc12345.us-east-1`) or a full URL. If
the account blocks password-only sign-in, use key-pair auth (README, step 2).

**Redshift connection refused or timing out (from `psql` or during apply):**
the cluster is private unless `redshift_publicly_accessible = true`. Set that
with your current IP in `redshift_allowed_cidrs`, or run from inside the VPC.

**`terraform destroy` times out connecting to Redshift:** Terraform drops the
users and grants by connecting to the cluster, so it must still be reachable
(check your IP hasn't changed). If the cluster can't be reached at all, remove
those in-cluster objects from state, since they're deleted with the cluster
anyway, and destroy again:
```bash
terraform state rm module.redshift
terraform destroy
```

**Redshift "provider configuration" error on the very first apply:** not
observed in testing, but if it happens, run `terraform apply -target=module.aws`
once to create the cluster, then a plain `terraform apply`. See
`redshift/providers.tf` for why.

**BigQuery "Already Exists: Dataset":** the project already has a dataset with
that name, for example from an earlier dbt run. Import it rather than deleting
it, then apply again:
```bash
terraform import 'module.bigquery.google_bigquery_dataset.this["extract"]' \
  projects/<project-id>/datasets/extract
```
Its location must match `bigquery_location`, or Terraform will plan to replace it.

**MWAA tasks fail instantly with no task log:** the task never reached a
worker. Look in the environment's scheduler log group in CloudWatch
(`airflow-<env-name>-Scheduler`), which the stack enables at warning level.

Note anything that didn't match this guide so it can be corrected.
