# ZT-07.26 — Teste de autorização negativa de Wazuh por Twingate

**Data:** 02/11/2026 (BRT) · **Alvo:** Resource `ConectaEduca — Wazuh Dashboard` → `wazuh.dashboard` → EP126/host loopback TCP/443 · **Estado:** PLANO, AINDA NÃO EXECUTADO.

Este teste é de **Twingate Resource/Groups**, não de RBAC Wazuh e não da EP126 acessada localmente. Não mudar Compose, Connector, Wazuh, firewall, CA ou grupos da usuária autorizada para forçar um deny. Não usar um `curl` do host EP126 como prova do ZTNA: o backend de Wazuh ali deve ser acessível localmente.

## 1. Pré-condições observadas anteriormente (não repetir a investigação)

- EP126: Connector institucional `conectaeduca-twingate-connector` healthy/host, Wazuh Dashboard `127.0.0.1:443→5601`, HTTPS local 302.
- Twingate: Resource em Remote Network Interna, target `127.0.0.1`, alias `wazuh.dashboard`, somente TCP443; grupo autorizado `CE-SOC-OPERACAO`, política `CE-SOC-MFA-1DIA`; **nunca Everyone**.
- 31/10–01/11: openSUSE Client autenticado, `twingate auth` do Resource, CA pública SHA256 `68fa6e5bcdeaca4f4759932619887638594f26aff5b2269a7b833db49c498065` validada, `curl --cacert` HTTPS `HTTP=302 TLS_VERIFY=0`; Firefox exibiu login Wazuh.
- **Não** houve login efetivo no Wazuh nem identidade NEGADA comprovada.

## 2. Primeiro gate: autorização estática (painel Admin, sem mudar nada)

Na interface Twingate Admin, abrir **Resources → ConectaEduca — Wazuh Dashboard** e examinar `Access` / `Access Graph`, depois **Team → Groups** e **Team → Users**.

Registrar (capturas sanitizadas, sem emails completos, convites, tokens, códigos MFA):
1. Resource associado exclusivamente à Remote Network Interna, target `127.0.0.1`, alias `wazuh.dashboard`, somente protocolo TCP/443; confirmar ICMP e UDP sem permissão.
2. `Everyone` **não** associado. Grupos associados: esperado `CE-SOC-OPERACAO` (se aparecer outro, **não** afirmar deny para seus membros sem revisar).
3. Política `CE-SOC-MFA-1DIA` associada; lembrar que MFA condiciona acesso **apenas para identidades já autorizadas**.
4. Identificar **uma segunda identidade de teste realmente separada**, com conta no tenant e **sem pertencimento a nenhum grupo que conceda acesso** ao Resource. Não confundir `teste` do Bacularis/Wazuh com identidade Twingate; nomes de perfis da aplicação não criam usuário no Twingate.
5. Confirmar a segunda identidade como pessoa/conta de ensaio **autorizada** antes de conectar qualquer Client; não enviar convite/criar conta/alterar filiação sem decisão explícita.

Se não houver segunda identidade autorizada, classificar `NEGATIVE_IDENTITY=NOT_TESTABLE`, não simular deny com `twingate stop` da identidade autorizada e não retirar usuários da produção.

## 3. Gate de teste A/B — executar SOMENTE no(s) Client(s) Twingate

**A — identidade autorizada, no openSUSE previamente homologado:**

```bash
twingate status
twingate resources
# Se Resource mostrar Pending, renovar sua sessão sem mudar grants:
# twingate auth 'ConectaEduca — Wazuh Dashboard'
getent ahostsv4 wazuh.dashboard
curl --noproxy '*' --cacert "$HOME/Downloads/root-ca.pem" \
  --silent --show-error --output /dev/null --connect-timeout 8 --max-time 20 \
  --write-out 'HTTP=%{http_code} TLS_VERIFY=%{ssl_verify_result} CURL_RC_INTERNO=ver_saida_shell\\n' \
  https://wazuh.dashboard/
printf 'CURL_RC=%s\\n' "$?"
```

Esperado: Client online, Resource concedido, DNS virtual resolvido, HTTPS/TLS verificado `TLS_VERIFY=0`, HTTP 302 para login Wazuh. Página de login significa transporte OK; **não comprova login**.

**B — identidade NÃO autorizada, em Client Twingate próprio e autenticado, idealmente mesmo perfil de dispositivo/OS, sem mexer na conta A:**

```bash
twingate status
twingate resources
getent ahostsv4 wazuh.dashboard || true
curl --noproxy '*' --cacert "$HOME/Downloads/root-ca.pem" \
  --silent --show-error --output /dev/null --connect-timeout 5 --max-time 12 \
  --write-out 'HTTP=%{http_code} TLS_VERIFY=%{ssl_verify_result}\\n' \
  https://wazuh.dashboard/
printf 'CURL_RC=%s\\n' "$?"
```

Esperado: Client autenticado com **identidade B confirmada**, Resource não acessível na lista de concessões, HTTPS não alcança a tela Wazuh por essa identidade. Pode ocorrer falha DNS ou timeout conforme a configuração; **código de curl isolado não prova política deny**. Correlacionar com Access Graph/grupos e, quando disponíveis, eventos auditáveis no painel Twingate. Se outro endereço público/direto resolve ao mesmo serviço, isso é um risco distinto que deve ser documentado.

> Os comandos em B são de observação, não tentam burlar a política e não exigem login no Wazuh. Não usar IP do Connector `192.168.6.50`, `127.0.0.1` ou DNS fixado manualmente como substituto do alias para validar Resource por usuário.

## 4. Critérios de aceite e falha

| Controle | Exigência | Estado 02/11 |
|---|---|---|
| Positivo A | HTTPS 302/TLS0 por usuário/grupo autorizado | **PASS histórico 01/11**, opcional repetir apenas para A/B pareado |
| Negativo B | Conta Twingate independente sem grants + conexão rejeitada | PENDENTE |
| Prova de grupo | Resource grupos restritos, `Everyone` ausente, B não em grupos autorizados | PENDENTE VERIFICAÇÃO |
| Auditoria | Evidência de sessão/teste de acesso sem PII/tokens/OTP | PENDENTE |
| Login Wazuh | Autenticar no Wazuh como usuário permitido e verificar RBAC do produto | PENDENTE e **fora do teste negativo ZTNA** |
| Portas extras | Twingate TCP/443 apenas, sem grants imprevistos | PENDENTE REVIEW |

**Se B não puder ser disponibilizada, não alterar produção para criar evidência:** `ZT07_NEGATIVE=NOT_TESTABLE_MISSING_IDENTITY`. Manter ZT-07 em progresso. Não confundir `not-running` ou ausência de rede com proibição por grupo.

## 5. Evidências e rastreabilidade

Capturas sanitizadas: Resource (endereço/porta/política), Access Graph, membership A/B, `twingate resources` nas duas identidades, `curl` somente códigos e resultado TLS. Não publicar emails completos, credenciais, token Connector, URL MFA, sessão, CA privada ou detalhes de dispositivo pessoal. Relacionar aos registros ZT-07.20/25 e PR #214.

**Próximo passo imediato enquanto a responsável ainda está na EP126:** abrir o painel Twingate Admin no navegador, verificar Resource, Access Graph e Groups, e informar se existe segunda conta Twingate de teste **já autorizada**. Não executar teste de grupo no terminal do host EP126.
