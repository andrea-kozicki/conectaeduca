# Plano de Testes de Segurança do ConectaEduca

**Versão:** 2.0 pós-VMs
**Consolidação inicial:** 23/08/2026
**Revisão pós-implantação:** 04/09/2026
**Objetivo:** manter uma sequência reproduzível de testes, registrando o que já foi executado, o resultado e o que ainda depende de validação.

## 1. Regras do laboratório

1. testar somente ativos autorizados do ConectaEduca;
2. usar contas, dados e marcadores sintéticos;
3. preferir marcador seguro a malware/web shell funcional;
4. não copiar segredos para log, relatório ou screenshot;
5. registrar origem, alvo, data/hora, esperado e observado;
6. testes destrutivos só atingem dados descartáveis;
7. pentest depende de recuperabilidade;
8. diferença entre **planejado**, **implementado** e **validado** deve ser explícita.

## 2. Evolução das fases

| Fase | Escopo | Estado em 23/08 | Estado em 04/09 | Resultado principal |
|---|---|---|---|---|
| 1 | CI/análise estática | ativa | **VALIDADA/CONTÍNUA** | PHPUnit, Composer, Semgrep e PRs continuam gates |
| 2 | integração local | executada em grande parte | **VALIDADA** | auth/RBAC/MFA/CSRF/WAF/OpenBao/Ferret/Bacula exercitados |
| 3 | implantação VMs | pendente | **EXECUTADA** | EP125/EP126 receberam workloads e checkpoints |
| 4 | segmentação | pendente | **VALIDADA POR COMPORTAMENTO** | allowlist funcional observada entre zonas |
| 5 | detecção/telemetria | preparado | **WAZUH/FIM/YARA VALIDADO** | agents Active + regra YARA 110211 |
| 6 | resiliência | preparado | **RESTORE VALIDADO EM LAB + RECUPERAÇÃO EP126** | restore/hash + kit externo + snapshot |
| 7 | DAST dedicado | planejado | **PENDENTE** | ZAP ainda será executado |
| 8 | Pentest A | final | **PENDENTE** | executar sem Twingate |
| 9 | Zero Trust | não ativar antes do A | **PENDENTE POR DESENHO** | ativar Twingate depois do A |
| 10 | Pentest B | comparação futura | **PENDENTE** | repetir cenários com Zero Trust |

## 3. CI e supply chain

### CI-01 — Composer

**Teste:** `composer validate`, `composer audit --locked`, compatibilidade da plataforma.

**Evolução:** passou a acompanhar PRs de dependências.

**Resultado:** updates de phpseclib/phpdotenv/PHPUnit foram integrados após gates; merges registraram 119 testes/351 assertions.

**Status:** **APROVADO / CONTÍNUO**.

### CI-02 — Semgrep SAST

**Teste:** regras sobre projeto + fixtures positivas.

**Evolução:** deixou de ser apenas "scanner presente" e gerou correções reais.

**Resultado:** findings de configuração/permissão foram tratados; exceções justificadas receberam comentário explícito; workflow existe na `main`.

**Status:** **APROVADO / CONTÍNUO**.

### CI-03 — Segredos estáticos

**Teste:** higiene de Git + scanner + revisão de `.runtime`/`.env`.

**Resultado:** documentação e handoffs não devem conter secrets; auditoria documental recente não encontrou indicador de alta confiança.

**Status:** **APROVADO / CONTÍNUO**.

### CI-04 — PHPUnit/lint

**Resultado conhecido:** merges recentes registraram **119 testes e 351 assertions**.

**Status:** **APROVADO / CONTÍNUO**.

### CI-05 — Imagens

**Teste:** digest, build, health, scanner e hardening.

**Evolução:** PHP/Nginx receberam nova rodada pós-VMs.

**Status:** **APROVADO NO GIT / NOVO FREEZE A RECONCILIAR NAS VMs**.

## 4. Aplicação

### APP-01 — Público/privado

**Esperado:** 200 público, 401 privado sem sessão.

**Observado:** comportamento conforme esperado nos checkpoints de autenticação.

**Status:** **APROVADO**.

### APP-02 — CSRF

**Esperado:** POST mutável sem token → 419.

**Observado:** **419**.

**Status:** **APROVADO**.

### APP-03 — Credencial inválida

**Esperado:** 401 e mensagem genérica.

**Observado:** 401 + auditoria de falha.

**Status:** **APROVADO**.

### APP-04 — Rate limiting

**Esperado:** antes do limite 401; após limite 429.

**Observado:** controle e evento `rate_limit_blocked` validados durante a implementação.

**Status:** **APROVADO**.

### APP-05 — MFA

**Esperado:** senha válida não cria sessão final sem segunda etapa.

**Observado:** pré-autenticação/MFA implementados e exercitados.

**Status:** **APROVADO**.

### APP-06 — RBAC

**Esperado:** usuário/empresa/admin separados.

