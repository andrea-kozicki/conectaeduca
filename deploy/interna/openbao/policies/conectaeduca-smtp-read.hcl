# Política mínima da workload SMTP.
# KV v2: o endpoint de leitura é secret/data/...
path "secret/data/conectaeduca/smtp" {
  capabilities = ["read"]
}
