# ConectaEduca — EP126 / Zero Trust — Consolidado das evidências de 31/10/2026

**Projeto:** Experiência Criativa 8 — Fase 3  
**Status:** Connector EP126 implantado e saudável; Wazuh Resource com MFA real concluído; caminho TLS alcançado, mas confiança CA ainda pendente.  
**Origem:** saídas CLI e capturas fornecidas pela responsável ao longo de 31/10/2026 (horário America/Sao_Paulo), confrontadas com as anotações versionadas da PR #214.  
**Natureza:** síntese documental retrospectiva; **não** constitui nova execução independente nas VMs. Nenhum segredo, token, código MFA, URL de autenticação individual ou chave privada foi copiado.

## 1. Arquitetura efetivamente observada

| Componente | Identificação / configuração | Evidência e limites |
|---|---|---|
| EP125 DMZ | Aplicação ConectaEducaAPP, endereço 192.168.6.34 | Resource separado da DMZ, não equivale ao Wazuh |
| EP126 interna | ep126-pucpr-br, 192.168.6.50 | Host do Connector institucional e Wazuh |
| Connector institucional | conectaeduca-twingate-connector / Twingate `conectaeduca-interna-ep126` | Docker Running=true; Health=healthy; Network=host; Restarts=0; painel Connected nas capturas |
| Connector pessoal openSUSE | `conectaeduca-interna-01`, previamente parado | Não foi reativado para estes testes; não confundir com Twingate Client |
| Twingate Client openSUSE | Twingate 2026.302.7126 / 0.198.0; `sdwan0=100.96.0.2/32` | `twingate status=online`; autenticação manual por `twingate auth` |
| Resource privado Wazuh | `ConectaEduca — Wazuh Dashboard`, Remote Network `ConectaEduca - Rede Interna` | Target `127.0.0.1`, alias `wazuh.dashboard`, TCP/443 único, UDP/ICMP bloqueados |
| Acesso | `CE-SOC-OPERACAO`, Resource Policy `CE-SOC-MFA-1DIA` | Grupo associado, `Everyone` não autorizado. Primeiro grupo tinha zero usuários; identidade de teste foi adicionada |
| Wazuh Dashboard | Docker `conectaeduca-wazuh-wazuh.dashboard-1` | Publicação host `127.0.0.1:443 -> container:5601/tcp`; HTTP 302 local para login |
| Certificados | CA pública `/opt/conectaeduca/deploy/interna/wazuh/.runtime/certs/root-ca.pem` | Montagem em Dashboard `/usr/share/wazuh-dashboard/certs/root-ca.pem`; cadeia ainda não validada no openSUSE |

## 2. Linha do tempo e saídas consolidadas

