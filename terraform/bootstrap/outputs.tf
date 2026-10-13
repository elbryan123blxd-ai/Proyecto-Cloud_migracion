output "tfstate_bucket" {
  description = "Nombre del bucket donde el resto de los modulos guarda su estado"
  value       = aws_s3_bucket.tfstate.id
}

output "tflock_table" {
  description = "Tabla DynamoDB para el lock del estado"
  value       = aws_dynamodb_table.tflock.name
}
