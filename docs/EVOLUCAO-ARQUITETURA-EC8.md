# Evolução da arquitetura e das validações — ConectaEduca / EC8

**Objetivo:** registrar como o projeto evoluiu, quais testes alteraram decisões e quais resultados transformaram itens planejados em controles validados.

Este documento não é apenas uma linha do tempo de commits. Ele liga:

```text
necessidade/ameaça
    -> decisão
    -> implementação
    -> teste
    -> resultado
    -> estado atual
```

## 1. Da aplicação anterior para a arquitetura EC8

### Situação inicial

O ConectaEduca veio de uma disciplina anterior com autenticação AWS Cognito.

### Mudança

Na EC8, a arquitetura passou a depender de controles locais e de infraestrutura próprios:

- autenticação local;
- RBAC;
- MFA;
- rate limiting;
- cofre de segredos;
- DLP;
- SIEM;
- WAF;
- backup;
- segmentação.

### Resultado

A branch Cognito foi preservada como legado histórico, enquanto a `main` passou a representar a arquitetura EC8.

**Estado:** concluído.

---

## 2. Autenticação, autorização e sessão

### Trabalho realizado

- login local;
- papéis `usuario`, `empresa`, `admin`;
- pré-autenticação MFA;
- TOTP;
- recovery codes;
- rate limiting persistente;
- logout/auditoria;
- CSRF.

### Testes

- rota privada sem sessão;
- acesso por papel inadequado;
- credencial inválida;
- POST sem CSRF;
- fluxo MFA;
- logout;
- limite de tentativas.

### Resultados

- 401 para ausência de autenticação;
- 403 para papel insuficiente;
- 419 para POST mutável sem CSRF;
- eventos `login_failed`, `login_success`, `forbidden_access_attempt` e correlatos;
- senha válida isoladamente não encerra o fluxo quando MFA é exigido.

**Estado:** validado e coberto por regressão.

---

## 3. DevSecOps antes da implantação

### Trabalho realizado

O projeto adotou gates de qualidade e segurança antes de levar a aplicação às VMs:

- PHPUnit;
- Composer validate/audit;
- Actions pinadas por SHA;
- Dependabot;
- Semgrep;
- Trivy;
- triagem contextual de CVEs;
- checksums;
- handoff reproduzível.

### Por que isso mudou o projeto

Os scanners não foram usados como lista decorativa de ferramentas.

A sequência usada foi:

```text
finding
  -> verificar alcance/contexto
  -> corrigir quando aplicável
  -> reexecutar teste
  -> aceitar risco residual somente com justificativa
```

### Resultados observados

- mensagem de exceção exposta em checkpoint SMTP foi identificada/corrigida;
- findings de permissão/configuração foram tratados ou explicitamente justificados;
- CVEs de Wazuh/MariaDB foram triadas por pré-condição e superfície;
- bases e runtimes foram revisados novamente depois das VMs;
- a `main` possui workflows separados de PHPUnit e Semgrep.

Em merges de dependências de setembro ficaram registrados **119 testes e 351 assertions** aprovados.

**Estado:** operacional como processo contínuo.

---

## 4. Containerização como mecanismo de segurança e portabilidade

### Trabalho realizado

A aplicação e os serviços foram separados em workloads com:

- imagens pinadas;
- usuários não-root quando suportado;
- secrets fora da imagem;
- healthchecks;
- redes Docker locais por VM;
- sem Docker socket;
- handoff reproduzível.

### Evolução pós-VMs

A implantação não encerrou o hardening.

PHP-FPM recebeu:

- base Alpine minimal;
- remoção de build deps;
- filesystem read-only;
- `cap_drop=ALL`;
- `pids_limit=128`;
- tmpfs específicos.

Nginx recebeu:

- novo digest;
- usuário `101:101`;
- filesystem read-only;
- `cap_drop=ALL`;
- `pids_limit=128`;
- tmpfs para cache/run;
- permissões explícitas nos arquivos públicos.

### Resultado

A containerização funcionou como etapa de **redução de superfície + portabilidade**. O mesmo artefato declarativo pôde ser levado às VMs e continuar recebendo hardening por PR.

**Estado:** validado; novo freeze pós-hardening ainda deve reconciliar runtime e Git.

---

## 5. WAF e aplicação exposta

### Trabalho realizado

