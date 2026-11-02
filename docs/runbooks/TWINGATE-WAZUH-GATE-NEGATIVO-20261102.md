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


## 8. ZT-07.26C — Controle positivo funcional do recurso APP no Android (02/11, 16h51 BRT)

**Origem:** captura de tela fornecida pela responsável em chat, não anexada ao GitHub. No mesmo Android utilizado na tentativa negativa de 16h48, em rede móvel **5G**, com Twingate reportado conectado, o navegador acessou `192.168.6.34` e exibiu a página inicial pública da aplicação **ConectaEduca**: logotipo, navegação e ações `Entrar` / `Criar conta`.

**Resultado:** `ZT07_26C_ALLOWED_APP_HTTP=PASS` (carregamento funcional da UI); `ZT07_26B_WAZUH_NOT_REACHABLE=OBSERVED` (alias `wazuh.dashboard` não resolvido no mesmo contexto de identidade B). Recursos no painel Admin: identidade Gmail/Linux possui APP+Wazuh; Hotmail/Android possui só APP; `CE-SOC-OPERACAO` tem 1 usuário, Wazuh com política `CE-SOC-MFA-1DIA`, TCP443, UDP/ICMP bloqueados.

**Aceite do cenário:** `ZT07_26_ACCESS_SEGREGATION=PASS_WITH_SCOPE`: evidência cruzada de Resource APP permitido/funcional e Resource Wazuh não concedido/não alcançado pela identidade B. A conclusão ficou **mais forte que a falha DNS isolada**, porque a mesma conexão alcançou o Resource APP.

**Limites do aceite:** a captura mostra carregamento da página web, **não** login PHP ou RBAC; sem logs de fluxo/protocolo não afirmar que conexão TCP com Wazuh foi bloqueada na camada de pacotes, nem bloquear todas as rotas laterais. A captura exibe IP privado RFC1918 em 5G com Client Twingate conectado, consistente com rota pelo túnel, mas não há packet capture provando o caminho exato. Não afirmar login Wazuh, logs de auditoria de tentativa negada, nem cobertura dos demais PAs. Dispositivos diferentes (Android para B, openSUSE para A) são uma limitação metodológica.

**Próximos gates ZT-07 distintos:** (1) login autorizado no Wazuh e RBAC nativo, caso exista conta de teste; (2) conciliar auditoria/políticas de acesso com os logs administrativos sem PII; (3) verificar isolamento de rotas/portas adicionais conforme escopo Pentest B. **Não repetir o A/B sem mudança causal**.

**Mudanças operacionais:** nenhuma em EP125/EP126/Connector/Resource/Group/Policy/firewall.


## 9. Reconciliação de evidências ZT-07.25–29 de 01/11/2026 — **não repetir login/RBAC**

**Correção documental em 02/11:** a interpretação anterior deste runbook, que classificava login no Wazuh e verificação de RBAC como `PENDING`, ficou desatualizada. O histórico da sessão de **01/11/2026** e o relatório acadêmico `Daily9_ConectaEduca_v33_Evidencias_Wazuh_01-11-2026.docx` já documentam:

| Gate | Observado em 01/11 | Status |
|---|---|---|
| ZT-07.25/26 | Twingate Resource autorizado e conta `teste` autenticada no Wazuh, Dashboard exibido | PASS, escopo login e interface |
| ZT-07.27 | Papéis da conta `teste` verificados: `own_index`, `kibana_user`, `readall`; backend roles `kibanauser`, `readall` | PASS, leitura de permissões |
| ZT-07.28 | Conta `teste` em Users, Roles, Policies, Roles mapping → `You have no permissions` | PASS, negativa para as quatro áreas |
| ZT-07.29 | Conta `admin` acessou as mesmas quatro áreas | PASS, positiva administrativa |

**Limite:** a comparação demonstra segregação Wazuh **nas quatro interfaces testadas**; não implica revisão exaustiva de ações, APIs, objetos, RBAC, auditoria ou criação de usuário. Os privilégios administrativos da conta `admin` não são uma recomendação de uso para o usuário final.

Assim, **não solicitar novamente captura do login Wazuh, tela Dashboard ou roles mapping** sem alteração causal ou lacuna específica. O gate distinto **ZT-07.26B/C de 02/11**, no Android sob segunda identidade Twingate, comprova visibilidade segregada (Wazuh ausente/inacessível e ConectaEducaAPP acessível), com os limites DNS/transportes já descritos na seção 8.

**Pendências ainda reais:** telemetria/auditoria detalhada dos controles, decisão final de reconciliação Git ↔ runtime/rollback do Connector, e testes de rede não cobertos pela comparação. Não reinterpretar o resultado de outro dispositivo como teste de regras locais do Wazuh.