| ID | Onde | Teste/saída fornecida | Conclusão de evidência |
|---|---|---|---|
| ZT-06 | EP126/painel | Connector em Docker; Connected/healthy, RestartCount=0 | Implantação básica institucional comprovada; não é aceite E2E |
| ZT-07.1 | EP126 | Tentativas a serviço legado Graylog :9000 sem listener | Não se aplica à arquitetura atual, que usa Wazuh; não classificar como falha do ZT |
| ZT-07.2 | EP126 | Wazuh Docker Dashboard com `127.0.0.1:443 -> 5601/tcp`; HTTP 302 local | Serviço publicado apenas no loopback host; não exposto na LAN por este bind |
| ZT-07.3 | EP126 | Certificado `CN=wazuh.dashboard`, SAN DNS `wazuh.dashboard`; emissão Wazuh; ausência CA confiável | Certificado presente, confiança do cliente a resolver |
| ZT-07.4 | EP126 | `getent ahostsv4 wazuh.dashboard` sem resolução no host; `curl --resolve ... --insecure` HTTP 302 | Host não usa DNS desse alias; teste com `--resolve` não instala DNS nem valida TLS |
| ZT-07.5 | EP126 | Imagem Connector sem shell; `docker exec ... sh` não pôde realizar DNS lookup | Não afirmar que DNS no Connector foi testado |
| ZT-07.6 | EP126 | Diário local atualizado: marcador `CE-ZT076-ISOLAMENTO-VALIDADO-20261031`; SHA256 final `248b7e2c8d983e19741b07e62e6cc89c57a3f387411e156eb6d9439558b90b37`; backup `diario.md.bak.ZT076-20261031T201519` | Confirma isolamento do Connector pessoal e continuidade do Connector institucional; não alterou infra |
| ZT-07.7 | Painel | Resource Wazuh criado com grupo SOC, MFA 1 dia, target loopback e TCP/443 | Controle configurado; inicialmente ainda sem identidade no grupo |
| ZT-07.8 | openSUSE | Client inicialmente `not-running`; `twingate start`; depois `online`, mas só ConectaEducaAPP visível | O Client pessoal estava desligado. Aviso de outra VPN ativa não comprova conflito |
| ZT-07.9 | Painel | Grupo `CE-SOC-OPERACAO` inicialmente exibia `0 users` | Explicação para Resource Wazuh não aparecer na identidade inicial |
| ZT-07.10 | openSUSE | Após inclusão no grupo, `twingate resources` lista Wazuh; `getent ahostsv4 wazuh.dashboard` → `100.98.166.92` | Visibilidade do Resource e IP virtual do alias confirmados |
| ZT-07.10/11 | openSUSE | `curl https://wazuh.dashboard/`: timeout 5 s e 8 s, `RC=28`, `HTTP=000` | Falha de acesso antes da autorização adicional; `TLS_VERIFY=0` sem handshake **não** prova TLS válido |
| ZT-07.11 | EP126 | `hostname=ep126-pucpr-br`; Docker Connector `Running=true Health=healthy Network=host Restarts=0`; `curl --insecure https://127.0.0.1:443/` → `HTTP=302 IP=127.0.0.1` | Wazuh responde localmente; uso diagnóstico de `--insecure` não é homologação TLS |
| ZT-07.12 | openSUSE | `ip -4 route get 100.98.166.92` → `dev sdwan0 src 100.96.0.2`; outro túnel institucional ativo | A rota do IP virtual aponta ao Twingate; coexistência de VPNs não prova interferência |
| ZT-07.13/14 | openSUSE | `twingate resources` mostrou `Pending`; `twingate-notifier console` → `Additional authentication required`; Firefox falhou antes do login | Identidade autorizada no grupo, mas autenticação adicional do Resource pendente; aba isolada `127.0.0.1` no openSUSE não era o Wazuh |
| ZT-07.15 | openSUSE | `twingate auth 'ConectaEduca — Wazuh Dashboard'` → `Authentication successful`; `Auth expires in 23 hours` | **Autenticação adicional da sessão comprovada**; a política do painel exige MFA |
| ZT-07.16 | openSUSE | HTTPS sem `--insecure`: `curl RC=60`, `IP=100.98.166.92`, `TLS_VERIFY=20`, `unable to get local issuer certificate`, `HTTP=000` | Timeout superado, conexão chegou à validação TLS; cadeia emissora não confiável no cliente. Login não testado |
| **ZT-07.17** | **EP126** | Certificado servidor `CN=wazuh.dashboard`, SAN `DNS:wazuh.dashboard`, issuer Wazuh; fingerprint SHA256 abaixo; montagens da CA pública e do certificado identificadas | **Arquivo CA candidato identificado**; validação da CA e transporte seguro ainda pendentes |

### ZT-07.17 — Identidade do certificado servidor

- **Subject:** `C=US, L=California, O=Wazuh, OU=Wazuh, CN=wazuh.dashboard`.
- **Issuer:** `OU=Wazuh, O=Wazuh, L=California`.
- **Validade (UTC):** `2026-08-27 21:36:49` a `2036-08-24 21:36:49`.
- **SAN:** `DNS:wazuh.dashboard`.
- **SHA-256 fingerprint do certificado servido:** `DB:56:D8:D9:6C:08:90:E1:DB:72:27:46:06:F2:60:CD:F8:36:10:49:5E:BE:56:F5:14:CC:20:6B:1C:2D:BE:F0`.
- **CA pública candidata:** `/opt/conectaeduca/deploy/interna/wazuh/.runtime/certs/root-ca.pem`.
- **Certificado servidor:** `/opt/conectaeduca/deploy/interna/wazuh/.runtime/certs/wazuh.dashboard.pem`.
- **Chave privada:** existe na implantação, mas **não deve ser copiada, aberta ou anexada** ao pacote de evidências.

**Importante:** fingerprint de certificado servidor não é fingerprint da CA. A CA precisa de identificação, fingerprint e verificação de cadeia próprios.

## 3. Evidências com status atual