- ModSecurity + OWASP CRS;
- terminação TLS;
- Nginx/PHP não publicados diretamente quando WAF está ativo;
- audit log reduzido para evitar persistência desnecessária.

### Testes

- tráfego legítimo;
- XSS sintético;
- SQL injection sintética;
- path traversal sintético;
- privacidade do audit log.

### Resultado

O WAF tornou-se o ponto único da superfície web, com aplicação/backend escondidos atrás da rede Docker da DMZ.

**Estado:** validado localmente e operacional; DAST dedicado nas VMs ainda pendente.

---

## 6. OpenBao e gestão de segredos

### Trabalho realizado

- storage Raft;
- bootstrap de laboratório;
- AppRole de mínimo privilégio;
- materialização de segredo em RAM/tmpfs;
- root temporário revogado;
- snapshot Raft integrado ao Bacula.

### Testes

- health/estado active;
- AppRole com escopo mínimo;
- segredo fora do Git;
- materialização efêmera;
- snapshot/restore via Bacula;
- comparação SHA-256.

### Resultado

No laboratório local, o segredo SMTP foi materializado fora do Git em RAM/tmpfs com AppRole de mínimo privilégio. Depois da separação em VMs, o OpenBao permaneceu local à EP126 e a DMZ não recebeu acesso HTTP ao cofre.

O PHP já possui contrato para consumir um arquivo de segredo no host da DMZ, mas a ponte OpenBao EP126 → DMZ **não é considerada validada** enquanto não houver TLS, CA confiável, Agent/Proxy ou workload identity e bootstrap seguro.

**Estado:** OpenBao operacional na EP126; materialização local validada; integração segura cross-VM do segredo SMTP permanece pendente caso o SMTP real seja habilitado.

---

## 7. Ferret DLP e minimização antes do SIEM

### Trabalho realizado

O Ferret foi separado em superfícies:

- `inbox/`;
- `reports/raw/`;
- sanitizador;
- `events/dlp.jsonl`.

### Testes

- scan com/sem finding;
- formatter JSON 2.4.3;
- sanitização por allowlist;
- rejeição de shape inesperado;
- `wazuh-logtest`.

### Resultado

O SIEM não recebe o conteúdo bruto do DLP. O evento é reconstruído com campos permitidos.

Esse desenho reduz o risco de o próprio mecanismo de monitoramento virar um novo repositório de dados sensíveis.

### Reconciliação pós-VM

O runtime 2.4.3 observado na EP126 foi validado pelo mesmo digest posteriormente promovido à baseline. O formatter 2.4.3 retornou objeto JSON com `stats` + `results` tanto no scan limpo quanto no scan com finding sintético; o sanitizador preservou a allowlist e não propagou `text`/`filename`.

A compatibilidade transitória com `legacy_empty_array` do Ferret 2.2.1 foi retirada do contrato atual.

**Estado:** Ferret 2.4.3 validado e reconciliado no Git; transporte DLP → Wazuh Agent permanece como evidência E2E separada se ainda necessário.

---

## 8. Wazuh: de stack central a detecção de endpoint validada

### Fase inicial

Manager/Indexer/Dashboard foram primeiro validados isoladamente.

### Integração DLP

Regras customizadas passaram a classificar o JSONL sanitizado do Ferret.

### Preparação YARA

Foram versionados:

- FIM;
- Active Response;
- script YARA;
- ruleset;
- decoders/regras.

### Teste nas VMs

Depois da implantação:

- EP125 e EP126 ficaram Active;
- TCP/1514 permaneceu operacional;
- FIM observou diretório sintético da EP125;
- Active Response executou YARA;
- resultado foi decodificado;
- regra 110211 nível 12 classificou o match;
- configtests passaram;
- TCP/1515 foi removido da publicação depois do enrollment.

### Resultado

O item deixou de ser "YARA preparado para a aula" e passou a ser **controle validado em runtime**.

**Estado:** validado.

---

## 9. Bacula e recuperação

### Trabalho realizado

- Director;
- Storage;
- Catalog PostgreSQL;
- File Daemon nativo como arquitetura final;
- FileSets por allowlist;
- MariaDB por dump;
- OpenBao por snapshot Raft;
- políticas RPO/RTO/retenção.

### Testes

- backup sintético;
- remoção controlada;
- restore;
- SHA-256;
- restore do snapshot Raft;
- canário de exclusão de custódia;
- recuperação externa da EP126.

