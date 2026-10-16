# =============================================================================
# S3 -- reemplaza al Storage de Supabase. Las apps Next.js (Fase 3) van a
# subir/leer archivos aca directo via SDK de AWS, con credenciales acotadas
# (no via un servicio intermedio -- el alcance de este clon no incluye
# replicar el "storage-api" propio de Supabase, solo el bucket).
# =============================================================================

resource "aws_s3_bucket" "archivos" {
  bucket = "academia-premier-archivos-994b4178" # mismo sufijo random que el bucket de tfstate, por unicidad global

  tags = { Name = "academia-premier-s3-archivos" }
}

resource "aws_s3_bucket_public_access_block" "archivos" {
  bucket = aws_s3_bucket.archivos.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archivos" {
  bucket = aws_s3_bucket.archivos.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "archivos" {
  bucket = aws_s3_bucket.archivos.id

  versioning_configuration {
    status = "Disabled" # clon de portfolio: no hace falta historial de versiones, serian mas GB cobrados por las dudas
  }
}