| Marco | Estado | O que ainda NÃO se demonstrou |
|---|---|---|
| Connector EP126 operacional | COMPROVADO | Não prova sozinho rota até cada serviço |
| Resource Wazuh mínimo TCP/443 | COMPROVADO CONFIGURADO | Não representa isolamento de outros serviços privados |
| Grupo SOC + política MFA | COMPROVADO CONFIGURADO | Teste de identidade sem permissão ainda não realizado |
| Desafio/autorização adicional | COMPROVADO | A política exige MFA e a operadora relatou configuração MFA; não copiar OTP |
| DNS virtual + encaminhamento TLS | COMPROVADO ATÉ CERTIFICADO | Sem resposta HTTP validada ainda |
| CA confiável no openSUSE | PENDENTE | `curl RC=60` e `TLS_VERIFY=20` |
| Login funcional e RBAC Wazuh | PENDENTE | Nenhum acesso à tela de login validada por cliente remoto |
| Teste negativo e logs | PENDENTE | Não houve ensaio de usuário excluído/sem acesso e relatório de eventos |
| Reconciliação Compose/runtime e rollback | PENDENTE | Digest fixado na `main` difere da versão efetiva; não recriar Connector saudável |
| Reteste de PA-01..PA-07 | FORA DESTE ACEITE | Executar somente na campanha autorizada de Pentest B |

## 4. Contagem de etapas restantes

### A. Para homologar **Twingate + Wazuh na EP126**: **4 gates**

1. **CA pública e TLS:** verificar a cadeia e o fingerprint da CA, transportar apenas a CA pública ao openSUSE por canal autorizado e executar `curl --cacert` sem alteração da confiança global; `HTTP=302` com validação TLS positiva é o primeiro aceite.
2. **Cliente/browser e funcionalidade:** após avaliar a necessidade de importar a CA no perfil Firefox, abrir `https://wazuh.dashboard/`, obter a página de login e efetuar um login autorizado de teste. Preservar RBAC do Wazuh.
3. **Acesso negativo e trilha de eventos:** validar identidade autorizada e identidade sem grupo, MFA/expiração, proteção de porta, eventos no painel Twingate e ausência de acesso indevido. Não usar `Everyone`.
4. **Reconciliação e aceite:** confrontar Compose, override local e digest do Connector EP126 sem reinício automático; descrever plano de rollback, custódia dos tokens, dependências e testes; atualizar diário local com backup, marcador e novo SHA-256; revisar PRs e Trello.

### B. Para cobertura **Zero Trust ampliada da EP126**: **mais 2 frentes condicionais**

5. **Recursos privados adicionais por papel:** somente se exigidos pelo escopo aprovado, proteger SSH/Bacularis/OpenBao ou outras interfaces administrativas com endereços/portas mínimos e política própria. Requer validar listeners e dependências institucionais antes de alterar firewall.
6. **Comparação pós-Zero Trust / Pentest B:** aplicar testes autorizados de acesso permitido/negado, tentativa de movimento lateral e observabilidade; separar controles ZTNA dos riscos leste-oeste não cobertos por Twingate. Consolidar relatório final.

**Resumo:** 4 gates para homologação da integração atual; até 6 frentes para cobertura ampliada. Não equivalem a seis operações de deploy.

## 5. Próximo comando seguro na EP126 — somente leitura

```bash
CA="/opt/conectaeduca/deploy/interna/wazuh/.runtime/certs/root-ca.pem"
CERT="/opt/conectaeduca/deploy/interna/wazuh/.runtime/certs/wazuh.dashboard.pem"

echo "=== CA PUBLICA — METADADOS ==="
if [[ -r "$CA" && -r "$CERT" ]]; then
  openssl x509 -in "$CA" -noout -subject -issuer -fingerprint -sha256 -ext basicConstraints
  echo "=== VERIFICAR CERTIFICADO / HOSTNAME ==="
  openssl verify -CAfile "$CA" -verify_hostname wazuh.dashboard "$CERT"
  echo "=== HASH DO ARQUIVO PUBLICO CA ==="
  sha256sum "$CA"
else
  echo "CA_OU_CERT_NAO_LEGIVEL_PELA_CONTA_ATUAL"
fi
echo "ALTERACOES=NAO"
```

Se não houver permissão, **não** abrir sessão root nem mudar modos ACL; planejar exportação do certificado público via Docker em etapa separada. Após verificação, planejar transferência autorizada da CA pública para ensaio local `curl --cacert`; não importar no trust store global por antecipação.

## 6. Rastreabilidade e custódia

