ui = true

storage "raft" {
  path    = "/openbao/data"
  node_id = "conectaeduca-openbao-1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = true
}

# No laboratório atual a API é publicada apenas em 127.0.0.1 no host.
# Antes de atravessar VMs, este listener deverá receber TLS real.
api_addr     = "http://openbao:8200"
cluster_addr = "https://openbao:8201"

# Auditoria declarativa para stdout do container.
# O log_raw permanece false: valores sensíveis são HMAC/redigidos pelo OpenBao.
audit "file" "to-stdout" {
  description = "Auditoria OpenBao para coleta posterior pelo Wazuh"
  options = {
    file_path = "stdout"
    log_raw   = "false"
  }
}
