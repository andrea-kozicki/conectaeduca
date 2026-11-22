# Conector Twingate da DMZ — EP125 (proposta, não homologado)

**Escopo:** novo contêiner isolado `conectaeduca-dmz-01`, sem portas publicadas, sem alterar `deploy/dmz/compose.yml`, sem reiniciar PHP/Nginx/WAF, sem configurar a EP126. O painel já contém o conector cadastrado na Remote Network **ConectaEduca - DMZ** e o Resource **ConectaEducaAPP** (`192.168.6.34`, TCP/443, UDP bloqueado, ICMP bloqueado). Conector ainda `Not yet connected`.

## Pré-requisitos / atenção
- Verificar se o serviço realmente responde em `192.168.6.34:443` **a partir da rede bridge do conector**, não apenas do host; o preflight do host não prova isso.
- Confirmar capacidade de CPU/RAM, saída para Twingate, DNS, TLS e regras institucionais. Sem necessidade de porta de entrada pública para o conector.
- O nome de `TWINGATE_NETWORK` é o identificador do **tenant** indicado nas instruções do conector no painel, **não** o nome da Remote Network. Copiar os tokens **do conector conectaeduca-dmz-01** diretamente no arquivo local protegido.
- Segredos nunca entram no Git, evidências, chats, comandos de shell com argumentos ou logs.
- `twingate/connector:1` usa tag de major; após homologação fixar digest imutável, com change control.
- Acesso público existente via WAF não é bloqueado pela criação do Resource. Decisão professor pendente.

## Execução EP125
```bash
cd /opt/conectaeduca
bash scripts/twingate/ce_twingate_dmz_preflight_deploy.sh --preflight
```
**Parar aqui e avaliar evidências.** Após aprovação do preflight e verificação de conectividade bridge→443, preparar segredo local:
```bash
cd /opt/conectaeduca
cp deploy/twingate/dmz/connector.env.example deploy/twingate/dmz/connector.env
chmod 600 deploy/twingate/dmz/connector.env
# Editar localmente com editor; nunca colar tokens no chat
```
Apenas após autorização explícita da execução:
```bash
bash scripts/twingate/ce_twingate_dmz_preflight_deploy.sh --deploy
```
Não usar `sudo -s`. Rollback limitado ao novo contêiner:
```bash
docker compose -f deploy/twingate/dmz/compose.yml down
```
**Não executar `docker compose down` no stack da aplicação.**

## Aceite
1. Conector `conectaeduca-dmz-01` aparece conectado no painel, sem segredos em evidências.
2. Recurso `ConectaEducaAPP` alcançável por identidade autorizada, com WAF/HTTPS preservados.
3. Identidade sem acesso negada; `Everyone` sem permissão.
4. Acesso direto pré-existente verificado e risco residual documentado, sem mudar firewall sem aprovação.
5. Disponibilidade PHP, Nginx, WAF e audit.log inalterada.

## Estado operacional observado em 04/11/2026 — CE-ZT15..25

O contêiner `conectaeduca-dmz-01` **já está instalado** na EP125 (1.95.0, Docker healthy, zero reinicializações); portanto, **não executar `--deploy`**. O script de implantação agora falha antes de qualquer alteração se detectar esse nome de contêiner, mesmo parado.

A API GraphQL Read only confirmou duas Remote Networks ativas, dois recursos e grupos associados às políticas `CE-PORTAL-MFA-1DIA` e `CE-SOC-MFA-1DIA`. Os Connectors `conectaeduca-dmz-01` (EP125) e `conectaeduca-interna-ep126` (EP126) apareceram `DEAD_HEARTBEAT_TOO_OLD` e não avançaram em três amostras de 20 segundos.

Os testes HTTPS `/time/0` para `pubsub.pubnub.com` e `h2.pubnubapi.com` retornaram **curl 35 / connection reset** em EP125 e EP126; o openSUSE externo retornou HTTP 200. `ps.pndsn.com` respondeu HTTP 200 nos testes. A causa da interrupção ainda não foi identificada; não atribuir ao pfSense nem à plataforma sem logs específicos. Não recriar Connectors nem gerar novas credenciais para tentar corrigir esse sintoma.

### Auditoria pela API em Fish, sem Terraform

No openSUSE, executar `python3 scripts/twingate/ce_twingate_reconcile.py` (solicita token **Read only**, oculto) ou adicionar `--json` para uma saída estruturada e sanitizada. Usa somente a biblioteca padrão Python. Não modifica o tenant e não grava segredos. Códigos: `0` esperado e online; `2` divergência cadastral; `3` pelo menos um Connector esperado offline. O script não prova isolamento nem substitui o teste positivo/negativo por identidade.

**Importante:** o grupo `CE-PENTESTB-LIMITADO` foi observado como acesso adicional ao portal; a auditoria o trata como **baseline observado, não como autorização definitiva**. Revalidar escopo antes da execução do Pentest B.

Prazos da fase: freeze 07/11, Pentest B 08–14/11, entrega 17/11. Continuidade operacional depende da rede institucional e dos gates de change control.
