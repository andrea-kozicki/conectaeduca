# Retomada das VMs — 24/09/2026

## Objetivo

Reduzir a retomada em casa a uma sequência curta, com checkpoints claros e sem misturar mudanças que dependem de análise de evidência.

## Regra

Não avançar automaticamente de um gate mutante para o seguinte. Cada fase gera TXT; o TXT é analisado antes da próxima alteração.

## Fase 0 — sincronizar checkout sem perder drift

Em cada VM:

```bash
cd /opt/conectaeduca
git status --short
git branch --show-current
git fetch origin
git rev-parse HEAD
git rev-parse origin/main
```

Se o checkout estiver limpo e na `main`:

```bash
git pull --ff-only origin main
```

Se houver arquivo modificado, não fazer reset/checkout forçado. Registrar o drift primeiro.

## Fase 1 — EP126 / prioridade absoluta BAC-04 v2.4

Usar o bundle já preparado:

```text
conectaeduca-bac-04b-v2.4-operational-bundle.tar.gz
```

Na EP126:

```bash
cd ~/Downloads
sha256sum -c conectaeduca-bac-04b-v2.4-operational-bundle.tar.gz.sha256
tar -xzf conectaeduca-bac-04b-v2.4-operational-bundle.tar.gz
cd conectaeduca-bac-04b-v2.4-operational
sha256sum -c SHA256SUMS
python3 conectaeduca-bac-04b-v2.4-operational-apply.py
```

Critério esperado:

```text
BAC04B_V24_OPERATIONAL_READY=YES
PRODUCER_IDENTITIES_READY=YES
STAGING_READY=YES
MATERIALIZER_READY=YES
BACULA_OPERATIONAL_RESOURCES=YES
SMOKEJOBS_PRESERVED=YES
SCHEDULE_ACTIVATED=NO
BACKUP_EXECUTED=NO
RESTORE_EXECUTED=NO
rollback_used=0
STATUS=SUCESSO
```

**Parar aqui e analisar o TXT antes do v2.5.**

## Fase 2 — EP126 / BAC-04 v2.5 E2E

Somente depois de v2.4 aprovado.

Escopo:

- materializar MariaDB;
- snapshot Raft OpenBao;
- dump do Catalog;
- Recovery State;
- preparar/rotular mídia;
- executar backup;
- remover apenas artefato descartável controlado;
- restore em destino isolado;
- comparar SHA-256;
- preservar SmokeJobs.

Schedule continua fora desta fase até existir janela operacional justificada.

## Fase 3 — EP126 / GUI-01C phpMyAdmin

O precheck está na `main`:

```bash
cd /opt/conectaeduca
python3 scripts/evidencias/gui01c_phpmyadmin_precheck.py
```

Ele não cria container e deve terminar com `APPLY_AUTHORIZED=NO`. Enviar o TXT para análise antes do Compose final.

Depois do precheck aprovado:

1. fixar imagem oficial por digest;
2. validar candidato isolado;
3. publicar somente em loopback;
4. login SQL `teste`;
5. SELECT permitido;
6. DML negado pelo MariaDB.

## Fase 4 — gate pré-pentest sem sudo

Executar antes de o suporte retirar sudo.

### EP126

```bash
cd /opt/conectaeduca
python3 scripts/evidencias/pentest_no_sudo_readiness.py
```

### EP125

```bash
cd /opt/conectaeduca
python3 scripts/evidencias/pentest_no_sudo_readiness.py
```

Enviar os dois TXT juntos.

O inventário de `/etc/passwd` dos containers é evidência, mas a ausência de `teste` no SO de um container de daemon é esperada. O gate relevante é a identidade nativa do serviço e o caminho utilizável sem sudo/docker.

## Fase 5 — fechar caminhos que ainda dependerem de privilégio

Na EP126, confirmar que `teste` consegue usar sem sudo:

- MariaDB: SELECT permitido / DML negado;
- PostgreSQL Catalog: conexão via PgBouncer loopback;
- Bacula: bconsole pelo host com Console `teste`;
- OpenBao: userpass/policy mínima;
- Wazuh: login humano read-only;
- Bacularis: login read-only;
- phpMyAdmin: login SQL read-only.

Qualquer caminho que só funcione por `docker exec` continua GAP.

## Fase 6 — pfSense SSH

Somente se professor/suporte confirmar o endpoint e a conta.

Registrar:

- IP/interface de gerenciamento;
- porta SSH;
- identidade fornecida;
- método de autenticação;
- privilégios do User Manager.

Para conta limitada, preferir apenas o privilégio de shell necessário. Não instalar/conceder sudo no pfSense como atalho.

O SSH complementa a WebGUI para consulta/evidência; não substitui a política de menor privilégio.

## Fase 7 — pré-freeze

Depois dos gates acima:

- reconciliar drift das VMs;
- Lynis EP125/EP126;
- rodada final Snyk/Semgrep/Gitleaks/CI;
- inventário final de imagens/serviços/portas;
- consolidar evidências;
- fechar riscos residuais;
- FREEZE-01.

## Depois do freeze

Ordem acadêmica preservada:

```text
DAST/ZAP
  -> Pentest A sem Twingate
  -> ativar Twingate
  -> Pentest B comparativo
  -> relatório/PPTX/demo final
```
