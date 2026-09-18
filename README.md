# Data Infrastructure Deployment

A Terraform stack for standing up a new client's data warehouse and ingestion in
about 30 minutes: modern best-practice RBAC, cost-optimized compute, and your
choice of components — one `terraform apply` does everything you select.

Supports:
- **Snowflake** (default / recommended) or **Redshift**
- **Fivetran** for automated ingestion (default / recommended), optional
- **Airflow** (optional), via MWAA or a self-hosted EC2 instance

Designed for separation of concerns:
- Extraction of raw data from source systems (production DB, third parties, etc.) into the warehouse
- Transformation of raw data into structured, insightful data with dbt
- Distribution of structured data via BI tools for analysts to query

---

## Two entry points, one apply each

This repo has two independent, self-contained Terraform stacks — [`snowflake/`](snowflake/)
and [`redshift/`](redshift/) — sharing the modules in [`modules/`](modules/). Pick the
one matching your client and `cd` into it; everything else (Fivetran, Airflow, MWAA vs
EC2) is a variable choice within that directory. **Why two directories instead of one
`warehouse_type` variable:** the Snowflake Terraform provider authenticates for real
the moment it's configured, regardless of whether any `snowflake_*` resource actually
exists in the plan — so a single stack containing both provider blocks would make
every Redshift deployment fail unless you also had a working Snowflake account. Splitting
by warehouse avoids that entirely, while each directory is still a single `init/plan/apply`
with no remote state and nothing hardcoded to a specific account.

---

## Features

- **One apply, any combination** — pick Snowflake or Redshift, optionally add Fivetran
  and/or Airflow, run `terraform apply` once. Nothing you didn't ask for gets created:
  a pure Snowflake + Fivetran client never touches AWS at all.
- **Cost-optimized compute**
  - Snowflake: separate X-SMALL (extract + analysis) and MEDIUM (transform) warehouses, 60s auto-suspend
  - Redshift: single cluster with schema-based separation + role-based access
- **RBAC done right**
  - Service accounts: `EXTRACT`, `TRANSFORM`, `LOAD`
  - Human roles: `ANALYST_ROLE` (analysis schema only) and `ADMIN_ROLE` (read access across all schemas)
  - Easy to manually create analyst users (or additional admins) and assign the appropriate roles
- **Fivetran integration** — configures the new warehouse as a destination, and wires
  the connection using a dedicated least-privilege `EXTRACT` service user (not the
  admin/master credentials) on both Snowflake and Redshift.
- **Airflow integration** — MWAA-hosted or EC2-hosted (Docker Compose behind an ALB),
  with a versioned, encrypted S3 bucket as the DAG source.

---

## Prerequisites (~5 minutes)

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6.0
- **Redshift, or Airflow with either warehouse:** AWS credentials in your environment
  (`aws configure` or equivalent) with permission to create VPCs, Redshift clusters,
  S3 buckets, IAM roles, and (if using Airflow) MWAA/EC2/ALB/ACM resources.
- **Snowflake:** a Snowflake account and a user with `ACCOUNTADMIN` (or equivalent) to
  run Terraform with.
