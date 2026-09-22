# Policy acadêmica mínima da identidade técnica teste.
# Permite somente leitura do segredo demonstrativo dedicado ao pentest.

path "secret/data/pentest-lab/openbao-demo" {
  capabilities = ["read"]
}

path "secret/metadata/pentest-lab/openbao-demo" {
  capabilities = ["read"]
}