- Diário local da EP126: `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md`. Último hash local confirmado neste recorte: `248b7e2c8d983e19741b07e62e6cc89c57a3f387411e156eb6d9439558b90b37` (ZT-07.6). Entradas posteriores nesta síntese são **documentais no GitHub**, não inserções comprovadas no diário local.
- GitHub: PR #214, branch `docs/twingate-evidencias-20261031`; PR #215 dos kits operacionais continua DRAFT e não prova reconciliação efetiva de runtime.
- Trello: cards ZT-06 (Connector institucional) e ZT-07 (Resources/MFA), permanecem em andamento até os gates finais.
- Os screenshots originais e saídas de terminal foram fornecidos pela operadora no chat; hashes individuais de screenshots não estão documentados aqui. Não inventar horários exatos de comandos sem carimbo de tempo.
- Não publicar certificados/CA dentro do Git por padrão; mesmo certificado público requer custódia aprovada. Nunca publicar chave privada, segredos de Compose ou tokens Twingate.

**Critério de fechamento:** HTTPS com CA confiável + acesso real Wazuh + identidade permitida/negada + reconciliação controlada + rastreabilidade do diário. Até lá: `ZT-EP126 = PARCIALMENTE HOMOLOGADO`.

## ZT-07.18C — validacao local da cadeia Wazuh concluida (PASS)

Saída fornecida pela responsável na EP126 (execução por `bash <<'BASH'`, subprocesso, sem encerramento do shell): `root-ca.pem` público em `~/CE-ZT0718B.DxuqlyrH/` inspecionado por OpenSSL: `subject=OU=Wazuh,O=Wazuh,L=California`; `issuer` idêntico; Basic Constraints crítico `CA:TRUE`; fingerprint SHA-256 da **CA** `EE:68:D3:51:A4:AE:B9:49:D3:34:68:82:D6:9B:33:89:75:15:18:4E:6B:C9:19:36:7F:22:21:70:BF:D9:EB:A5`. Certificado servidor público capturado via `openssl s_client -connect 127.0.0.1:443 -servername wazuh.dashboard` para `~/CE-ZT0718B.DxuqlyrH/wazuh-apresentado.pem`; fingerprint igual à coleta ZT-07.17: `FINGERPRINT_CORRESPONDE=SIM` (`DB:56:D8:D9:6C:08:90:E1:DB:72:27:46:06:F2:60:CD:F8:36:10:49:5E:BE:56:F5:14:CC:20:6B:1C:2D:BE:F0`).

`openssl verify -CAfile root-ca.pem -verify_hostname wazuh.dashboard wazuh-apresentado.pem` retornou `wazuh-apresentado.pem: OK`, `OPENSSL_VERIFY_RC=0`, `VALIDACAO_CA_LOCAL=PASS`. SHA-256 dos **arquivos** (diferente de fingerprint X.509): `root-ca.pem`: `68fa6e5bcdeaca4f4759932619887638594f26aff5b2269a7b833db49c498065`; `wazuh-apresentado.pem`: `29c6dc3b0a49a17f04dfafae034700d300cb9dfb12ba03083d4a05de8bc7117f`. Impressões digitais CA e servidor são objetos diferentes.

**Limites:** assinatura/nome do certificado efetivamente servido no loopback EP126 validados com CA pública. Isto ainda não comprova trust store no openSUSE, resposta HTTPS via Client Twingate, Firefox/login Wazuh nem acesso negado a identidade não autorizada. Nenhum serviço/certificado original foi alterado. Próximo gate: transferir somente CA pública por meio autorizado, comparar SHA-256 do arquivo no openSUSE e testar `curl --cacert <CA local> --noproxy '*' https://wazuh.dashboard/` sem `-k`, sem importar CA globalmente. Diário local da EP126 ainda não atualizado automaticamente.


## Atualizacao ZT-07.20 — HTTPS remoto com CA aprovada

Teste pelo openSUSE do endpoint Wazuh via Client Twingate com `curl --cacert` usando a CA pública transferida: resposta `HTTP=302 IP=100.98.166.92 TLS_VERIFY=0` e `CURL_RC=0`. Conectividade HTTPS com validação de cadeia e hostname confirmada; o retorno 302 é um redirecionamento do serviço, ainda sem `Location` registrado neste teste. Falta conferir SHA-256 do arquivo transferido no cliente (não informado nessa saída), instalar confiança apenas no navegador quando aprovado, efetuar login no Dashboard e testar negativas de identidade/permissão e auditoria. **Gate 1/4 concluído; restam 3 gates para aceitação da integração Wazuh; escopo ampliado de outros serviços e pentest ainda independente.**


## Fechamento gerencial e referências canônicas — 31/10

