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

## 3. Controles implementados
### 3.1 Aplicação, MFA e RBAC — S04/S05
### 3.2 WAF/CRS — S02
### 3.3 pfSense/Suricata — S01/S03
### 3.4 MariaDB — S06
### 3.5 OpenBao
### 3.6 Wazuh/FIM/YARA — S09/S10
### 3.7 Ferret/DLP — S11/S13
### 3.8 Bacula — S12/BAC-04
### 3.9 Hardening de containers — S07/S08
### 3.10 AppSec e gates DevSecOps
- APPSEC-04 / CWE-611 — [PREENCHER APÓS SNYK FINAL]
- APPSEC-05 / CWE-23 Ferret — [PREENCHER APÓS SNYK FINAL]
- Semgrep / Gitleaks / PHPUnit / Static Integrity — [PREENCHER NO FREEZE]

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
[PREENCHER]
### 7.2 Escalação
[PREENCHER]
### 7.3 Evasão
[PREENCHER]
### 7.4 Vazamento
[PREENCHER]

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
- evidência APPSEC-04/05 sobre a ref congelada;
- S01–S13;
- BAC-04;
- comparação A/B.
