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
  --write-out 'HTTP=%{http_code} TLS_VERIFY=%{ssl_verify_result}\n' \
  https://wazuh.dashboard/
printf 'CURL_RC=%s\n' "$?"
```

Esperado: Client online, Resource concedido, DNS virtual resolvido, HTTPS/TLS verificado `TLS_VERIFY=0`, HTTP 302 para login Wazuh. Página de login significa transporte OK; **não comprova login**.

**B — identidade NÃO autorizada, em Client Twingate próprio e autenticado, idealmente mesmo perfil de dispositivo/OS, sem mexer na conta A:**

```bash
twingate status
twingate resources
getent ahostsv4 wazuh.dashboard || true
curl --noproxy '*' --cacert "$HOME/Downloads/root-ca.pem" \
  --silent --show-error --output /dev/null --connect-timeout 5 --max-time 12 \
  --write-out 'HTTP=%{http_code} TLS_VERIFY=%{ssl_verify_result}\n' \
  https://wazuh.dashboard/
printf 'CURL_RC=%s\n' "$?"
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

## 5. Evidência estática do Admin Console recebida em 02/11 (ZT-07.26-pre)

Quatro capturas enviadas pela responsável em chat, **não anexadas ao Git**:

- Resource `ConectaEduca — Wazuh Dashboard`: `127.0.0.1`, alias `wazuh.dashboard`, modo Manual Access, Security Policy `CE-SOC-MFA-1DIA`, tipo IP Network, TCP `[443]`, UDP/ICMP bloqueados, grupo `CE-SOC-OPERACAO` listado. **Não apareceu associação `Everyone` na captura do Resource**; checar outros grants no Access Graph para aceitar exclusividade.
- Grupo `CE-SOC-OPERACAO` possui **1 user**; tem o Resource Wazuh na lista.
- Identidade A (provedor Gmail, Linux Laptop): cartão de usuário no Admin Console apresenta Resources ConectaEducaAPP **e Wazuh**, compatível com a pertença SOC.
- Identidade B (provedor Hotmail, Android Mobile): cartão de usuário no Admin Console apresenta **somente ConectaEducaAPP**. Isso sugere ausência de grant ao Wazuh, mas não comprova sessão ativa no Android nem tentativa de conexão negada. As duas contas são identidades Twingate separadas, ainda que representem a mesma operadora; para teste acadêmico, registrar essa limitação de independência humana.

**Estado comprovado:** `RESOURCE_TCP443=CONFIGURADO`, `A_HAS_WAZUH=SIM`, `B_WAZUH_NOT_LISTED=SIM`. **Não afirmar** `B_CONNECTION_DENIED=PASS` sem evidência do Android. Não confundir permissões do Admin Console (Gmail identificada como Admin) com o acesso aplicacional Wazuh. A ausência de recurso no cartão de B é melhor indício de ACL do que erro de DNS isolado.

**Teste operacional mínimo Android (sem alterações):**

1. No Android, abrir o **Twingate Client**, confirmar que o Client está *Connected/Online* e autenticado como a identidade B. Se estiver com outra conta ou offline, não interpretar erro de browser como deny por ACL.
2. Conferir a lista de Resources: ConectaEducaAPP disponível e Wazuh ausente. Se o produto ocultar recursos em Background/Hidden Resources, confirmar ausência também ali.
3. Com Client B conectado, no navegador do mesmo Android abrir **exatamente** `https://wazuh.dashboard/`; registrar resultado e horário (sem credenciais nem capturar informações pessoais).
4. Se aparecer a **tela de login do Wazuh**, o teste NEGATIVO FALHOU (investigar grants, outra rota, cache/sessão/conta); não tentar autenticar. Se houver erro de nome não encontrado ou conexão indisponível e o Client permanecer conectado, a observação é **compatível com deny**; corroborar recurso ausente em lista, grupo B e configuração do recurso. Erro TLS/certificado não conta como deny (pode indicar que o serviço foi alcançado).
5. Não usar `127.0.0.1` do telefone, não adicionar `hosts`, não usar `-k`, nem autenticar o cliente A no Android. Preservar a sessão do Linux.

