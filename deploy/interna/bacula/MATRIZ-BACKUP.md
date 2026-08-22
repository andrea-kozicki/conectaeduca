# Matriz de escopo do backup

Princípio: **backup por fonte autoritativa e formato consistente**, nunca
`backup de /` nem cópia cega de `/var/lib/docker`.

| Objeto | Baseline Bacula | Estratégia |
|---|---|---|
| MariaDB ConectaEduca | SIM | dump consistente em staging protegido |
| dados persistentes da aplicação | SIM, se existirem | diretórios explicitamente cadastrados |
| configuração específica da implantação | SIM | allowlist de arquivos |
| código versionado | SECUNDÁRIO | Git é a fonte principal; registrar commit |
| OpenBao Raft | SIM | snapshot Raft consistente |
| OpenBao configuração não secreta | SIM | allowlist |
| Wazuh regras/config customizadas | SIM | allowlist |
| Wazuh índices/volumes do Indexer | NÃO no baseline | retenção própria; revisar em evolução |
| Ferret config/policies | SIM | arquivos versionados/allowlist |
| Ferret suppressions operacionais | AVALIAR | somente se não contiver material sensível impróprio |
| Ferret inbox | NÃO | fonte potencialmente sensível |
| Ferret reports/raw | NÃO | relatório bruto nunca vira backup geral |
| Ferret events JSONL | NÃO no baseline | observabilidade/SIEM, não fonte primária |
| `.env` real | NÃO | reconstruir por gestão de segredos |
| Gmail App Password | NÃO | permanece no OpenBao |
| OpenBao root token | NUNCA | não deve existir como artefato de backup |
| unseal shares | NUNCA | custódia offline separada |
| Docker socket | NUNCA | não é dado de backup |
| Docker images | NÃO | reconstruíveis/pull por digest |
| volumes Docker crus | NÃO por padrão | usar export/snapshot específico do serviço |
| caches/tmp | NÃO | reconstruíveis |
| chaves privadas de PKI | NÃO indiscriminadamente | custódia/backup criptográfico específico |

## Allowlist em vez de wildcard

Todo FileSet deverá declarar diretórios/arquivos explicitamente. Inclusões novas
exigem revisão da equipe. Não usar `Include = /` como atalho.

## Dados futuros

Se o ConectaEduca ganhar uploads/documentos persistentes, o diretório só passa
a fazer parte do backup após:
1. ser identificado como fonte autoritativa;
2. ter owner/permissões definidos;
3. ter teste de restore;
4. entrar no checkpoint.
