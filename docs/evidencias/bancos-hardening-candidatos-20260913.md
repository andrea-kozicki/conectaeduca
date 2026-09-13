# Card #43 — candidatos de hardening MariaDB + PostgreSQL/Bacula Catalog

Data de validação: 2026-09-13
Host de bancada: `ep126-pucpr`
Baseline Git: `f58e3f0069c2dc1249ff146e39ec6d5f0c192134`

## Resultado

A auditoria residual e os candidatos isolados foram executados sem mutação dos
containers ou volumes live.

### MariaDB

Candidato `full` aprovado na bancada v4:

- `read_only=true`;
- `no-new-privileges=true`;
- `cap_drop=ALL`;
- bootstrap com `CHOWN`, `SETUID` e `SETGID`;
- `pids_limit=256`;
- `/tmp` e `/run/mariadb` em `tmpfs`;
- daemon final UID 999 e `CapEff=NONE`;
- autenticação positiva/negativa validada;
- senha por `_FILE`.

### PostgreSQL / Bacula Catalog

Candidato forte `robust-bootstrap` aprovado na bancada v7 em fresh init e
restart do mesmo container:

- `read_only=true`;
- `no-new-privileges=true`;
- `cap_drop=ALL`;
- bootstrap com `CHOWN`, `SETUID`, `SETGID`, `FOWNER` e `DAC_OVERRIDE`;
- `pids_limit=256`;
- `/tmp` e `/var/run/postgresql` em `tmpfs`;
- daemon final UID 999, `CapEff=NONE` e `NoNewPrivs=1`;
- 5432 sem publicação no host;
- `POSTGRES_PASSWORD_FILE`;
- `pg_hba.conf` sem `trust`;
- SCRAM e logging de conexões;
- fresh init + restart `healthy`.

## Segredo administrativo do Catalog

O runtime atual ainda usa `POSTGRES_PASSWORD` em `.runtime/catalog.env`.
Este commit adapta `catalog`, `catalog-init` e `catalog-role-init` para o
segredo por arquivo. A migração live fica para o gate de promoção.

## Decisões

- CPU/RAM: ACCEPT pré-freeze; dimensionar com telemetria mais longa.
- Director ausente no primeiro auditor: falso positivo de labels.
- Fresh-volume hardening: FIX declarativo.
- Senha administrativa no environment: FIX por `_FILE`.
- MariaDB/Catalog: candidatos aprovados, ainda não promovidos live.

Bundle validado:
`fd56247902c120f257480be4650807a11c7db5df343134a4e4bbb10046fa1054`