*Nota de rastreabilidade:* esta seção atualiza as interpretações históricas das seções anteriores que diziam 'login Wazuh PENDENTE'; a prova primária está no diário/chat e no documento Daily9 v33 citado. Não copiar credenciais nem capturas privadas para o Git.


## 10. ZT-07.30 — Auditoria de conexão no Twingate Admin Console — 02/11/2026

**Evidências:** quatro capturas da página Network → Overview → Recent Activity, apresentadas pela operadora no chat. As imagens brutas **não** foram anexadas ao repositório devido a identificadores e IPs públicos. A página exibiu **2 Active Devices, 2 Resources Online, 2 Remote Networks Online, 2 Users (1 Admin, 1 Member)** e o painel `Connection History` com atividade recente.

### Evento A — Android / Resource ConectaEducaAPP

- Conta de teste B (Hotmail), dispositivo Android, Resource `192.168.6.34` (`ConectaEducaAPP`), TCP/443, Remote Network `ConectaEduca - DMZ`.
- `Connection Type=Relay`; duração exibida de **1 minuto**.
- Cadeia de eventos observada na UI: `requested 192.168.6.34` → `Relay patched connection` → `Connector received request` → `192.168.6.34 connection established` → `connection closed`.
- **Connector registrado pela UI:** `conectaeduca-dmz-01`. Este nome atesta que o painel atribuiu a conexão a esse Connector. **Não comprova, isoladamente, em qual host/contêiner ele está efetivamente implantado**. Não marcar PR #213 como implantada exclusivamente com base no nome.
- `ZT07_30_APP_NETWORK_EVENT=PASS`: log positivo do Twingate compatível com captura Android da UI ConectaEduca carregada em 5G no mesmo intervalo.

### Evento B — Linux / Resource Wazuh

- Conta autorizada A (Gmail), dispositivo Linux Laptop, Resource `wazuh.dashboard`, TCP/443, Remote Network `ConectaEduca - Rede Interna`.
- `Connection Type=Relay`; duração exibida **inferior a 1 segundo**.
- Sequência: request → Relay → Connector → `wazuh.dashboard connection established` → closed.
- **Connector registrado:** `conectaeduca-interna-ep126`.
- `ZT07_30_WAZUH_NETWORK_EVENT=PASS` para conexão de transporte; a conexão registrada **não é, sozinha, prova de login Wazuh ou MFA** (cobertos por outras evidências).

### Conclusões e limites

- `ZT07_30_POSITIVE_NETWORK_AUDIT=PASS` para as **duas conexões autorizadas**: logs contêm identidade, cliente, Resource, TCP/443, Remote Network, Connector, cadeia de conexão e duração.
- `ZT07_26_ACCESS_SEGREGATION=PASS_WITH_SCOPE` permanece corroborada por evidência de painel/grupos, Android com APP listado e funcional, Wazuh ausente e mensagem de hostname não encontrado. **Não foi apresentada entrada explícita 'Wazuh denied' para identidade B**. A não visibilidade pode impedir tentativa de fluxo e não se deve inferir que evento de negativa necessariamente exista.
- **Não afirmar** que todos os acessos ao Wazuh/APP foram auditados, nem que Relay seja o único caminho, nem que Twingate substituiu firewall, WAF, restrições leste-oeste ou RBAC.
- A tela de `Connection History` em 30 dias e `Recent Activity` comprova **observabilidade positiva**, mas não comprova política de retenção futura nem exportação/auditoria administrativa de alterações de grupo.
- Os conectores de DMZ e Interna aparecem no painel com nomes distintos. Isso **exige reconciliação com o runtime real da EP125/EP126** antes de atualizar o estado de implantação no relatório ou fazer merge da PR #213. Não reiniciar/recriar serviços apenas para descobrir a localização.

**Próximo gate ZT-07.31:** conferir se o painel Admin oferece registros de **mudança de grupos/políticas** (control plane), diferenciando-os de Network Events (data plane), sem alteração operacional. Em paralelo, registrar metadados mínimos do Connector da DMZ em revisão Git/host autorizado, **sem inventário geral nem deploy**.


## 11. ZT-07.31 — Disponibilidade do relatório administrativo (02/11, 17h BRT)

A responsável apresentou captura do Twingate Admin Console em **Settings → Reports → Audit Logs**, com `Audit Logs 0` e controle `Generate Audit Logs Report`; a página também exibe as abas `User Activity`, `Network`, `Device List` e `AI Usage`.

