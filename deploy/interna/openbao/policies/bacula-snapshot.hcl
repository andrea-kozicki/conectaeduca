# Identidade operacional dedicada ao snapshot do OpenBao.
# O snapshot usa GET em /sys/storage/raft/snapshot.
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