O ciclo do dia foi encerrado com ZT-07.20: `curl --cacert ~/Downloads/root-ca.pem https://wazuh.dashboard/` pelo openSUSE e Client Twingate retornou `HTTP=302`, `IP=100.98.166.92`, `TLS_VERIFY=0`, `CURL_RC=0`. Assim, o **gate TLS/HTTPS remoto está PASS**, após `Authentication successful` do Resource e `openssl verify ... = OK` na EP126. **Não foram comprovados** login pelo Firefox, negação de acesso por outra identidade, trilha completa de eventos, reconciliação efetiva Git/runtime ou atualização do diário local EP126. Hash do arquivo CA no destino ainda aguarda saída de verificação independente; na EP126 o SHA-256 de `root-ca.pem` era `68fa6e5bcdeaca4f4759932619887638594f26aff5b2269a7b833db49c498065`.

**Plano enxuto e decisões para EP125, EP126 e suporte pfSense:** [Fechamento operacional de 31/10](FECHAMENTO-OPERACIONAL-20261031-E-PLANO-ENXUTO.md). O foco mudou para 1 pacote validado por VM (preflight/revisão de diff/rollback/postcheck), 1 solicitação única ao suporte pfSense com decisão público×privado/NAT/regras LAN49, e testes guiados pelos sete PAs. PRs de documentação/código continuam draft; nenhuma VM foi modificada por este fechamento GitHub e nenhum item deve ser assinalado DONE sem critérios de aceite.


## ZT-07.25 — Firefox: tela de login Wazuh acessível via Twingate (01/11/2026)

A operadora comprovou no openSUSE que o arquivo CA público transferido corresponde a `SHA256 68fa6e5bcdeaca4f4759932619887638594f26aff5b2269a7b833db49c498065`. Após criar o perfil Firefox `ConectaEduca-Lab`, a navegação inicial em `wazuh.dashboard` mostrou `Servidor não encontrado`. Investigação revelou **Twingate Client `not-running`**, `getent ahostsv4 wazuh.dashboard` vazio e `curl (6) Could not resolve host` — causa confirmada, distinta de TLS/Firefox. Depois de executar `twingate start`, `twingate resources` exibiu `ConectaEducaAPP` autorizado por 4 dias e `ConectaEduca — Wazuh Dashboard` como **`Pending`**; `getent` passou a resolver IP virtual `100.110.213.17`, mas `curl (28)` expirava. Após orientar autenticação específica via `twingate auth 'ConectaEduca — Wazuh Dashboard'`, a usuária enviou captura do **Firefox exibindo logo Wazuh e formulário Username/Password/Log in** no endereço `wazuh.dashboard/app/login?`. **PASS para acesso à interface de login pelo navegador e evidência visual.** Não foi apresentada saída textual pós-autenticação, portanto não atribuir horário ou duração precisa da nova sessão; tampouco afirmar login Wazuh, consulta a alertas, deny de outro usuário ou audit E2E. DNS sobre HTTPS do Firefox já estava desativado por padrão, **não era a causa**.

**Procedimento de retomada permanente:** [`docs/runbooks/TWINGATE-OPENSUSE-WAZUH-ACESSO-RAPIDO-20261101.md`](../runbooks/TWINGATE-OPENSUSE-WAZUH-ACESSO-RAPIDO-20261101.md). O runbook diferencia Client/Connector, autenticação por Resource, perfil dedicado do Firefox, CA, comandos de diagnóstico e árvore de decisão por erro. O Connector EP126 e os containers não foram modificados. **Escopo pendente:** login de teste na aplicação Wazuh, controle negativo de identidade, correlação de logs, revisão de configuração/reconciliação e atualização do diário **local** na VM.


## ZT-07.26 — Login aplicacional Wazuh `teste` (01/11/2026)

A responsável enviou captura de tela do Firefox (arquivo recebido no chat `image(20261101-165833).png`), após a orientação de autenticar-se como usuário de aplicação `teste`, mostrando **Dashboard Wazuh Overview renderizado e sessão autenticada**, com avatar `t`, em `wazuh.dashboard/app/wz-home#/overview/`. Classificar **ZT-07.26 PASS: login e apresentação do painel**, com identidade `teste` informada pelo fluxo da operadora (a captura isoladamente não revela o username completo). **Não classificar RBAC como PASS:** a tela não comprova permissões efetivas de leitura/administração e não há teste de operação administrativa negada; não houve teste de identidade sem grupo no Twingate. Foto indica em seu intervalo `Last 24 Hours Alerts`: Critical 0, High 0, Medium 81, Low 404 (total 485); resumo `Active (1)`, `Disconnected (1)`. Esses números são observação de painel no momento da coleta, não evidenciam causa do agente desconectado ou incidentes. Próximo teste seguro: inspecionar, **sem alterar configuração**, os papéis atribuídos ao usuário teste e tentar acessar apenas uma área administrativa em modo leitura para documentar permissão/negação, sem salvar mudanças. Não publicar credenciais nem códigos MFA. Evidência de imagem disponível no chat, não commitada no repositório. Nenhuma VM, conector ou pfSense modificados neste gate.