### Resultados

O projeto passou a exigir **restore comprovado**, e não apenas job de backup concluído.

Na EP126 também foram documentadas três camadas:

1. Git/freeze;
2. kit cifrado externo;
3. snapshot Hyper-V.

### Risco residual

Storage na mesma VM/disco interno não protege contra perda total daquele domínio físico.

**Estado:** implementado e validado em laboratório; consolidar nova evidência pós-VM somente se necessário.

---

## 10. pfSense e segmentação

### Trabalho realizado

- separação DMZ/interna;
- matrizes de porta/firewall;
- runbooks;
- checkpoints;
- regras ajustadas durante implantação.

### Teste bidirecional

#### EP126 → EP125

Permitido no teste:

- 80;
- 443;
- 9102.

Bloqueado/não alcançável:

- 22;
- 3389;
- 3306;
- 5432;
- 8200;
- 9101;
- 9103;
- 1514;
- 1515;
- 55000.

#### EP125 → EP126

Permitido:

- 3306;
- 9103;
- 1514.

Bloqueado/não alcançável:

- 22;
- 80;
- 443;
- 3389;
- 5432;
- 8200;
- 9101;
- 1515;
- 55000.

ICMP entre as VMs permaneceu bloqueado.

### Resultado

O comportamento observado é compatível com allowlist entre zonas e redução de movimento lateral.

Como a conta pfSense fornecida pelo laboratório é limitada, o projeto registra o que foi **provado por comportamento** e não inventa detalhes de regras que não puderam ser auditados administrativamente.

**Estado:** segmentação funcional observada; evidência administrativa completa depende dos privilégios disponíveis.

---

## 11. Suricata

### Decisão evolutiva

O projeto inicialmente produziu dois textos aparentemente conflitantes:

- "não instalar pacote adicional na primeira subida";
- "instalar Suricata".

A decisão consolidada é por subfase:

1. rede/firewall primeiro, sem pacote adicional;
2. Suricata depois, em IDS/alert-only;
3. IPS somente depois de validar alertas/falsos positivos.

### Resultado

A ordem reduz variáveis de diagnóstico e mantém o firewall mínimo durante o bootstrap.

**Estado:** tratar como incremento; não declarar operacional sem checkpoint correspondente.

---

## 12. Twingate e desenho experimental A/B

Twingate foi preparado, mas propositalmente deixado fora do baseline inicial.

A sequência planejada permanece:

1. arquitetura segmentada sem Zero Trust;
2. Pentest A;
3. ativação Twingate;
4. Pentest B;
5. comparar redução de superfície/caminhos.

Isso preserva a capacidade de demonstrar o valor incremental do Zero Trust.

**Estado:** pendente por desenho, não por esquecimento.

---

## 13. Pendências reais

| Item | Por que permanece pendente | Critério de fechamento |
|---|---|---|
| evidência final pfSense | privilégio GUI é limitado | consolidar comportamento + evidência disponível sem bypass |
| DLP ponta a ponta | classificação já existe; transporte precisa evidência se ainda não fechada | evento sintético chegando via Agent |
| DAST ZAP | fase deliberadamente posterior à implantação | scan passivo/ativo autorizado + reteste |
| Pentest A | depende baseline estabilizado | cenários MITRE executados e registrados |
| Twingate | depende Pentest A | ativação e checkpoint |
| Pentest B | comparação pós-Zero Trust | repetir cenários e comparar |
| NTP | depende da infraestrutura institucional | relógio sincronizado ou resposta formal do suporte |
| release pipeline completa | CI atual não equivale a pipeline de release | SBOM + build/scan/handoff/checksums automatizados |

---

## 14. Leitura acadêmica da evolução

O valor do projeto não está na quantidade de ferramentas, mas no encadeamento entre elas.

Exemplos:

- Semgrep/Trivy → finding → correção/triagem → nova baseline;
- containerização → portabilidade → VM real → novo hardening;
- Wazuh readiness → Agent/FIM/YARA → teste sintético → regra 110211;
- Bacula planejado → backup → restore → SHA-256;
- pfSense planejado → implantação → teste bidirecional positivo/negativo;
- Twingate preparado → adiado para permitir comparação antes/depois.

A documentação final deve preservar essa evolução porque ela demonstra **processo de engenharia de segurança**, não apenas instalação de produtos.