**Observado:** tentativas fora do papel retornam 403 e `forbidden_access_attempt`.

**Status:** **APROVADO**.

### APP-07 — Sessão/logout

**Esperado:** logout invalida e rota privada volta a 401.

**Observado:** comportamento validado.

**Status:** **APROVADO**.

## 5. WAF

### WAF-01 — Tráfego legítimo

**Resultado:** rotas necessárias continuaram funcionais durante os checkpoints.

**Status:** **APROVADO**.

### WAF-02 — XSS sintético

**Esperado:** 403.

**Resultado:** probe bloqueada.

**Status:** **APROVADO LOCALMENTE**.

### WAF-03 — SQL injection sintética

**Esperado:** 403.

**Resultado:** probe bloqueada.

**Status:** **APROVADO LOCALMENTE**.

### WAF-04 — Path traversal

**Esperado:** 403.

**Resultado:** probe bloqueada.

**Status:** **APROVADO LOCALMENTE**.

### WAF-05 — Privacidade de auditoria

**Controle:** `RelevantOnly`, partes `AFHZ`; B/C omitidas.

**Resultado:** desenho reduz persistência de headers/body sensíveis.

**Status:** **APROVADO NO BASELINE**.

### WAF-06 — DAST dedicado

**Ferramenta:** OWASP ZAP.

**Status:** **PENDENTE**.

## 6. VMs e segmentação

### NET-01 — EP126 → EP125

Portas testadas:

- **PASS:** 80, 443, 9102;
- **BLOCK/sem alcance:** 22, 3389, 3306, 5432, 8200, 9101, 9103, 1514, 1515, 55000.

**Status:** **APROVADO PARA O COMPORTAMENTO ESPERADO**.

### NET-02 — EP125 → EP126

- **PASS:** 3306, 9103, 1514;
- **BLOCK/sem alcance:** 22, 80, 443, 3389, 5432, 8200, 9101, 1515, 55000.

**Status:** **APROVADO PARA O COMPORTAMENTO ESPERADO**.

### NET-03 — ICMP

**Observado:** ICMP entre VMs bloqueado; gateways alcançáveis.

**Status:** **INFORMATIVO / COERENTE COM SEGMENTAÇÃO**.

### NET-04 — MariaDB

**Resultado:** DMZ alcança 3306; sentido inverso não é fluxo funcional; defesa adicional no host restringe origem permitida.

**Status:** **APROVADO**.

### NET-05 — SSH/XRDP/administração

**Resultado:** 22 e 3389 não atravessaram as zonas no teste atual; OpenBao/55000/9101 também bloqueados.

**Status:** **APROVADO POR COMPORTAMENTO**.

### NET-06 — Evidência pfSense

**Pendência:** export/auditoria administrativa completa depende do nível de permissão institucional.

**Status:** **PARCIAL POR RESTRIÇÃO DO AMBIENTE**.

## 7. Wazuh/FIM/YARA

### DET-01 — Agentes

**Esperado:** EP125 e EP126 Active.

**Observado:** ambos permaneceram Active via TCP/1514.

**Status:** **APROVADO**.

### DET-02 — Enrollment

**Evolução:** 1515 necessário no bootstrap, depois removido da publicação.

**Resultado:** agentes continuaram Active sem manter porta de enrollment aberta.

**Status:** **APROVADO**.

### DET-03 — FIM/YARA

Marcador seguro:

`CONECTAEDUCA_YARA_TEST_MARKER_2026`

**Fluxo observado:**

```text
FIM -> 110200/110201 -> Active Response -> YARA -> decoder -> 110211
```

**Resultado:** match classificado em nível 12.

**Status:** **APROVADO**.

### DET-04 — Auditoria da aplicação → SIEM

**Status:** **CONSOLIDAR EVIDÊNCIA E2E SE AINDA NECESSÁRIO**.

## 8. DLP

### DLP-01 — Finding sintético

**Camada já validada:** Ferret → relatório bruto → sanitizador → JSONL → classificação Wazuh.

**Resultado:** allowlist impede propagação de conteúdo bruto.

**Status:** **APROVADO NA CAMADA DE PROCESSAMENTO/ANÁLISE**.

### DLP-02 — Transporte via Agent

**Esperado:** JSONL sanitizado chega via Wazuh Agent.

**Status:** **PENDENTE DE EVIDÊNCIA E2E, SE NÃO HOUVER CHECKPOINT FINAL**.

### DLP-03 — Privacidade

**Esperado:** Manager não recebe `reports/raw/`, `inbox/` ou conteúdo original.

**Status:** **APROVADO POR ARQUITETURA/CONFIGURAÇÃO**.

### DLP-04 — Ferret 2.4.3

**Objetivo:** reconciliar runtime observado com baseline 2.2.1.

**Critério:** digest + formatter + sanitizador + checkpoint + Wazuh.

**Status:** **PENDENTE**.

## 9. OpenBao

