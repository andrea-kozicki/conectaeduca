# Ferret Scan — imagem validada

Baseline operacional do DLP do ConectaEduca após reconciliação pós-VM.

- Produto: Ferret Scan (AWS Labs)
- Versão: 2.4.3
- Plataforma: linux/amd64
- Imagem: `public.ecr.aws/awslabs/ferret-scan:2.4.3`
- Digest: `sha256:7a1b36050ae20a74632ac05b5c34e4aeb26b69836ca6703e10c1392b724b270f`
- Entrypoint: `/ferret-scan`
- Usuário da imagem: `ferret`

A referência usada pelo Compose inclui versão e digest. Não substituir por `latest` no baseline validado.

A mesma imagem/digest foi observada na EP126 e validada em teste isolado com scan limpo e finding sintético. O formatter JSON 2.4.3 retornou objeto com `stats` + `results` nos dois casos; a sanitização allowlist permaneceu fail-closed e não propagou conteúdo bruto ao evento SIEM.