## ZT-07.27 — papéis da sessão `teste` no Dashboard (01/11/2026)

Captura recebida da sessão autenticada no Wazuh Dashboard `wazuh.dashboard`, usuário `teste` confirmado no menu anterior, aberta a opção **View roles and identities**. Roles efetivos **(3)** exibidos: `own_index`, `kibana_user`, `readall`. Backend roles **(2)**: `kibanauser`, `readall`. Não há `all_access` nem `admin` **na lista mostrada**, mas isso **não é prova de usuário estritamente read-only nem de bloqueio administrativo de todas as APIs**. Interpretação de acordo com documentação OpenSearch: `readall` permite pesquisar/ler índices do cluster; `kibana_user` permite uso do Dashboard e pode conceder escrita em índices do próprio Dashboard; `own_index` concede pleno acesso ao índice individual do usuário. Essas são permissões do **Indexer/OpenSearch**, distintas do RBAC da API Wazuh Server (Server management → Security), cuja atribuição não foi verificada. Próximo gate: **consulta read-only** à interface de gerenciamento para determinar visibilidade/permissões, sem modificar credenciais, roles, índices ou agentes, registrando mensagem de acesso negado se ocorrer. Não executar teste destrutivo para provar negação. Evidência visual disponível no chat: `image(20261101-170323).png`; arquivo não inserido no GitHub. Nenhuma mudança na infraestrutura por este registro.

Referências: OpenSearch Security built-in roles `https://docs.opensearch.org/latest/security/access-control/users-roles/`; Wazuh server roles `https://documentation.wazuh.com/current/cloud-service/your-environment/manage-auth.html`.


## ZT-07.28 — Validação de permissões do usuário de teste

**Data:** 01/11/2026. O usuário de teste entrou no Wazuh Dashboard por meio do acesso privado previamente validado. Em quatro capturas fornecidas na conversa, as abas **Users, Roles, Policies e Roles mapping**, da seção Security, mostraram **“You have no permissions”**. Resultado: **PASS para restrição de consulta nessas quatro seções**. Nenhuma configuração foi alterada. Isso não equivale a validar todas as operações administrativas nem a negar acesso ao Resource para uma identidade Twingate fora do grupo autorizado; essas verificações permanecem pendentes. As quatro capturas originais permanecem na conversa, não anexadas ao repositório.


## ZT-07.29 — Contraprova administrativa Wazuh (01/11/2026)

**Escopo:** comparação observacional das quatro seções `Security` do Wazuh Server por usuário do Dashboard identificado visualmente pelo avatar `a` (a operadora informou login na conta `admin`) após verificar com `teste` que as quatro seções exibiam `You have no permissions` (ZT-07.28). Acesso via Firefox no openSUSE e Twingate à interface `https://wazuh.dashboard/`. Não houve operações de escrita.

| Área | Usuário `teste` (ZT-07.28) | Usuário `admin` (ZT-07.29) |
|---|---|---|
| Users | Consulta negada | Lista carregada; duas contas apresentadas com papel `administrator`: `wazuh` e `wazuh-wui` |
| Roles | Consulta negada | Lista de roles carregada, incluindo `administrator`, `readonly`, `users_admin`, `agents_readonly`, `agents_admin`, `cluster_readonly`, `cluster_admin`; essas linhas exibem status `Reserved` |
| Policies | Consulta negada | Lista de policies carregada; regras `allow` e status `Reserved` exibidos nos itens visíveis (página 1/4) |
| Roles mapping | Consulta negada | Lista carregada; mapeamento `conectaeduca_teste_readonly` (ID 100) vinculado ao role `readonly`, e dois mapeamentos de integração `wui_elastic_admin` e `wui_opensearch_admin` vinculados a `administrator` |

**ZT-07.29 = PASS para a comparação de autorização de leitura em 4 seções administrativas:** o teste positivo `admin` abre listas e o teste negativo `teste` recebe negação. A lista de roles mapping prova a existência do mapeamento `conectaeduca_teste_readonly`, **não prova por si só quais identidades/usuários estão incluídos nesse mapeamento**, pois detalhes de associação não foram abertos; verificar separadamente apenas se exigido. As contas `wazuh` e `wazuh-wui` aparecem com papel `administrator`; a captura não permite concluir se isso é risco ou desvio da configuração padrão. Não interpretar este ensaio como prova de bloqueio de acesso ao Resource por uma identidade Twingate fora de `CE-SOC-OPERACAO` nem como teste das APIs administrativas de escrita. Nenhuma configuração modificada.

