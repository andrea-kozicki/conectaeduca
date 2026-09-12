# Inventário de pendências — 12/09/2026

## Estado consolidado

O baseline defensivo do ConectaEduca avançou para um estágio pré-freeze. Nesta data, estão validados:

- EP125/DMZ: Nginx, PHP-FPM, WAF/ModSecurity, TLS confiável e Suricata nativo;
- EP126/interna: MariaDB, OpenBao, Ferret, Wazuh, Bacula, PostgreSQL/PgBouncer;
- Wazuh: Manager/Indexer/Dashboard, Agents por zona, Auditd, SCA, Syscollector, YARA, FIM e Detection Engineering;
- privilégio mínimo de sistema e aplicação, MFA e RBAC;
- Suricata EP125 -> Wazuh ponta a ponta;
- Suricata no pfSense em IDS/detect-only, com EVE JSON e alertas reais;
- segmentação LAN33 <-> LAN49 no pfSense com exceções explícitas;
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
- persistir o acknowledgment dos recovery codes de MFA;
- refinamentos adicionais de CPU/RAM/retention onde já existe baseline funcional;
- revisar port forwards institucionais RDP apenas se houver escopo/permissão explícita.

## Critério de encerramento da fase

A fase pode ser considerada pronta para freeze/pentest quando:

1. egress mínimo estiver definido e validado;
2. pfSense/Suricata estiver correlacionado no Wazuh;
3. NTP/timezone estiver resolvido ou formalmente aceito como risco institucional residual;
4. evidências estiverem consolidadas e versionadas;
5. snapshot/freeze pré-pentest estiver criado;
6. não houver segredos versionados.
