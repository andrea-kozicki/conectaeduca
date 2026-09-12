# Inventário de pendências — 12/09/2026

## Estado consolidado

O baseline defensivo do ConectaEduca avançou para um estágio pré-freeze. A expressão **validado** neste inventário é sempre aplicada por camada; ela não transforma automaticamente um componente inteiro em encerrado quando ainda existem auditorias de serviço ou operação pendentes.

Estado por camada:

- **EP125/DMZ**
  - Nginx, PHP-FPM e WAF/ModSecurity: runtime/hardening e validação funcional já comprovados, porém auditorias finais de configuração de serviço permanecem **PARCIAIS**;
  - TLS confiável da aplicação: validado;
  - Suricata nativo da EP125 -> Wazuh: validado ponta a ponta.
- **EP126/interna**
  - MariaDB: hardening de serviço validado; runtime/container ainda **PARCIAL**;
  - OpenBao: runtime forte, Shamir e AppRoles implementados; auditoria operacional/de serviço ainda **PARCIAL**;
  - Ferret: runtime forte e pipeline DLP -> Wazuh comprovado; operação, healthcheck e retenção ainda **PARCIAIS**;
  - PostgreSQL/Bacula Catalog: serviço/TLS validados; runtime/container ainda **PARCIAL**;
  - Bacula Director/Storage: runtime endurecido e fluxos funcionais validados; políticas operacionais de Jobs/FileSets/retenção permanecem evolução separada;
  - Wazuh Manager/Indexer/Dashboard: controles de runtime, agentes e módulos defensivos validados no baseline pré-pentest, com riscos residuais deliberados documentados.
- Privilégio mínimo de sistema e aplicação, MFA e RBAC: validados;
- Suricata no pfSense em IDS/detect-only, com EVE JSON e alertas reais: validado;
- segmentação LAN33 <-> LAN49 no pfSense com exceções explícitas: validada;
- regras genéricas IPv4 `* -> *` desabilitadas em LAN33 e LAN49;
- teste negativo TCP/22 bloqueado nos dois sentidos;
- fluxos permitidos preservados:
  - EP125 -> EP126: 3306, 1514, 9103;
  - EP126 -> EP125: 80, 443, 9102;
- HTTPS de saída preservado nas duas VMs;
- NAT de saída automático e ausência de NAT 1:1.

## Evidência de segmentação pfSense

Resultado pós-limpeza das regras:

### EP125 / LAN33

- rota default: PASS;
- HTTPS de saída: PASS;
- TCP/3306, 1514 e 9103: OPEN;
- TCP/22 para EP126: TIMEOUT;
- resumo: `PASS=4 WARN=0 FAIL=0`.

### EP126 / LAN49

- rota default: PASS;
- HTTPS de saída: PASS;
- TCP/80, 443 e 9102: OPEN;
- TCP/22 para EP125: TIMEOUT;
- resumo: `PASS=4 WARN=0 FAIL=0`.

Conclusão: a retirada lógica das regras amplas não quebrou os fluxos necessários e a segmentação lateral permaneceu efetiva.

## Pendências prioritárias

### 1. pfSense — egress mínimo por zona

Ainda existem regras finais:

- `LAN33 subnets -> any`;
- `LAN49 subnets -> any`.

Próximo passo: inventariar dependências reais e substituir o egress amplo por regras explícitas em etapas, preservando DNS, HTTP/HTTPS, APT, Docker/GitHub, Wazuh, Bacula e demais fluxos necessários.

### 2. pfSense/Suricata -> Wazuh

O Suricata do pfSense já detecta eventos reais e persiste EVE JSON, mas a correlação deste sensor específico no Wazuh ainda precisa ser fechada e evidenciada.

Critério de fechamento: evento gerado no pfSense deve aparecer de forma rastreável no Wazuh, com correlação temporal e origem do sensor identificável.

### 3. NTP e timezone institucional

EP125 ainda apresenta:

- `System clock synchronized: no`;
- `Packet count: 0`;
- servidor NTP selecionado em IPv6 sem rota IPv6 global utilizável.

