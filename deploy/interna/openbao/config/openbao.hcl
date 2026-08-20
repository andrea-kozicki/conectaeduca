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

api_addr     = "http://openbao:8200"
cluster_addr = "https://openbao:8201"
