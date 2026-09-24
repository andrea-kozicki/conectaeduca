# Auditoria pré-freeze — 24/09/2026

## Objetivo

Separar o que pode ser fechado no repositório do que ainda exige prova live
antes do FREEZE-01.

## Fechado no repositório

- REPO-01: reconciliação #89/#91 e Fases 2–4 concluída;
- Dependabot #96 integrado;
- APPSEC-01 estrutural integrado no #104;
- GUI-01A: contrato OpenBao humano versionado;
- GUI-01B: Bacularis read-only final versionado no #105;
- gates estáticos do HEAD do #105 aprovados;
- documentação de identidade técnica `teste` existe e separa host, serviço e
  service account.

## Gates de host ainda abertos

### HOST-01

Reconciliar EP125 e EP126 com a `main` vigente antes do freeze final.

### BAC-04

Prioridade operacional corrente:

1. v2.4: staging/materializer/FileSets/Jobs/Pool;
2. v2.5: materialização + backup + perda controlada + restore + SHA-256;
3. Schedule somente após escolha/justificativa da janela.

### GUI-01C phpMyAdmin

- executar precheck da EP126;
- fixar imagem oficial por digest;
- validar candidato isolado;
- aplicar loopback-only;
- provar SELECT permitido e DML negado com `teste`.

### Pentest sem sudo

Executar `scripts/evidencias/pentest_no_sudo_readiness.py` antes da remoção de
sudo e fechar os GAPs reportados.

O gate só passa quando:

- `teste` existe nos hosts EP125/EP126;
- `teste` não pertence a sudo/wheel/docker;
- os serviços de pentest têm identidade mínima no mecanismo nativo;
- os caminhos de cliente não dependem de `docker exec`;
- nenhum caso de teste exige root/sudo para produzir a evidência principal.

### TIME-01

Permanece boundary institucional até correção pelo suporte/professor ou aceite
formal de risco.

### DAST / Pentest A / Twingate / Pentest B

Continuam sequenciados e não devem ser antecipados antes do freeze aplicável.

## Snapshots históricos

Documentos antigos com estados PENDENTE/FUTURE devem permanecer intactos quando
forem explicitamente snapshots datados. A fonte corrente de pendências é
`docs/BACKLOG-TECNICO.md`.

Não corrigir retrospectivamente uma evidência histórica para fazê-la parecer
mais atual.

## Critério de FREEZE-01

Antes do freeze:

- Git/main coerente;
- VMs reconciliadas ou drift formalmente aceito;
- BAC-04 E2E concluído;
- identidades/caminhos sem sudo verificados;
- phpMyAdmin concluído se mantido no escopo da demonstração;
- riscos institucionais registrados;
- evidências sanitizadas e hashes consolidados;
- nenhum segredo no Git;
- plano de testes/MITRE reconciliado ao estado final.