O pfSense registra EVE com offset `-0400`, enquanto as VMs usam `America/Sao_Paulo (-03)`.

A conta `aluno` não expõe as páginas General Setup/NTP na GUI do pfSense. Esta pendência continua classificada como boundary institucional, sem bypass local.

### 4. Consolidação de evidências e freeze final

Consolidar em um único checkpoint:

- rede/pfSense;
- Suricata pfSense;
- Wazuh;
- WAF;
- DLP;
- Bacula;
- OpenBao;
- riscos residuais;
- hashes dos relatórios;
- estado dos checkouts das VMs.

### 5. Pentest controlado

Executar os casos de teste acadêmicos já previstos:

- movimento lateral;
- escalação de privilégios;
- evasão de defesa;
- vazamento/exfiltração de dados;
- exploração web/banco compatível com o ambiente próprio.

Cada caso deve ter baseline, execução controlada, telemetria observada, mitigação e evidência.

### 6. Twingate / Zero Trust

Implementar somente após o primeiro pentest/freeze, para preservar comparação entre baseline perimetral e arquitetura Zero Trust.

## Backlog não bloqueante

- revisar governança/ciclo de vida da credencial administrativa do Wazuh;
  - uma inspeção posterior à evidência Suricata/Wazuh de 07/09 corrigiu a premissa inicial de "credencial padrão": o usuário administrativo permanece `admin`, porém a senha observada era longa (32 caracteres) e não correspondia à senha padrão da stack;
  - portanto, não há evidência atual que justifique rotação emergencial como gate de freeze; a rotação passa a ser obrigatória se houver exposição, requisito de política, mudança de custódia ou outra evidência concreta;
- persistir o acknowledgment dos recovery codes de MFA;
- refinamentos adicionais de CPU/RAM/retention onde já existe baseline funcional;
- revisar port forwards institucionais RDP apenas se houver escopo/permissão explícita.



## Auditoria dos containers — lacunas operacionais e residuais

A classificação abaixo distingue **controle técnico já validado** de **uso operacional/auditoria de serviço ainda pendente**. Um container pode estar hardened e saudável sem que o fluxo de operação tenha sido exercitado suficientemente para o freeze.

### EP126 / rede interna

| Componente | Estado técnico | O que ainda falta antes do freeze |
|---|---|---|
| OpenBao | runtime forte: rootfs RO, cap_drop ALL, NNP, PIDs 256, memória 1 GiB, healthcheck, API/UI em loopback; Shamir/AppRole SMTP e snapshot Bacula já documentados | auditoria de serviço e exercício operacional: listener/auth methods/TTLs/tokens/audit device/policies; provar consumo por AppRole sem root; confirmar trilha de auditoria no Wazuh; documentar procedimento normal de unseal/rematerialização sem expor segredo |
| Ferret | runtime forte: non-root, rootfs RO, cap_drop ALL, NNP, PIDs 128, loopback; pipeline Ferret -> sanitizador -> dlp.jsonl -> Wazuh já foi provado E2E | exercício operacional reproduzível pela equipe; healthcheck ausente no Compose; recursos CPU/RAM ainda sem limites; política de retenção/limpeza automática ainda não habilitada; quarentena permanece futura/detect-only |
| MariaDB | hardening de serviço validado: TLS, mínimo privilégio, conta restrita à EP125, local_infile OFF e testes funcionais | runtime/container ainda parcial: avaliar rootfs RO, NNP, cap_drop e limites de recursos em candidato isolado antes de qualquer promoção |
| Wazuh Manager | runtime validado: NNP, PIDs 1024, healthcheck e exposição mínima; integrações Suricata/DLP e agentes por zona comprovadas | **serviço PARCIAL / gate pré-freeze:** revisar API/RBAC, enrollment temporário, Active Response e módulos efetivamente necessários; rootfs/capabilities permanecem decisão separada de compatibilidade |
| Wazuh Indexer | runtime validado: cap_drop ALL, NNP, PIDs 256, healthcheck, sem porta host | **serviço PARCIAL / gate pré-freeze:** revisar security plugin, usuários internos, TLS HTTP/transport e acesso anônimo; CPU/RAM continuam refinamento secundário |
| Wazuh Dashboard | runtime validado: cap_drop ALL, NNP, PIDs 128, healthcheck e loopback | **serviço PARCIAL / gate pré-freeze:** revisar sessão/cookies, TLS, RBAC e opções relevantes do OpenSearch Dashboards; rootfs/CPU/RAM permanecem riscos de runtime separados |
| Bacula Catalog / PostgreSQL | SCRAM, TLS via PgBouncer verify-full, 5432 não publicado, serviço validado | runtime do container Catalog ainda parcial; avaliar rootfs/capabilities/limites em candidato isolado |
| PgBouncer | non-root, rootfs RO, cap_drop ALL, NNP, healthcheck e socket local | sem pendência crítica identificada; manter baseline |
| Bacula Director | hardening de runtime validado, rootfs RO/PID-less/capabilities finais zeradas/NNP/PIDs/healthcheck | sem pendência crítica; políticas de Jobs/FileSets/RunScripts são evolução operacional |
| Bacula Storage | hardening de runtime validado, rootfs RO/capabilities finais zeradas/NNP/PIDs/healthcheck | sem pendência crítica; retenção/mídia e domínio de falha do backup são riscos operacionais já conhecidos |

