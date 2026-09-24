# Auditoria pré-freeze — 24/09/2026

## Objetivo

Separar o que já pode ser fechado no repositório do que ainda exige prova live antes do FREEZE-01.

## Fechado no repositório

- REPO-01: reconciliação #89/#91 e Fases 2–4 concluída;
- Dependabot #96 integrado;
- APPSEC-01 estrutural integrado no #104;
- GUI-01A: contrato OpenBao humano versionado;
- GUI-01B: Bacularis read-only final versionado no #105;
- gates estáticos do HEAD do #105 aprovados;
- modelo da identidade técnica `teste` documentado separando host, serviço e service account.

## Gates live ainda abertos

### HOST-01
Reconciliar EP125/EP126 com a `main` vigente antes do freeze final.

### BAC-04
1. v2.4 — staging/materializer/FileSets/Jobs/Pool;
2. v2.5 — materialização, backup, perda controlada, restore e SHA-256;
3. Schedule somente após escolha e justificativa da janela operacional.

### GUI-01C phpMyAdmin
Executar precheck na EP126, fixar imagem oficial por digest, validar candidato, aplicar loopback-only e provar SELECT permitido + DML negado com `teste`.

### Pentest sem sudo
Executar `scripts/evidencias/pentest_no_sudo_readiness.py` antes da retirada de sudo. O gate deve provar:
- `teste` nos hosts EP125/EP126;
- ausência de `teste` em sudo/wheel/docker;
- identidades mínimas nos mecanismos nativos dos serviços;
- caminhos cliente/WebGUI que não dependam de `docker exec`;
- nenhum caso de pentest dependente de root/sudo.

### TIME-01
Boundary institucional até correção pelo suporte/professor ou aceite formal do risco.

### DAST / Pentest A / Twingate / Pentest B
Continuam sequenciados; não antecipar Twingate antes do Pentest A.

## Regra para snapshots históricos

Documentos antigos com PENDENTE/FUTURE devem permanecer intactos quando forem snapshots datados. A fonte corrente é `docs/BACKLOG-TECNICO.md`.

## Critério de FREEZE-01

- Git/main coerente;
- VMs reconciliadas ou drift formalmente aceito;
- BAC-04 E2E concluído;
- caminhos sem sudo verificados;
- phpMyAdmin concluído se mantido no escopo da demonstração;
- riscos institucionais registrados;
- evidências sanitizadas/hashes consolidados;
- nenhum segredo no Git;
- plano de testes/MITRE reconciliado ao estado final.
