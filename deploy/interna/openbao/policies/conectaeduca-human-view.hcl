# ConectaEduca — policy humana de visualização/demonstração.
# Não concede leitura de valores em secret/data/*.

path "sys/health" {
  capabilities = ["read"]
}
path "sys/seal-status" {
  capabilities = ["read"]
}
path "sys/mounts" {
  capabilities = ["read"]
}
path "sys/auth" {
  capabilities = ["read"]
}
path "secret/metadata/conectaeduca" {
  capabilities = ["read", "list"]
}
path "secret/metadata/conectaeduca/*" {
  capabilities = ["read", "list"]
}