### EP125 / DMZ

| Componente | Estado técnico | O que ainda falta antes do freeze |
|---|---|---|
| PHP-FPM | non-root/read-only/cap_drop ALL/PIDs/tmpfs e aplicação funcional | auditoria final de php.ini/pool, upload/session/error disclosure e funções de risco; preferir validação antes do pentest em vez de mudanças agressivas |
| Nginx | non-root/read-only/cap_drop ALL/PIDs/tmpfs | revisão final de headers, métodos, timeouts, disclosure e FastCGI/proxy |
| WAF / ModSecurity + CRS | rootfs RO, cap_drop ALL, PIDs, NNP, TLS, logging e XSS sintético bloqueado | consolidar policy/paranoia/exclusions/logging e usar o pentest como validação funcional; evitar tuning cego antes da linha de base |

### Fora do conjunto atual de containers persistentes

- Mailpit não aparece no stack declarativo atual; o projeto possui overlay SMTP real. Tratar Mailpit como artefato histórico/laboratorial, não como workload atual.
- Suricata, Wazuh Agent e Bacula File Daemon nas Ubuntu são serviços nativos do host, não containers.
- Twingate ainda não está implantado e permanece pós-pentest.

## Ordem revisada antes do freeze

1. OpenBao — exercício operacional + auditoria de serviço.
2. Ferret — exercício de uso real com artefato sintético + retenção/healthcheck.
3. Wazuh Manager/Indexer/Dashboard — fechar auditorias de serviço (API/RBAC/módulos, security plugin/usuários/TLS/anônimo, sessão/cookies/TLS/RBAC).
4. MariaDB e PostgreSQL Catalog — auditoria de runtime residual em candidatos isolados, sem promoção automática.
5. Nginx/PHP/WAF — auditoria de configuração de serviço, priorizando observação e regressão.
6. pfSense — egress mínimo e correlação Suricata -> Wazuh.
7. consolidar riscos residuais aceitos e checkpoint/freeze pré-pentest.

## Critério de encerramento da fase

A fase pode ser considerada pronta para freeze/pentest quando:

1. auditorias de serviço do Wazuh Manager/Indexer/Dashboard estiverem concluídas e evidenciadas;
2. egress mínimo estiver definido e validado;
3. pfSense/Suricata estiver correlacionado no Wazuh;
4. NTP/timezone estiver resolvido ou formalmente aceito como risco institucional residual;
5. evidências estiverem consolidadas e versionadas;
6. snapshot/freeze pré-pentest estiver criado;
7. não houver segredos versionados;
8. o estado da credencial administrativa do Wazuh permanecer documentado sem evidência de senha padrão/exposição; caso surja evidência de exposição ou requisito de política, executar rotação coordenada antes do freeze.
