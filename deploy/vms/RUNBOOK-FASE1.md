# Runbook — implantação fase 1 das VMs ConectaEduca

Identidades:

- `CE-PFSENSE` / `conectaeduca-pfsense`
- `CE-UBUNTU-DMZ` / `conectaeduca-dmz`
- `CE-UBUNTU-INT` / `conectaeduca-interna`

A implantação foi organizada em blocos sequenciais. A regra operacional é:
**não avançar para a próxima pasta enquanto o checkpoint da etapa atual não
estiver aprovado**.

## Disco 0 — pfSense

Fora de `scripts/implantacao/vms/`.

Usar:

```text
deploy/pfsense/
scripts/implantacao/pfsense/
```

Sequência conceitual:

1. interfaces / IP / rotas;
2. regras mínimas de firewall e NAT;
3. Suricata IDS/IPS como incremento do pfSense;
4. logging local;
5. encaminhamento pfSense/Suricata -> Wazuh somente quando o receptor estiver definido.

O pfSense não recebe containers Docker. O incremento operacional do Suricata
deve ser versionado no bloco específico de pfSense, não misturado aos scripts
das Ubuntu.

## Disco 1 — base das Ubuntu

Pasta:

```text
scripts/implantacao/vms/00-base/
```

Ordem:

1. preencher `/etc/conectaeduca/vms/topologia.env` a partir de `deploy/vms/topologia-fase1.env.example`;
2. `00-orientar-topologia.sh` — identifica a VM pelo IP e informa o que instalar;
3. `02-configurar-identidade-ubuntu.sh`;
4. `05-preflight-ubuntu.sh` com `--topology`

Executar nas duas Ubuntu. Primeiro conferir/aplicar o hostname; depois executar
o preflight `base`. Após IP/gateway/DNS, repetir o preflight em `network` usando
uma cópia local do arquivo `*.env.example`.

## Disco 2 — CE-UBUNTU-INT

Pasta:

```text
scripts/implantacao/vms/10-interna/
```

Ordem:

1. `10-preparar-interna-fase1.sh` — MariaDB primeiro;
2. `12-preparar-wazuh-runtime-vm.sh` — runtime do Wazuh;
3. `14-preparar-openbao-vm.sh` — OpenBao local à VM;
4. `16-preparar-ferret-vm.sh` — Ferret com UI em loopback;
5. `19-checkpoint-interna-fase1.sh` — gate da VM interna.

O Wazuh só entra quando `vm.max_map_count >= 262144`.

O OpenBao desta fase não abre acesso DMZ→OpenBao e não inventa init/unseal,
custódia, TLS ou workload identity.

## Disco 3 — CE-UBUNTU-DMZ

Pasta:

```text
scripts/implantacao/vms/20-dmz/
```

Ordem:

1. transferir com segurança o mesmo `conectaeduca_db_password` usado na interna;
2. `20-preparar-segredos-dmz.sh`;
3. `22-preparar-dmz-fase1.sh`;
4. `29-checkpoint-dmz-fase1.sh`.

O overlay `deploy/dmz/compose.vm.yml` fixa:

```text
APP_ENV=production
APP_DEBUG=false
```

## Disco 4 — integração entre zonas

Pasta:

```text
scripts/implantacao/vms/30-integracao/
```

Executar na `CE-UBUNTU-DMZ`:

```text
30-checkpoint-integracao.sh
```

O checkpoint prova o caminho:

```text
CE-UBUNTU-DMZ -> pfSense -> CE-UBUNTU-INT / MariaDB
```

e a resposta HTTPS da aplicação.

## Disco 5 — Bacula

Pasta:

```text
scripts/implantacao/vms/40-bacula/
```

Executar:

```text
40-preparar-bacula-vm.sh
```

nas duas Ubuntu com o papel correspondente.

O Bacula File Daemon final é nativo. A instalação é opt-in e a ativação
permanece condicionada a TLS e credenciais finais.

## Disco 6 — evidências

Pasta:

```text
scripts/implantacao/vms/90-evidencias/
```

Em cada Ubuntu:

```text
90-coletar-evidencias.sh
```

O pacote de evidências não deve carregar `.runtime`, `.env`, chaves privadas ou
secrets.

## Deliberadamente fora da fase 1

- Twingate;
- Wazuh Agent/FIM/YARA real;
- pfSense → Wazuh syslog sem receptor definido;
- DMZ → OpenBao antes de TLS/workload identity;
- ativação do Bacula FD sem TLS e credenciais finais.


## Git / origem dos containers

Nas duas Ubuntu, clonar o repositório inteiro em `/opt/conectaeduca`, buscar as
tags e fazer checkout do freeze pré-VMs. Os arquivos Compose e Dockerfiles vêm
do Git. As imagens não: quando ausentes, Docker as obtém dos registries ou elas
podem ser carregadas a partir do handoff de imagens previamente exportado.

O `05-preflight-ubuntu.sh` registra `GIT_HEAD` e `GIT_TAG_EXATO`. Quando o cartão
de topologia contém `CONECTAEDUCA_BASELINE_COMMIT` e
`CONECTAEDUCA_BASELINE_TAG`, o stage `deploy` reprova se a VM estiver em outro
baseline.

## Disco 2.5 — transferência segura do segredo DB

Entre a interna e a DMZ use:
`scripts/implantacao/vms/15-segredos/15-transferir-db-secret.sh`.

Primeiro valide a fingerprint SSH da DMZ por canal confiável e registre a chave
em `known_hosts`. Rode `--check` antes de `--apply`.

O script não imprime o segredo, exige host key conhecida, compara SHA-256 e
grava o destino com modo 0600.

## Freeze Git

Depois do merge final em `main`, registre o commit exato e crie a tag de freeze.
Só então substitua `ALTERAR_APOS_FREEZE` no `topologia.env`.

No stage `deploy`, o preflight reprova se o commit/tag não estiverem fixados ou
se a VM estiver em outro baseline.