**Custódia visual:** capturas fornecidas pela operadora em 01/11, referenciadas nesta conversa e não anexadas ao GitHub como binários. Arquivos e SHA-256 verificados dos uploads atuais:

- `image(20261101-171728).png` — Users — `f8861509de218026b2aa4b505a20f04e643a7c807658838dc7d355d57bf3c4de`
- `image(20261101-171746).png` — Roles — `719fee211ef15bbc390cc59b52a745355f81f310fd2da2cc9a9c6664e4aa6e2e`
- `image(20261101-171819).png` — Policies — `ec0dc0453c5d9120a898259658ed511d6adde26bf55ac73e41eb183cb1d1b7e5`
- `image(20261101-171839).png` — Roles mapping — `333a3cdee0d6d21a3b8872c62ee1c30ebc773d8867965b639cd41e15d8535f24`

**Próximo gate:** testar controle negativo específico do Twingate com identidade de laboratório **fora** do grupo SOC; consultar logs de acesso e revistar disponibilidade da EP125/Connector da DMZ separadamente. Preservar a sessão `admin` com cuidado, sem alterá-la sem change control.


## ZT-07.30 — Pré-requisito para teste negativo de identidade Twingate (01/11/2026)

A responsável informou que dispõe de **apenas uma identidade pessoal** no tenant Twingate. Portanto, o acesso permitido ao Resource Wazuh pelo grupo `CE-SOC-OPERACAO` está demonstrado, mas **não foi realizado** ensaio independente de acesso com uma segunda identidade fora dos grupos autorizados. **Status: PENDENTE POR PRÉ-REQUISITO**, não `FAIL`, nem `PASS` de negação. Para executar, convidar identidade separada e aprovada por professor/suporte em `Team → Users → Add User`, sem associação aos grupos com acesso ao Resource Wazuh (verificar também `Everyone` e qualquer concessão indireta), e realizar tentativa controlada de acesso, preservando captura/telemetria; confirmar eventual licença/custo antes. Não remover a operadora de `CE-SOC-OPERACAO` para esse teste, não compartilhar credenciais e não duplicar contas sem aprovação. Enquanto se aguarda uma identidade de teste, prosseguir na homologação do Connector DMZ/EP125 e revisão de fluxos pfSense sem declarar conclusão integral da política negativa Twingate.


## ZT-08.1 — painel Twingate confirma Connector DMZ Connected (01/11/2026)

Capturas do painel Twingate fornecidas em 01/11/2026 mostram **Remote Network ConectaEduca - DMZ** com Connector `conectaeduca-dmz-01` **Connected**, Connector `notorious-catfish` **Not yet connected**, Resource `ConectaEducaAPP` com destino `192.168.6.34`. A rede **ConectaEduca - Rede Interna** mostra Connector `conectaeduca-interna-ep126` **Connected**, `conectaeduca-interna-01` **Could not connect**, Resource `ConectaEduca — Wazuh Dashboard` com destino `127.0.0.1`. Conclusão: existem Connectors ativos em cada rede conforme o painel; **não requer reinstalação/redeploy para investigação**. A captura **não comprova em qual host efetivo cada Connector executa, se o Resource APP está alcançável pelo Client ou se o tráfego atravessa WAF**. Próximo passo: no host institucional EP125 confirmar nome/saúde/rede/restarts dos contêineres Connector, sem consultar variáveis de ambiente/tokens nem executar `docker compose up`; depois realizar teste positivo remoto do Resource APP, revisar permissões/portas e reteste PA-02 WAF. Conectores desconectados não serão excluídos sem revisão. PR #213 para DMZ permanece em draft, e seu código não deve ser aplicado sobre runtime saudável sem diff/rollback.


## ZT-08.2 — EP125 Connector DMZ ativo e erro de filtro (01/11/2026)

