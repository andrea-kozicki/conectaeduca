---
# Derivado de Wazuh Docker v4.14.7.
# Os hashes abaixo são gerados localmente em .runtime/ e NÃO devem ser versionados.
_meta:
  type: "internalusers"
  config_version: 2

admin:
  hash: "__ADMIN_HASH__"
  reserved: true
  backend_roles:
    - "admin"
  description: "Wazuh admin"

kibanaserver:
  hash: "__KIBANASERVER_HASH__"
  reserved: true
  description: "Wazuh dashboard service user"

kibanaro:
  hash: "__KIBANARO_HASH__"
  reserved: false
  backend_roles:
    - "kibanauser"
    - "readall"
  attributes:
    attribute1: "value1"
    attribute2: "value2"
    attribute3: "value3"
  description: "Wazuh read-only dashboard user"

logstash:
  hash: "__LOGSTASH_HASH__"
  reserved: false
  backend_roles:
    - "logstash"
  description: "Wazuh logstash service user"

readall:
  hash: "__READALL_HASH__"
  reserved: false
  backend_roles:
    - "readall"
  description: "Wazuh read-only user"

snapshotrestore:
  hash: "__SNAPSHOTRESTORE_HASH__"
  reserved: false
  backend_roles:
    - "snapshotrestore"
  description: "Wazuh snapshot/restore user"