**Limites:** o Android e o Linux são dispositivos diferentes; outras VPNs/DNS locais podem interferir. Um teste A/B no mesmo dispositivo seria mais forte, mas não justifica mexer em acesso da conta A ou reutilizar credenciais indevidamente. Logs de **acesso negado** podem não existir no Twingate porque o Client desconhece Resources não autorizados; não assumir que ausência de log equivale a ausência de teste.

## 6. Evidências e rastreabilidade

Capturas sanitizadas: Resource (endereço/porta/política), Access Graph, membership A/B, `twingate resources` nas duas identidades, `curl` somente códigos e resultado TLS. Não publicar emails completos, credenciais, token Connector, URL MFA, sessão, CA privada ou detalhes de dispositivo pessoal. Relacionar aos registros ZT-07.20/25 e PR #214.

**Próximo passo imediato enquanto a responsável ainda está na EP126:** abrir o painel Twingate Admin no navegador, verificar Resource, Access Graph e Groups, e informar se existe segunda conta Twingate de teste **já autorizada**. Não executar teste de grupo no terminal do host EP126.


## 7. ZT-07.26B — Observação operacional no Android em 02/11/2026, 16h48 BRT

**Fonte:** duas capturas fornecidas pela responsável na conversa (tela Twingate Android e tela do navegador Android; não copiadas ao GitHub). Teste realizado em **5G**, portanto não se tratou de acesso direto à LAN do laboratório.

| Evidência | Resultado efetivamente observado |
|---|---|
| Cliente Twingate Android | Rede `Conectaeducalab` exibe **Connected** |
| Resource visível | `ConectaEducaAPP` / `192.168.6.34` exibido com ponto verde |
| Resource Wazuh | **Não aparece** na lista do Android |
| Navegador Android em `wazuh.dashboard` | Mensagem **“Endereço não encontrado”**, sem apresentar página de login Wazuh |
| Identidades do Admin Console (capturas anteriores) | Conta A (Gmail/Linux) tinha ConectaEducaAPP + Wazuh; conta B (Hotmail/Android) tinha somente ConectaEducaAPP; grupo SOC com 1 usuário |

**Interpretação fundamentada:**
- `RESOURCE_VISIBILITY_SEPARATION=PASS`: identidade B não tem Wazuh listado, ao contrário da A.
- `NEGATIVE_ACCESS_OBSERVED=YES`: na tentativa documentada, o navegador Android não chegou ao serviço.
- `POLICY_CAUSATION=CONSISTENT_NOT_ISOLATED`: recusa de resolução DNS é compatível com ausência de grant ao Resource, **mas isoladamente não prova que a política Twingate causou a falha**. Não houve diagnóstico isolado de DNS do dispositivo ou teste funcional positivo do Resource ConectaEducaAPP no mesmo momento.
- `ZT07_26B=PASS_WITH_QUALIFICATION` para o **cenário observado de não visibilidade e não alcance**. Não transformar em prova universal de deny para todos os protocolos/dispositivos.
- `WAZUH_APPLICATION_LOGIN=PENDING`; `TWIN_GATE_AUDIT_CORRELATION=PENDING`.

**Próximo passo mínimo para fortalecer a cadeia causal (sem mudar configuração):** confirmar que o Twingate Android permanece conectado à identidade B e que o Resource permitido `ConectaEducaAPP` é alcançável **via caminho autorizado**, na mesma rede móvel, enquanto Wazuh segue ausente/inacessível. Não divulgar credenciais, IP virtual pessoal ou capturas com emails completos. Se o teste positivo falhar, revisar conectividade/DNS antes de proclamar bloqueio por ACL.

**Restrições preservadas:** sem mudar grupos, Access Policy, dispositivo da identidade A, Connector EP126, Wazuh, pfSense, firewall, containers ou credenciais. Evidência do screenshot é observação do usuário, não medição reproduzida automaticamente pelo GitHub.
