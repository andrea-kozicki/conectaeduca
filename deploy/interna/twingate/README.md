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
não é procedimento do usuário `teste`. Na **Fase 3**, o Resource WAF EP125:443 é somente um **ensaio inicial** de conectividade ZTNA, não a arquitetura completa. O site público permanece na porta HTTPS 443 e sem obrigatoriedade de Client. Os Resources privados de Operação/SOC/Admin são separados por grupos e portas mínimas, apenas após validação de listener, rota, TLS e firewall. É proibido liberar backend PHP, MariaDB, OpenBao, Catalog ou Bacula diretamente por padrão. Consulte os documentos atualizados abaixo.

**Observação de segredos:** embora o arquivo de tokens `/dev/shm` seja
efêmero, o Compose os passa por variáveis de ambiente do container, que podem
ficar visíveis nos metadados administrativos do Docker. Proteger acessos e
planejar rotação/revogação; não anexar `docker inspect` bruto em evidências.


## Fase 3 — desenho por identidade e porção de infraestrutura (21/10/2026)

- [Arquitetura Zero Trust, grupos e critérios do Pentest B](../../../docs/seguranca/FASE3-ARQUITETURA-ZERO-TRUST-GRUPOS-RECURSOS.md)
- [Matriz de acesso Twingate e testes negativos](../../../docs/seguranca/FASE3-MATRIZ-ACESSO-TWINGATE.md)

**Atenção:** grupos da aplicação PHP (`usuario`, `empresa`, `admin`) não equivalem aos grupos Twingate (`TG-OPERACAO`, `TG-SEGURANCA`, `TG-ADMIN`, `TG-BACKUP`). O Twingate aplica ACL por endereço/porta, não isola caminhos `/admin` num mesmo IP:443 público. O acesso administrativo PHP só será classificado como privado quando um endpoint de rede distinto e uma regra de bloqueio da rota pública forem implantados e testados. Até então a defesa efetiva nessa área continua PHP RBAC/MFA/WAF.

A imagem de Connector ainda estava ausente e os gates NTP/CA/egress/tenant pendentes na evidência `EP126-F2-0014`. **Este documento não autoriza iniciar o Connector ou criar Resources sem cumprir esses gates.**
