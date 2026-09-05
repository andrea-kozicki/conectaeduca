# STRIDE — Modelo de Ameaças do ConectaEduca

**Versão:** 2.0 pós-VMs
**Consolidação inicial:** 23/08/2026
**Revisão pós-implantação:** 04/09/2026
**Escopo:** aplicação, CI/supply chain, pfSense, EP125/DMZ, EP126/rede interna e mecanismos de detecção/recuperação.

## 1. Objetivo

STRIDE é usado como modelo de ameaça e como mecanismo de rastreabilidade entre:

```text
ameaça
  -> controle
  -> teste
  -> resultado
  -> risco residual
```

A versão 2.0 preserva cenários da versão pré-VMs, mas atualiza estados depois da implantação.

## 2. Fronteiras de confiança

Consulte também `docs/dfd.md`.

1. Internet → pfSense/DMZ;
2. DMZ → rede interna;
3. WAF → Nginx/PHP;
4. PHP → MariaDB;
5. OpenBao/materializador → workload;
6. Ferret → sanitizador → Wazuh Agent;
7. Wazuh Agent → Manager;
8. Bacula Director ↔ File Daemon ↔ Storage;
9. GitHub/CI → artefatos/handoff.

## 3. Ativos

| Ativo | Propriedades prioritárias |
|---|---|
| contas e papéis | autenticidade, autorização |
| sessões | confidencialidade, integridade |
| MariaDB | confidencialidade, integridade, disponibilidade |
| segredos/keys | confidencialidade, menor privilégio |
| código/CI | integridade, rastreabilidade |
| logs/telemetria | integridade, minimização, disponibilidade |
| backups | integridade, recuperabilidade, isolamento |
| pfSense | integridade e segmentação |
| runtimes Docker | isolamento e menor privilégio |

## 4. Matriz STRIDE pós-VMs

| ID | Categoria | Cenário | Evolução do controle | Teste | Resultado observado | Estado |
|---|---|---|---|---|---|---|
| S-01 | Spoofing | atacante tenta autenticar como usuário legítimo | login local + MFA + rate limiting | credencial inválida, MFA e limite | 401 em falha; MFA impede conclusão só com senha; 429 no limite | **VALIDADO** |
| S-02 | Spoofing | replay de sessão roubada | cookie seguro + regeneração + logout | inspeção/logout | sessão destruída no logout; replay de cookie já roubado continua risco residual | **PARCIAL** |
| S-03 | Spoofing | workload falso tenta obter segredo SMTP | AppRole mínima + materialização local; bridge cross-VM exige TLS/workload identity | checkpoints OpenBao/SMTP | segredo não entra no Git; OpenBao não foi aberto à DMZ; entrega EP126→DMZ ainda não é considerada validada | **VALIDADO NO LAB LOCAL / CROSS-VM PENDENTE SE NECESSÁRIO** |
| T-01 | Tampering | alteração de formulário/requisição | CSRF + validação + WAF | POST sem token | 419 | **VALIDADO** |
| T-02 | Tampering | XSS/SQLi/path traversal | CRS PL2 + validação app | probes sintéticas | 403 no WAF; tráfego legítimo continuou funcional | **VALIDADO LOCALMENTE** |
| T-03 | Tampering | arquivo malicioso/modificado na DMZ | FIM → Active Response → YARA | marcador sintético em diretório controlado EP125 | regras 110200/110201 acionam fluxo; match chega a 110211 nível 12 | **VALIDADO NAS VMs** |
| T-04 | Tampering | comprometimento de código/dependência/CI | PR + PHPUnit + Semgrep + Composer Audit + Dependabot/Trivy + pinagem | workflows/checkpoints/PRs | findings geraram correção/triagem; updates passaram gates | **VALIDADO COMO PROCESSO** |
| R-01 | Repudiation | usuário nega login/falha/acesso proibido | `AuditLogger` | fluxos de autenticação/RBAC/logout | eventos de login, falha, forbidden e logout registrados | **VALIDADO** |
| R-02 | Repudiation | evento de host não é correlacionado | Wazuh central + Agents | agents EP125/EP126 + configtest | ambos Active via 1514; telemetria YARA correlacionada | **VALIDADO PARA YARA/FIM** |
| I-01 | Information Disclosure | segredo vaza em Git/config/log | OpenBao + `.gitignore` + tmpfs + scanners/redaction | auditoria de secrets/checkpoints | nenhum indicador de alta confiança nos documentos; secrets reais fora do Git | **VALIDADO COMO PROCESSO** |
| I-02 | Information Disclosure | DLP envia conteúdo sensível ao SIEM | Ferret → raw local → sanitizador allowlist → JSONL | sanitizador + `wazuh-logtest` | classificação sem relatório bruto no Manager | **VALIDADO NA CAMADA DE ANÁLISE / E2E A CONSOLIDAR** |
| I-03 | Information Disclosure | dado sensível em claro | envelope criptográfico + OpenBao | testes CryptoHybrid e migração phpseclib | criptografia continuou funcional após update | **VALIDADO** |
| D-01 | Denial of Service | brute force exaure autenticação | rate limit persistente | sequência controlada | 429 + evento específico | **VALIDADO** |
| D-02 | Denial of Service | tráfego excessivo na borda | WAF + runtime limits + pfSense | probes WAF e hardening runtime | bloqueio funcional; volumetria real não ensaiada | **PARCIAL** |
| D-03 | Denial of Service | perda/corrupção impede operação | Bacula + restore + kit EP126 + snapshot | backup/restore/hash + recuperação EP126 | recuperabilidade comprovada em laboratório e por camadas | **VALIDADO COM RISCO RESIDUAL FÍSICO** |
| E-01 | Elevation of Privilege | usuário comum acessa empresa/admin | RBAC server-side | testes por papel | 403 + auditoria | **VALIDADO** |
| E-02 | Elevation of Privilege | comprometimento DMZ alcança serviços internos | pfSense + bindings privados + nftables DB | teste TCP bidirecional | somente 3306/9103/1514 atravessaram DMZ→interna; 22/3389/8200/9101/1515/55000 bloqueados no teste | **VALIDADO POR COMPORTAMENTO** |
| E-03 | Elevation of Privilege | container amplia privilégio no host | non-root, read-only, cap drop, sem Docker socket | inspeção/hardening PHP/Nginx/Ferret | PHP/Nginx receberam hardening adicional pós-VMs | **FORTE / RECONCILIAR NOVO FREEZE** |
| E-04 | Elevation of Privilege | workload lê segredo além do necessário | policy/AppRole específica | testes de policy/AppRole | escopo mínimo; token/root temporário não persiste | **VALIDADO LOCALMENTE** |

