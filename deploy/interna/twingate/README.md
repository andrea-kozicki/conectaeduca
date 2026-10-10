# Twingate Connector — ConectaEduca

Imagem fixada:
`twingate/connector@sha256:833e7a968f1b3a5ad79b88b04f82aad1bfc8621f61b6b35f01be2411d35beba9`

Destino arquitetural: VM Ubuntu interna.

Controles:
- profile `twingate` (não sobe por padrão);
- `network_mode: host`;
- nenhuma porta publicada;
- nenhum volume;
- sem Docker socket;
- imagem executa como `nonroot`;
- `no-new-privileges`;
- tokens somente em `/dev/shm/conectaeduca-twingate.env` com modo 0600.

Fluxo:
1. `preparar_twingate_runtime.fish`
2. `ativar_twingate_connector.fish`
3. `checkpoint_twingate_operacional.sh`

Nenhum token deve ser versionado ou incluído em evidências.

---

## Plano de ativação após o Pentest A — documentação de 09/10/2026

**O Connector ainda não deve ser ativado durante o Pentest A.** Para a Fase 3,
foram preparados o [runbook com gates G0–G6 e matriz A/B](../../../docs/seguranca/TWINGATE-RUNBOOK-POS-PENTEST-A.md),
o [checklist de execução/rollback](../../../docs/release/TWINGATE-CHECKLIST-CAMPO.md)
e a [solicitação ao suporte](../../../docs/release/TWINGATE-SOLICITACAO-SUPORTE.md).

A execução requer **autorização institucional** e operador com privilégios Docker;
não é procedimento do usuário `teste`. O Twingate deve expor somente o Resource
WAF da EP125 na porta TCP 443, e não o backend da aplicação ou serviços internos.

**Observação de segredos:** embora o arquivo de tokens `/dev/shm` seja
efêmero, o Compose os passa por variáveis de ambiente do container, que podem
ficar visíveis nos metadados administrativos do Docker. Proteger acessos e
planejar rotação/revogação; não anexar `docker inspect` bruto em evidências.