- `ZT07_31_AUDIT_EXPORT_AVAILABLE=PASS` para presença da opção de exportação na interface.
- `AUDIT_LOGS_REPORT_COUNT=0`: nenhum relatório exportado/listado nesta aba; **não** significa zero eventos de auditoria na origem.
- `ZT07_31_EVENT_CONTENT=NOT_VERIFIED`: nenhuma exportação executada, nenhum evento administrativo analisado. A captura não prova alterações de grupo, políticas ou MFA registradas no período.
- Próximo passo não destrutivo: abrir `Generate Audit Logs Report` para conferir o seletor de período/categoria, **sem confirmar a criação** antes de revisar escopo e possíveis dados pessoais. Categorias candidatas para 30/10–02/11/2026: `Users & Groups`, `Network`, `Policies`, `MFA Configurations`. O relatório administrativo é diferente dos eventos de tráfego já comprovados no ZT-07.30.
- Se for autorizado gerar a exportação, guardar `*.gz` JSON original sob custódia privada e produzir **somente sumário sanitizado** (tipos, contagens, horários aproximados, sem IDs, emails, IPs públicos, tokens e antes/depois que exponha identidades) para GitHub/Trello. Timestamps de exportação são UTC e seleção na interface segue fuso local, conforme documentação oficial.
- Nenhuma alteração em VMs, Connector, ACLs ou políticas nesta etapa.

Referência: documentação oficial Twingate `/docs/admin-console-export` e `/docs/audit-logs`.


## 12. ZT-07.31A — Exportação real de Audit Logs / Access — 02/11/2026

**Fonte primária:** relatório de auditoria em `.gzip` fornecido pela responsável no chat e analisado localmente. Captura da interface **Settings → Reports → Audit Logs** mostra relatório de tipo **Access** para período **30/10–02/11/2026**. **Não publicar o gzip original**: contém e-mail, nome, IP de origem e identificadores internos de atores, recursos e concessões.

**Formato observado:** GZIP contendo **4 linhas JSON independentes** (JSONL; não é array JSON único). Cada linha tem `version`, `time`, `actor`, `action`, `targets`; todas as entidades de `targets` são do tipo `Access` e todos os atores são `user`. Apenas os metadados abaixo foram preservados; e-mail, IP público, UUID/IDs, endereços e identificadores de cliente foram suprimidos.

| Timestamp UTC | Data/hora BRT | Ação | Recurso | Principal (grupo) | Política observada |
|---|---|---|---|---|---|
| 2026-10-30 23:19:37 | 30/10 20:19:37 | `create` | `Address` | `CE-PORTAL` | campo ausente |
| 2026-10-30 23:35:01 | 30/10 20:35:01 | `edit` | `ConectaEducaAPP` | `CE-PORTAL` | targets de edição incluem uma representação sem `policy` e uma com `Default Policy` |
| 2026-10-31 23:26:24 | 31/10 20:26:24 | `create` | `ConectaEduca — Wazuh Dashboard` | `CE-SOC-OPERACAO` | `CE-SOC-MFA-1DIA` |
| 2026-11-02 16:44:01 | 02/11 13:44:01 | `create` | `ConectaEducaAPP` | `CE-PENTESTB-LIMITADO` | campo ausente |

**Interpretação:**
- `ZT07_31_ACCESS_EXPORT_READ=PASS`: export real contém 4 eventos `Access`, não zero eventos. O número `1` na aba representa o relatório gerado, não a quantidade de eventos.
- `ZT07_31_WAZUH_GRANT_AUDITED=PASS`: há registro de criação da concessão Wazuh ao grupo SOC com política MFA, coerente com o Resource/Admin Console e o acesso pelo Linux no ZT-07.30.
- `ZT07_31_LIMITED_APP_GRANT_AUDITED=PASS`: consta criação de concessão APP ao grupo limitado, mas isto **não prova** testes de permissões PHP/RBAC nem qual pessoa está no grupo.
- `ZT07_31_CE_PORTAL_EDIT=OBSERVED_UNDERSPECIFIED`: o evento `edit` contém duas representações do acesso (`policy` ausente e `Default Policy`); **não inferir direção (antes/depois)** sem contrato formal da exportação.
- `AUDIT_EXPORT_SCOPE=ACCESS_ONLY`: **não provar** por este arquivo criação/edição dos Resources, cadastro de usuários, membership de grupos, alterações globais de política, desafios de MFA, logins, tentativas negadas ou conexões TCP. As duas conexões positivas pertencem à evidência Network/Recent Activity da ZT-07.30, não a este gzip.
- Nenhuma alteração operacional: relatório gerado/exportado no painel; nenhuma mudança em recursos/grupos/políticas, EP125/EP126, Connectors ou firewall.

**Custódia:** original permanece arquivo privado da responsável; relatórios publicados apenas em formato sanitizado. Não subir `.gzip` completo nem campos `actor.info`, `actor.ip`, `id`, `principal.id` ou `resource.id` ao GitHub/Trello.

**Status:** `ZT07_31_ADMIN_AUDIT=PASS_WITH_SCOPE` para a rastreabilidade das **concessões de acesso**. Auditoria de todos os eventos administrativos do tenant ainda não demonstrada.
