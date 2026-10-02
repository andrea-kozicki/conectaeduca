# Policy acadêmica mínima da identidade técnica teste.
# Permite somente leitura do segredo demonstrativo dedicado ao pentest.

path "secret/data/pentest-lab/openbao-demo" {
  capabilities = ["read"]
}

path "secret/metadata/pentest-lab/openbao-demo" {
  capabilities = ["read"]
}

# Autoatendimento mínimo exigido pela WebUI para consultar as próprias capacidades.
path "sys/capabilities-self" {
  capabilities = ["update"]
}

# Permite que o token humano encerre a própria sessão, sem revogar terceiros.
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
