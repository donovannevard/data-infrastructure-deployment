# Shared Google Cloud mock data for `terraform test` in bigquery/.
# The Google provider validates resource name formats even when mocked, so give
# the resources whose names are passed to other resources realistic values.

mock_resource "google_service_account" {
  defaults = {
    email = "mock-sa@test-project.iam.gserviceaccount.com"
    name  = "projects/test-project/serviceAccounts/mock-sa@test-project.iam.gserviceaccount.com"
  }
}
mock_resource "google_iam_workload_identity_pool" {
  defaults = { name = "projects/123456789012/locations/global/workloadIdentityPools/airflow-mock" }
}
mock_resource "google_iam_workload_identity_pool_provider" {
  defaults = { name = "projects/123456789012/locations/global/workloadIdentityPools/airflow-mock/providers/aws-airflow" }
}
