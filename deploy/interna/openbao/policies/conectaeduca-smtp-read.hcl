# FUTURE/LAB-ONLY: policy da integração SMTP cross-VM ainda não habilitada.
# Deliberadamente excluída do handoff final.
# Política mínima da workload SMTP.
# KV v2: o endpoint de leitura é secret/data/...
path "secret/data/conectaeduca/smtp" {
  capabilities = ["read"]
}