A operadora executou checkpoint de leitura às `2026-11-01T14:28:00-03:00` em `ep125-pucpr`: `DOCKER=OK`. A seção `CONNECTORS TWINGATE` ficou vazia porque filtrava apenas nomes contendo `twingate|connector`, **não identificando o nome real** `conectaeduca-dmz-01`. A seção `APLICACAO DMZ` mostrou: `conectaeduca-dmz-01` **Up 41 hours (healthy)**; `conectaeduca-dmz-php-1`, `conectaeduca-dmz-waf-1`, `conectaeduca-dmz-nginx-1` **Up 46 hours (healthy)**. Git na EP125: branch `main`, HEAD curto `b74ea58`, somente arquivo **não rastreado** `?? deploy/dmz/compose.audit-persistent.yml` no status fornecido. Nome sugere override de persistência de auditoria, **sem conteúdo ou utilização comprovada**; preservar, não excluir nem sobrescrever. Nenhuma alteração à infraestrutura pelo script. Painel Twingate já mostrava `conectaeduca-dmz-01` Connected na Remote Network DMZ, com Resource `ConectaEducaAPP` apontando à EP125. **Status:** Connector DMZ parece operacional no host e no painel, mas sem prova positiva end-to-end do Resource APP, sem validação de porta, políticas, WAF e negativas. **Não reinstalar nem aplicar `--deploy` da PR #213**. Próximo checkpoint restrito: `docker inspect` do contêiner nominal (campos selecionados que não expõem tokens), identificar modo de rede e imagem; verificar se override de auditoria é efetivamente usado sem ler segredos; testar APP pelo Client openSUSE somente depois.


## ZT-08.4–08.5 — Acesso APP na DMZ com TCP/443 (01/11/2026)

**Evidências da operadora:** no openSUSE, Client Twingate `online`, Resource `ConectaEducaAPP` com autorização vigente. Requisição HTTP à aplicação expirou sem resposta (`curl RC=28`); HTTPS retornou `HTTP=200`, `TLS_VERIFY=0`, `CURL_RC=0`. Captura do Admin Console da Remote Network `ConectaEduca - DMZ`, Resource `ConectaEducaAPP`, mostra **Protocols TCP: [443]**, grupo de acesso `CE-PORTAL`, política `Default Policy` e atividade recente de conexão da identidade autorizada ao destino. **ZT-08.5 PASS para acesso positivo via Twingate e resposta HTTPS**; o timeout na porta 80 é compatível com a política que limita o Resource a TCP/443, não prova indisponibilidade do WAF. A atividade confirma conexão ao Resource, mas não contém prova granular de qual solicitação HTTP gerou o evento. **Não concluir que o tráfego passou pelo WAF nem considerar PA-02 corrigido**: isso requer correlação com logs/arquitetura e comparação de alcance do upstream Nginx. A captura foi recebida na conversa (`image(20261101-173619).png`); não anexada ao GitHub, e dados pessoais do painel não são reproduzidos neste registro. Nenhuma alteração de rede, firewall, contêineres ou Resource foi realizada neste teste.


## ZT-08.6 — Requisição HTTPS correlacionada no WAF

Em 01/11/2026, um GET HTTPS de teste à aplicação da DMZ com marcador `CEZT-PA02-20261101T144223` retornou HTTP 200 e verificação TLS válida no openSUSE. O WAF da EP125 registrou a mesma URI em access log e auditoria ModSecurity às 17:42:25 UTC. A auditoria indica ModSecurity 3.0.16, CRS 4.25.1, `is_interrupted=false`, resposta 200. Regra 920350 detectou hostname apresentado como IP, sem bloqueio. **PASS para inspeção da requisição observada no WAF.** Não comprova correção do caminho alternativo ao Nginx interno (PA-02), ainda pendente. A origem `172.18.0.1` do registro é um endereço de rede Docker, não atribuição conclusiva do usuário. **Omitidos dados de cookies/sessão** presentes no registro bruto fornecido. Sem alterações em infraestrutura.


## PA-02 — Configuração de rede WAF e Nginx na EP125 (01/11)

Saída fornecida da EP125: os contêineres `conectaeduca-dmz-waf-1` e `conectaeduca-dmz-nginx-1` estão em execução e ligados à rede Docker `conectaeduca-dmz_frontend`. O WAF publica no host `192.168.6.34` as portas 80 e 443, respectivamente mapeadas para 8080/tcp e 8443/tcp do contêiner. O Nginx informa `80/tcp:null` e `8080/tcp:null`, sem publicação direta em portas do host. **Conclusão restrita:** a publicação no host passa pelo WAF; a ausência de publicação do Nginx não implica isolamento de peers Docker ou do próprio host contra acesso direto à bridge. PA-02 permanece **aberto**; etapa seguinte será uma requisição benigna e marcada, diretamente ao IP interno do Nginx e porta previamente identificada no pentest, para verificar alcance sem modificar os serviços. O resultado do teste determinará se ainda há caminho de bypass interno. Nenhuma alteração de infraestrutura foi realizada por esta verificação.
