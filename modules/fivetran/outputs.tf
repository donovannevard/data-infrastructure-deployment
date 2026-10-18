output "fivetran_group_id" {
  description = "Fivetran group ID (add source connectors to this group)"
  value       = fivetran_destination.main.group_id
}

output "fivetran_destination_id" {
  description = "Fivetran destination ID"
  value       = fivetran_destination.main.id
}
