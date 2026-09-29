# Esqueleto do relatório final — ConectaEduca

> Documento de trabalho. Campos pendentes só devem ser preenchidos após evidência.

## 1. Introdução
- contexto;
- objetivo;
- escopo.

## 2. Arquitetura final
- diagrama;
- EP125/DMZ;
- EP126/interna;
- pfSense e fluxos mínimos;
- justificativas de segmentação e menor privilégio.

### Estado já estabelecido
- EP125 representa a zona DMZ e concentra a superfície pública protegida por
  WAF/Nginx/PHP;
- EP126 concentra serviços internos e de segurança/observabilidade;
- pfSense intermedia as zonas e aplica a segmentação;
- acessos entre zonas foram reduzidos ao necessário e egress mínimo foi
  validado anteriormente;
- o commit histórico do merge #138 é
  `df2ebd5e509c671640efddc524ec5ffbbc4714a3`;
- a `main` efetivamente congelada deve ser registrada como
  `<FREEZE_COMMIT>` no momento do freeze;
- a sincronização final das VMs com esse commit vigente ainda é HOST_GATE.

## 3. Controles implementados
### 3.1 Aplicação, MFA e RBAC — S04/S05
- MFA e RBAC local implementados;
- identidade de aplicação `teste@pucparana.com` validada como usuário;
- acesso administrativo indevido negado;
- auditoria de login/RBAC disponível.

### 3.2 WAF/CRS — S02
- ModSecurity/OWASP CRS ativo na DMZ;
- probes sintéticos já demonstraram bloqueio;
- WAF → journald → Wazuh rule 110300 revalidado pós-reboot.

### 3.3 pfSense/Suricata — S01/S03
- segmentação e egress mínimo já possuem baseline validado;
- Suricata EP125 → Wazuh foi revalidado pós-reboot;
- pfSense → Wazuh permanece pendente somente do marker assistido OPS-01.

### 3.4 MariaDB — S06
- conta de menor privilégio e acesso segmentado já validados;
- phpMyAdmin read-only comprova SELECT permitido e DML negado.

### 3.5 OpenBao
- identidade humana `teste` e controles allow/deny validados;
- credencial antiga/incorreta rejeitada após CRED-01.

### 3.6 Wazuh/FIM/YARA — S09/S10
- Manager/Indexer/Dashboard e agentes já validados;
- FIM/YARA e detecções customizadas possuem evidência histórica;
- G2/FIM EP126 já passou no readiness; repetir após sync final quando aplicável.

### 3.7 Ferret/DLP — S11/S13
- pipeline/hardening e correções APPSEC-05 já estão na `main`;
- submissão canônica é `submeter_ferret_pentest.py`;
- G3 live permanece pendente após sync final da EP126.

### 3.8 Bacula — S12/BAC-04
- backup/restore E2E concluído para MariaDB, OpenBao, Catalog e Recovery State;
- restores tiveram SHA-256 idêntico às fontes;
- risco residual: Storage compartilha domínio físico da EP126.

### 3.9 Hardening de containers — S07/S08
- non-root/cap_drop/no-new-privileges/rootfs read-only aplicados onde previsto;
- pentester não deve depender de Docker/socket;
- prova final zero-sudo permanece HOST_GATE.
### 3.10 AppSec e gates DevSecOps
- APPSEC-04 / CWE-611 — correção mergeada; fechamento formal aguarda o Snyk
  final da `main`;
- APPSEC-05 / CWE-23 Ferret — correção #141 mergeada sem suppression; fechamento
  formal usa o mesmo artifact Snyk final;
- PR #138 mergeado em
  `df2ebd5e509c671640efddc524ec5ffbbc4714a3`;
- o boundary final usa runner GitHub-hosted e identidade dedicada sem sudo;
- Repository Static Integrity, PHPUnit, Semgrep e Gitleaks passaram no push da
  `main` pós-merge;
- Snyk final — [PREENCHER APÓS WORKFLOW_DISPATCH] registrar
  `SNYK_TOTAL_RESULTS`, contagens CWE e hash do TXT sanitizado.

Registrar o risco residual do backup no mesmo domínio físico e a limitação institucional do segundo disco/partição.

## 4. Modelo de ameaça e MITRE ATT&CK

Quatro objetivos:
- movimento lateral;
- escalação de privilégios;
- evasão de mecanismos de defesa;
- vazamento de dados.

Usar a matriz MITRE canônica e não acrescentar técnica não exercitada.

## 5. Metodologia
- ativos autorizados;
- contas/dados sintéticos;
- zero-sudo;
- sem Docker/root para o atacante;
- timestamps e SHA-256;
- perda destrutiva apenas de artefato descartável.

## 6. Resultados S01–S13

Para cada cenário registrar:
- objetivo;
- origem/destino;
- identidade;
- ferramenta;
- esperado;
- observado;
- controle;
- telemetria;
- resultado;
- evidência/hash;
- reteste.

## 7. Resultados por objetivo
### 7.1 Movimento lateral
Baseline preventivo já estabelecido por segmentação pfSense, portas mínimas e
identidades de menor privilégio. [PREENCHER após Pentest A/B com observado.]

### 7.2 Escalação
Baseline já exige `teste` fora de sudo/wheel/docker e sem Docker socket.
[PREENCHER após runtime check pós-corte e Pentest A/B.]

### 7.3 Evasão
Controles de detecção já incluem WAF, Suricata, Wazuh, FIM/YARA e DLP.
[PREENCHER após tentativas autorizadas de impair defenses/evasão.]

### 7.4 Vazamento
Egress mínimo, Ferret/DLP e privacidade por dados fictícios já compõem o
baseline. [PREENCHER após S11/S13 e comparação A/B.]

## 8. Pentest A × Pentest B

| Vetor | A | B | Evidência | Observação |
|---|---|---|---|---|
| Superfície | [PREENCHER] | [PREENCHER] | | |
| Movimento lateral | [PREENCHER] | [PREENCHER] | | |
| Administração | [PREENCHER] | [PREENCHER] | | |
| Telemetria | [PREENCHER] | [PREENCHER] | | |

Não atribuir ao Twingate diferença que não tenha sido medida em teste comparável.

## 9. Limitações e riscos residuais
- TIME-01/NTP;
- domínio físico do backup;
- restrições institucionais;
- OPS-01/pfSense → Wazuh: registrar resultado do probe assistido ou boundary externo explícito;
- componentes detect-only;
- testes não executados.

## 10. Privacidade/LGPD
- dados fictícios;
- minimização;
- DLP sanitizado;
- conteúdo bruto fora do SIEM.

## 11. Conclusão
Distinguir: implementado, validado, falhou, risco aceito e melhoria futura.

## Anexos
- diagrama;
- matriz de portas;
- MITRE;
- índice/manifesto de evidências;
- SHA256SUMS;
- commit/tag de freeze;
- artifact sanitizado APPSEC-04/05 (`appsec-snyk-final.txt` + `.sha256`) sobre a ref congelada;
- S01–S13;
- BAC-04;
- comparação A/B.