## 5. Evolução das ameaças mais relevantes à atividade acadêmica

### 5.1 Movimento lateral — E-02 / T-03

**Antes das VMs:** mitigação descrita como arquitetura alvo.

**Depois das VMs:** conectividade foi testada nos dois sentidos.

EP125 → EP126:

- permitidos: 3306, 9103, 1514;
- bloqueados no teste: 22, 80, 443, 3389, 5432, 8200, 9101, 1515, 55000.

EP126 → EP125:

- permitidos: 80, 443, 9102;
- bloqueados no teste: 22, 3389, 3306, 5432, 8200, 9101, 9103, 1514, 1515, 55000.

**Resultado:** comprometimento da DMZ não implica acesso genérico à rede interna pelos serviços testados.

**Limitação:** não afirmar regra interna exata do pfSense sem acesso administrativo suficiente.

### 5.2 Escalação de privilégio — E-01 / E-03 / E-04

Camadas:

- RBAC no aplicativo;
- containers com menor privilégio;
- AppRole/policies de segredos;
- APIs administrativas não publicadas.

Resultado:

- usuários não atravessam papéis;
- PHP/Nginx tiveram superfície de runtime reduzida;
- OpenBao permanece fora da DMZ.

### 5.3 Evasão de mecanismos de defesa — T-03 / R-02

A preparação de YARA virou teste operacional:

```text
FIM
 -> regra 110200/110201
 -> Active Response
 -> YARA
 -> decoder
 -> regra 110211
```

Resultado:

- agente permaneceu Active;
- marcador sintético produziu classificação de alta severidade;
- enrollment 1515 foi fechado depois de concluído.

### 5.4 Vazamento de dados — I-01 / I-02 / I-03

Camadas:

- criptografia;
- OpenBao;
- DLP;
- redaction;
- WAF audit sem partes B/C;
- backup excluindo segredos.

Resultado:

- relatório bruto Ferret não deve ser enviado ao SIEM;
- eventos são reconstruídos por allowlist;
- segredos ficam fora do Git;
- OpenBao não cruza zonas em HTTP.

## 6. Riscos residuais

### 6.1 Replay de sessão

Ainda existe risco se um cookie válido for roubado.

Possíveis melhorias:

- timeout absoluto;
- timeout por inatividade;
- revogação de sessão;
- reautenticação em operação sensível.

### 6.2 Capacidade / DoS

WAF e limites de runtime não equivalem a proteção volumétrica de Internet.

Não foi executado ensaio de carga agressivo.

### 6.3 Bacula no mesmo domínio físico

Storage local na EP126 não protege contra perda total daquele disco/VM.

### 6.4 NTP

Os diagnósticos indicaram serviço NTP ativo, mas relógio não sincronizado.

Isso impacta correlação temporal e permanece dependência institucional.

### 6.5 Ferret

Runtime 2.4.3 observado vs baseline Git 2.2.1.

A divergência deve ser reconciliada antes do freeze final.

## 7. Cenários MITRE ATT&CK associados

| Técnica | Relação com STRIDE | Teste |
|---|---|---|
| T1190 Exploit Public-Facing Application | T-02 / E-02 | DAST/pentest controlado contra WAF/app |
| T1110 Brute Force | S-01 / D-01 | rate limit + auditoria |
| T1078 Valid Accounts | E-01 | conta de menor privilégio contra recursos superiores |
| T1505.003 Web Shell | T-03 / R-02 | marcador sintético em vez de web shell funcional |
| T1021.004 SSH | E-02 | tentativa DMZ → SSH interno |
| T1490 Inhibit System Recovery | D-03 | provar que app/DMZ não administra repositório Bacula |
| T1486 Data Encrypted for Impact | D-03 | perda apenas de dados sintéticos + restore |

## 8. Estado geral

- Spoofing: controles principais validados;
- Tampering: app/WAF/YARA validados em diferentes camadas;
- Repudiation: aplicação + Wazuh disponíveis;
- Information Disclosure: fortes controles de minimização/segredos;
- Denial of Service: aplicação protegida, volumetria permanece risco;
- Elevation of Privilege: RBAC + segmentação + runtime hardening.

O Pentest A/B continua necessário para testar caminhos adversariais integrados, não para "criar" controles que já existem.
