# Testing guide

`make check` verifies every combination offline: `terraform validate` plus
`terraform test` with mocked providers. That proves the configuration is
internally consistent, but mocks can't prove that Snowflake, AWS or Fivetran
accept every setting. This guide walks through applying each combination for
real against trial accounts, checking it did what it should, and tearing it
down again. Budget 15-20 minutes for a combination without MWAA, and about
90 minutes with it (MWAA takes 30-40 minutes to create and 20-25 to delete).

Two runs cover every module, and both have been completed against real
accounts: `snowflake/` with Fivetran and EC2 Airflow, and `redshift/` with
Fivetran and MWAA. Re-run them after changing a module or bumping a provider.

## Before you start

- **Use sandbox/trial accounts, not a real client's**, for this first pass:
  an AWS account you're happy to spin infrastructure up in, a Snowflake trial
  account, a Fivetran trial account. Nothing here is destructive to existing
  resources, but Redshift and MWAA both cost real money per hour while running.
- **Set `redshift_skip_final_snapshot = true`** for test runs, so destroy doesn't
  leave a snapshot behind (if you forget, destroy prints the delete command).
- **Always run `terraform destroy` when you're done with a combination**
  before moving to the next one — Redshift clusters, MWAA environments, and
  NAT gateways are the expensive parts, all billed hourly (see the
  [Redshift](https://aws.amazon.com/redshift/pricing/) and
  [MWAA](https://aws.amazon.com/managed-workflows-for-apache-airflow/pricing/)
  pricing pages for your region). Don't leave them running between sessions.
- **Never commit `terraform.tfvars` or `terraform.tfstate`** — both contain
  plaintext secrets once you apply for real. They're already gitignored.
- Work through `snowflake/` and `redshift/` as two entirely separate sessions —
  they don't share state or interact with each other.

## General flow for every combination

```bash
cd snowflake   # or redshift
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars for this combination — see checklist below
terraform init
terraform plan     # read it before applying — should match what you expect
terraform apply
# ... verify (see per-component checklists below) ...
terraform destroy  # tear down before moving to the next combination
```

If `terraform apply` ever fails partway through, re-run `terraform apply` again
before troubleshooting further — Terraform is safe to re-run and will pick up
where it left off.

---

## Combinations to run through

Suggested order: cheapest/fastest first, so you catch problems early without
burning time on expensive infra.

| # | Directory | `use_fivetran` | `use_airflow` | `airflow_type` | Notes |
|---|-----------|-----------------|-----------------|------------------|-------|
| 1 | `snowflake/` | `true` | `false` | — | The default/recommended combo — start here |
| 2 | `redshift/` | `true` | `false` | — | First combo that touches AWS |
| 3 | `snowflake/` | `true` | `true` | `mwaa` | |
| 4 | `redshift/` | `true` | `true` | `mwaa` | |
| 5 | `snowflake/` or `redshift/` | `true` | `true` | `ec2` | HTTP only (`airflow_ec2_enable_https = false`) — leave HTTPS for last |
| 6 | either | `false` | `false` | — | Confirms a bare warehouse-only deploy works with no ingestion tool |
| 7 | `redshift/` | `true` | `true` | `ec2` | `airflow_ec2_enable_https = true` — needs a real domain you control |

You don't strictly need all 7 — 1, 2, 3 (or 4), and 5 cover the combinations
most likely to be used with a real client. 6 and 7 are lower priority.

---

## Per-component verification

### Snowflake (combos 1, 3, 5, 6)
```bash
terraform output -json snowflake
```
Log into Snowflake as `ACCOUNTADMIN` (or your Terraform user) and confirm:
- [ ] Databases `EXTRACT`, `TRANSFORM`, `ANALYSIS` exist, each with the schema name you configured (default `EXTRACT`/`TRANSFORM`/`ANALYSIS`)
- [ ] Warehouses `EXTRACT_WH` (X-SMALL), `TRANSFORM_WH` (MEDIUM), `ANALYSIS_WH` (X-SMALL), all `auto_suspend = 60`
- [ ] Roles `ADMIN_ROLE`, `EXTRACT_ROLE`, `TRANSFORM_ROLE`, `LOAD_ROLE`, `ANALYST_ROLE` exist
- [ ] Users `EXTRACT`, `TRANSFORM`, `LOAD` exist, each with `must_change_password = false`
- [ ] Log in as the `EXTRACT` user (credentials from the output above) and confirm it can create/write tables in `EXTRACT.EXTRACT` but gets a permission error touching `TRANSFORM` or `ANALYSIS`
- [ ] Create a table in `EXTRACT.EXTRACT` as `EXTRACT`, then confirm the `TRANSFORM` user can `SELECT` from it (future grants) but cannot write to it
- [ ] As `TRANSFORM`, create a view in `ANALYSIS.ANALYSIS`, then confirm the `LOAD` user can `SELECT` from it

### Redshift (combos 2, 4, 5, 7)
```bash
terraform output -json redshift_connection   # host + admin credentials
terraform output -json redshift              # service users
```
Connect with `psql` (or any SQL client) using the admin credentials. For testing
from a laptop, set `redshift_publicly_accessible = true` with your own IP in
`redshift_allowed_cidrs` (Terraform needs the same access to create users and grants).
- [ ] Database is named `<aws_prefix>_database`, with hyphens turned into underscores (e.g. `acme_co_database`)
- [ ] Schemas `extract`, `transform`, `analysis` exist
- [ ] `SELECT groname, grolist FROM pg_group;` shows `extract_group`, `transform_group`, `load_group`, `admin_group`, `analyst_group`, each with the right user already a member (`admin_group` contains the master user)
- [ ] Log in as the `extract` user and confirm it can create tables in the `extract` schema but not `transform`/`analysis`
- [ ] Create a table in `extract` as `extract`, then confirm the `transform` user can `SELECT` from it (default privileges)

### Fivetran (combos 1-5, 7)
```bash
terraform output fivetran_group_id
terraform output fivetran_destination_id
```
- [ ] A new group (default `snowflake_warehouse` / `redshift_warehouse`) appears in the Fivetran dashboard with a destination of the correct type and region
- [ ] It's configured with the `EXTRACT` service user, not an admin/master user — check the connection config in the Fivetran UI
- [ ] Run the destination's connection test in the Fivetran UI. For Redshift, add [Fivetran's IPs for your region](https://fivetran.com/docs/using-fivetran/ips) to `redshift_allowed_cidrs` first
- [ ] Add a real source connector to the group and confirm the first sync lands in the `EXTRACT` database / `extract` schema

### MWAA Airflow (combos 3, 4)
```bash
terraform output airflow_mwaa_webserver_url
```
- [ ] MWAA environment shows `AVAILABLE` in the AWS console (this takes 30-40 minutes — the slowest part of any MWAA test)
- [ ] `aws mwaa create-web-login-token --name <env-name>` (or just the console's "Open Airflow UI" button) gets you into the webserver
- [ ] Drop a test DAG file into the S3 bucket's `dags/` prefix and confirm it shows up in the Airflow UI within a few minutes
- [ ] If testing with Redshift: confirm the MWAA execution role's IAM policy includes `redshift-data:ExecuteStatement` (check the role in the IAM console)

### EC2 Airflow (combo 5, 7)
```bash
terraform output airflow_ec2_url
terraform output airflow_ec2_admin_username
terraform output airflow_ec2_admin_password
```
- [ ] The URL loads the Airflow login screen within a few minutes of apply completing (cloud-init takes a little while)
- [ ] The admin credentials above log you in. If the UI never comes up, connect with SSM Session Manager and check `/var/log/cloud-init-output.log`
- [ ] Drop a test DAG into the S3 bucket's `dags/` prefix and confirm it appears in the UI within 5 minutes (the instance polls on a cron)
- [ ] For combo 7 (HTTPS): confirm the ACM certificate shows `ISSUED` in the AWS console, and the URL loads over `https://` with a valid cert
- [ ] For combo 7 without a Route53 zone ID: confirm `terraform output airflow_ec2_acm_validation_record` gives you a real DNS record, add it with your DNS provider, wait for validation, then re-apply and confirm the listener comes up

---

## Troubleshooting

**Redshift-related "provider configuration" error on the very first apply of a
brand-new AWS account:** this hasn't been observed in testing, but if it ever
happens, run `terraform apply -target=module.aws` once to create the cluster,
then a plain `terraform apply` to finish the rest. See `redshift/providers.tf`
for why this is a defensive fallback rather than an expected step.

**Snowflake auth errors:** double check `snowflake_account_identifier` is in
`ORGNAME-ACCOUNTNAME` form (Snowsight → account menu → *Connect a tool to
Snowflake*), not the legacy locator (`abc12345.us-east-1`) or a full URL.

**Redshift connection refused or timing out (from `psql` or during `apply`):**
the cluster is private unless `redshift_publicly_accessible = true`. Either set
that with your IP in `redshift_allowed_cidrs`, or run from inside the VPC.

**`terraform destroy` times out connecting to Redshift:** Terraform drops the
users and grants by connecting to the cluster, so it must still be reachable
(check your IP is still in `redshift_allowed_cidrs`). If the cluster can't be
reached at all, remove those in-cluster objects from state — they're deleted
with the cluster anyway — and destroy again:
```bash
terraform state rm module.redshift
terraform destroy
```

Once you've been through this, note anything that didn't match this doc so it
can be corrected.
