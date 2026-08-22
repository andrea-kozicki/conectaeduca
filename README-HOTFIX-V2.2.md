# Hotfix OpenBao retomada v2.2

## v2.1 — eleição Raft pós-unseal

A retomada passou a exigir `/sys/health` HTTP 200, `sealed=false` e
`standby=false` antes de operações administrativas, evitando a condição:

`local node not active but active cluster node not found`

## v2.2 — decode seguro do generate-root

O decoder do `encoded_token`:

- normaliza padding Base64 eventualmente omitido;
- valida o conteúdo antes da decodificação;
- mantém OTP e root token somente em memória;
- não imprime OTP, encoded token, root token ou unseal shares.

O root temporário continua sendo revogado ao fim da recuperação e o endpoint
legado de generate-root volta a ser desabilitado.
