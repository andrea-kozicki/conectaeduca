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