### SEC-01 — Segredo fora do Git

**Status:** **APROVADO**.

### SEC-02 — AppRole menor privilégio

**Resultado:** policies específicas, tokens/root temporário não persistentes.

**Status:** **APROVADO**.

### SEC-03 — Materialização em tmpfs

**Resultado:** no laboratório local, o segredo runtime foi materializado fora do Git e desaparece após reboot por desenho.

**Status:** **APROVADO NO LABORATÓRIO LOCAL**.

### SEC-04 — API entre zonas

**Resultado atual:** 8200 não atravessa DMZ→interna; OpenBao usa binding local na EP126.

**Status:** **APROVADO PARA O BASELINE SEM ACESSO REMOTO**.

### SEC-05 — Bridge OpenBao EP126 → segredo SMTP na DMZ

**Esperado:** se o SMTP real for habilitado, o host da DMZ deve receber/materializar o segredo por mecanismo autenticado e cifrado, sem expor root token ou SecretID estático.

Pré-requisitos:

- TLS no listener OpenBao;
- CA confiável;
- regra pfSense mínima;
- OpenBao Agent/Proxy ou workload identity equivalente;
- bootstrap seguro, preferencialmente com response wrapping.

**Status:** **PENDENTE / SOMENTE SE O SMTP REAL FOR HABILITADO NAS VMs**.

## 10. Bacula / recuperação

### BAK-01 — Backup sintético

**Resultado:** executado em laboratório.

**Status:** **APROVADO**.

### BAK-02 — Restore sintético

**Resultado:** restore + comparação SHA-256.

**Status:** **APROVADO**.

### BAK-03 — OpenBao Raft

**Resultado:** snapshot lógico entrou no Bacula, original foi removido, restore ocorreu e hash foi comparado.

**Status:** **APROVADO**.

### BAK-04 — Recuperação EP126

**Resultado:** Git/freeze + kit cifrado externo + snapshot Hyper-V.

**Status:** **APROVADO**.

### BAK-05 — Fluxos Bacula entre VMs

**Resultado de rede:** interna→DMZ 9102 e DMZ→interna 9103 alcançáveis.

**Status:** **CAMINHO DE REDE APROVADO**.

### BAK-06 — Risco de infraestrutura

Storage local não protege contra perda total do domínio físico da VM interna.

**Status:** **RISCO RESIDUAL ACEITO NO LABORATÓRIO**.

## 11. DAST

Ferramenta prevista: **OWASP ZAP**.

Sequência:

1. baseline/passivo;
2. triagem;
3. scan ativo autorizado;
4. autenticação com fixtures;
5. correlação WAF/Wazuh;
6. correção;
7. reteste;
8. relatório sanitizado.

**Status:** **PENDENTE**.

## 12. Pentest A — sem Zero Trust

| ATT&CK | Teste | Controle que deve ser observado |
|---|---|---|
| T1190 | exploração web controlada | WAF + validação |
| T1110 | brute force | rate limit + log |
| T1078 | conta válida de baixo privilégio | RBAC |
| T1505.003 | marcador sintético | FIM/YARA |
| T1021.004 | DMZ → SSH | segmentação |
| T1490 | acesso à recuperação | isolamento Bacula |
| T1486 | perda de dados sintéticos | restore |

**Status:** **PENDENTE**.

## 13. Twingate

Só ativar depois do Pentest A.

**Status:** **PENDENTE POR DESENHO EXPERIMENTAL**.

## 14. Pentest B — com Zero Trust

Repetir cenários comparáveis do Pentest A e registrar diferenças de superfície/caminho.

**Status:** **PENDENTE**.

## 15. NTP e correlação temporal

Diagnósticos:

- NTP service active;
- System clock synchronized: no.

A configuração pertence à infraestrutura institucional e já foi escalada.

**Status:** **PENDÊNCIA EXTERNA / NÃO ALTERAR SEM AUTORIZAÇÃO**.

## 16. Formato obrigatório da evidência

Cada teste novo deve registrar:

- ID;
- data/hora;
- ambiente;
- origem/alvo;
- pré-condições;
- ação;
- esperado;
- observado;
- porta/HTTP/processo;
- log/evento;
- artefato sanitizado;
- status;
- risco residual;
- próxima ação.

## 17. Gate para Pentest A

### Já atendido

- aplicação em VMs;
- WAF em operação;
- segmentação funcional observada;
- Wazuh Agents;
- FIM/YARA;
- restore Bacula em laboratório;
- contas/dados sintéticos possíveis.

### Ainda verificar antes do início

- DAST ou decisão de executar DAST imediatamente antes/do pentest;
- estado final do DLP E2E;
- freeze pós-hardening PHP/Nginx;
- relógios suficientemente correlacionáveis ou limitação NTP registrada;
- Ferret reconciliado ou drift explicitamente aceito para a rodada.

O gate não deve reclassificar como "pendente" um controle que já possui evidência.