- **Fivetran (optional):** a Fivetran account, an API key/secret
  ([Fivetran docs](https://fivetran.com/docs/rest-api/getting-started)), and a group ID.

Nothing else is required to get started — state defaults to a local backend, so there's
no external account to set up just to run `terraform init`.

## Quickstart (~30 minutes end-to-end for a new client)

1. **Clone the repo and pick your warehouse**
   ```bash
   git clone https://github.com/donovannevard/data-infrastructure-deployment.git
   cd data-infrastructure-deployment/snowflake   # or data-infrastructure-deployment/redshift
   ```

2. **Copy and edit variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
   Almost everything has a sensible default (see `variables.tf`) — you only need to
   fill in account credentials and (for Redshift, or EC2 Airflow) the CIDR restriction
   variables, which deliberately have no default so you don't accidentally leave
   anything open to the whole internet. See the comments in `terraform.tfvars.example`
   for exactly what's needed for your chosen combination.

3. **Initialize and deploy**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```
   That's it — one apply creates everything you selected (network, warehouse,
   Fivetran destination, Airflow) in the correct order automatically.

4. **Retrieve credentials**
   ```bash
   terraform output -json snowflake   # or `redshift`, depending on directory
   ```
   These, and the local `terraform.tfstate` file itself, contain plaintext secrets.
   Store them in a password manager and treat the state file as sensitive (see
   Security Notes below).

## Repo Structure
```
.
├── snowflake/            (Snowflake stack: main.tf, variables.tf, outputs.tf, providers.tf)
├── redshift/             (Redshift stack: same shape as snowflake/)
└── modules/              (shared by both stacks)
    ├── aws/               (VPC, Redshift cluster, S3 bucket for DAGs)
    ├── redshift/          (schemas, users, groups, grants)
    ├── snowflake/         (warehouses, databases, schemas, roles, users, grants)
    ├── fivetran/          (destination + connector)
    ├── airflow_mwaa/
    └── airflow_ec2/
```

## Key Variables
See each directory's `variables.tf` for the full list and defaults.

| Variable                            | Description                                  | Default      |
|--------------------------------------|-----------------------------------------------|--------------|
| `use_fivetran`                       | Deploy a Fivetran destination + connector      | `true`       |
| `use_airflow`                        | Deploy Airflow                                | `false`      |
| `airflow_type`                       | `mwaa` or `ec2`                               | `mwaa`       |
| `redshift_inbound_cidr_restriction`  | CIDR allowed to reach Redshift (5439)         | *(required, redshift/ only)* |
| `ec2_inbound_cidr_restriction`       | CIDR allowed to reach EC2 Airflow via the ALB | *(required if ec2 airflow)* |
| `airflow_ec2_enable_https`           | Serve EC2 Airflow over HTTPS via ACM           | `false`      |

## Warehouse Architecture

### Snowflake
- **Databases**: `EXTRACT`, `TRANSFORM`, `ANALYSIS`
- **Schemas**: `extract`, `transform`, `analysis`
- **Warehouses**: `EXTRACT_WH` (X-SMALL), `TRANSFORM_WH` (MEDIUM), `ANALYSIS_WH` (X-SMALL)
- **Roles & Users**: Service users (`EXTRACT`, `TRANSFORM`, `LOAD`) + analyst/admin roles

### Redshift
- Single database with schemas: `extract`, `transform`, `analysis`
- Equivalent service users and roles, assigned to groups natively (no external
  `psql` step required)

## Remote state (optional)

By default each stack uses `backend "local" {}` — zero external accounts needed to
get started, matching the 30-minute goal. The local state file contains plaintext
secrets, so back it up somewhere encrypted per client (e.g. a password manager, or
an encrypted volume) rather than leaving it as a bare file.

If you want state locking/collaboration across a team, switch the `backend "local" {}`
block in `main.tf` to S3 or Terraform Cloud. Terraform backend blocks can't use
variables, so this is a one-time manual edit per client — or pass `-backend-config`
flags at `terraform init` time to parameterize it without editing the file, e.g.:
```bash
terraform init \
  -backend-config="bucket=acme-co-tfstate" \
  -backend-config="key=snowflake/terraform.tfstate" \
  -backend-config="region=eu-west-2"
```
(with `backend "s3" {}` declared empty in `main.tf`).

## Post-Deployment Steps
### Analysts
1. Create users manually in Snowflake / Redshift
2. Grant `ANALYST_ROLE` (read access to the analysis schema/database only)
3. Senior analysts: also grant `ADMIN_ROLE` (read access across all schemas/databases)

Example (Snowflake):
```sql
CREATE USER johnsmith PASSWORD = 'StrongPass123!' MUST_CHANGE_PASSWORD = TRUE;
GRANT ROLE ANALYST_ROLE TO USER johnsmith;
```

Example (Redshift):
```sql
CREATE USER janedoe PASSWORD 'StrongPass123!';
ALTER GROUP analyst_group ADD USER janedoe;
```

## Airflow / dbt / Fivetran
- Use the `EXTRACT` service user for Fivetran or Airflow extraction into the warehouse
- Use the `TRANSFORM` service user for dbt transformations of the raw data
- Use the `LOAD` service user for BI tool connections (QuickSight, Sigma, etc.) to query the structured data output by dbt

## Security Notes
- All service user passwords are randomly generated and exposed only via sensitive Terraform outputs
- Least-privilege grants applied throughout, including for the Fivetran connector itself
  (it authenticates as the `EXTRACT` service user, not the warehouse admin)
- `must_change_password = false` for service accounts, `true` for human users you create manually
- `redshift_inbound_cidr_restriction` and `ec2_inbound_cidr_restriction` have no
  default on purpose — pick your actual office/VPN CIDR, never `0.0.0.0/0`
- The Redshift cluster is always `publicly_accessible = false`, in private subnets
- The local state file contains plaintext secrets — treat it like a credentials file
- Rotate passwords as needed via Terraform (`terraform taint` the relevant
  `random_password` resource) or directly in the Snowflake/Redshift UI

## Testing
See [`docs/testing.md`](docs/testing.md) for a guided walkthrough of applying
and verifying each combination for real (Snowflake/Redshift × Fivetran ×
Airflow) before trusting this in front of a client.

## Contributing
Feel free to open issues or PRs for improvements.
