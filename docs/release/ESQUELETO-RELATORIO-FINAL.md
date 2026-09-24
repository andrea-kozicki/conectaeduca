# Esqueleto do relatório final — ConectaEduca

> Documento de trabalho. Não substituir resultados pendentes por suposições. Campos `[PREENCHER]` só devem ser completados após evidência correspondente.

## 1. Introdução

### 1.1 Contexto

[PREENCHER: cenário acadêmico e objetivo geral do ConectaEduca.]

### 1.2 Objetivo

Descrever a construção e avaliação de uma arquitetura segura para o ConectaEduca, com segmentação, menor privilégio, gestão de segredos, detecção, DLP, backup/restore e testes de intrusão controlados.

### 1.3 Escopo

- aplicação ConectaEduca;
- EP125/DMZ;
- EP126/rede interna;
- pfSense;
- WAF;
- MariaDB;
- OpenBao;
- Wazuh;
- Ferret;
- Bacula;
- Twingate somente após Pentest A.

## 2. Arquitetura final

### 2.1 Visão geral

[INSERIR diagrama final.]

### 2.2 Zonas e fluxos

[PREENCHER com a matriz final de fluxos permitidos/bloqueados.]

### 2.3 Justificativas de arquitetura

Explicar:

- DMZ separada da rede interna;
- serviços administrativos não publicados externamente;
- egress mínimo;
- loopback para WebGUIs administrativas quando aplicável;
- service accounts separadas de identidades humanas;
- zero-sudo no pentest.

## 3. Controles de segurança

### 3.1 Aplicação, autenticação, RBAC e MFA

Evidências relacionadas: S04 e S05.

### 3.2 WAF / ModSecurity CRS

Evidência relacionada: S02.

### 3.3 Segmentação pfSense e Suricata

Evidências relacionadas: S01 e S03.

### 3.4 MariaDB e menor privilégio

Evidência relacionada: S06.

### 3.5 OpenBao

Descrever segregação entre identidades humanas e AppRoles/workloads, custódia fora do Git e policies mínimas.

### 3.6 Wazuh / SIEM / FIM / YARA

Evidências relacionadas: S09 e S10.

### 3.7 Ferret / DLP / privacidade

Evidências relacionadas: S11 e S13.

### 3.8 Bacula / resiliência

Evidência relacionada: S12 e BAC-04.

Registrar explicitamente o risco residual de armazenamento no mesmo domínio físico da EP126 devido à restrição institucional de não disponibilizar segundo disco/partição.

### 3.9 Hardening de containers

Evidências relacionadas: S07 e S08.

## 4. Modelo de ameaça e MITRE ATT&CK

### 4.1 Objetivos avaliados

- movimento lateral;
- escalação de privilégios;
- evasão de mecanismos de defesa;
- vazamento de dados.

### 4.2 Mapeamento

Usar `docs/seguranca/MITRE-ATTACK-MATRIZ-FINAL.md` como fonte de rastreabilidade e atualizar somente com técnicas efetivamente exercitadas.

## 5. Metodologia dos testes

### 5.1 Condições do laboratório

- ativos exclusivamente autorizados;
- contas e dados sintéticos;
- zero-sudo durante pentest;
- nenhuma dependência de Docker/root para o atacante;
- evidências com timestamp e SHA-256;
- testes destrutivos limitados a artefatos descartáveis.

### 5.2 Pentest A

[PREENCHER após execução.]

Twingate deve permanecer inativo.

### 5.3 Twingate

[PREENCHER somente após Pentest A.]

### 5.4 Pentest B

[PREENCHER após execução comparativa.]

## 6. Resultados S01–S13

Usar a mesma estrutura para cada cenário.

### S01 — Perímetro

- objetivo:
- origem:
- destino:
- identidade:
- ferramenta:
- esperado:
- observado:
- controle:
- telemetria:
- resultado:
- evidência/hash:
- reteste:

[REPETIR S02 ... S13.]

## 7. Resultados por objetivo

### 7.1 Movimento lateral

[PREENCHER com S01/S03 e demais evidências relevantes.]

### 7.2 Escalação de privilégios

[PREENCHER com S05/S08 e demais evidências relevantes.]

### 7.3 Evasão de mecanismos de defesa

[PREENCHER com S09/S10 e demais evidências relevantes.]

### 7.4 Vazamento de dados

[PREENCHER com S06/S07/S11/S13 e demais evidências relevantes.]

## 8. Comparação Pentest A × Pentest B

| Vetor | Pentest A | Pentest B | Evidência | Observação |
|---|---|---|---|---|
| Superfície acessível | [PREENCHER] | [PREENCHER] | [PREENCHER] | |
| Movimento lateral | [PREENCHER] | [PREENCHER] | [PREENCHER] | |
| Administração | [PREENCHER] | [PREENCHER] | [PREENCHER] | |
| Telemetria | [PREENCHER] | [PREENCHER] | [PREENCHER] | |

Não declarar causalidade além do que os testes comparáveis sustentarem.

## 9. Limitações e riscos residuais

Incluir, conforme o estado final:

- TIME-01/NTP;
- domínio físico de backup compartilhado;
- dependências institucionais;
- componentes detect-only;
- limitações de escopo do laboratório;
- ausência de testes que não tenham sido autorizados/executados.

## 10. Privacidade e LGPD

Descrever minimização, uso de dados fictícios, sanitização de DLP/SIEM e ausência de dados pessoais reais nos testes.

## 11. Conclusão

[PREENCHER após Pentest B e consolidação das evidências.]

A conclusão deve distinguir:

- controle implementado;
- controle validado;
- controle que falhou;
- risco residual aceito;
- melhoria futura.

## Anexos

- diagrama final;
- matriz de portas;
- matriz MITRE;
- inventário de evidências;
- SHA256SUMS;
- referência ao commit/tag de freeze;
- outputs S01–S13;
- evidências BAC-04;
- comparação Pentest A/B.
