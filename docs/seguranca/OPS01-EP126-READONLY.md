# OPS-01 — preflight read-only da EP126

> **Status 27/09/2026:** este documento descreve o preflight que foi usado para
> descobrir os gaps pós-reboot. Depois dele, WAZ-02/Rootcheck e WAF rule 110300
> foram fechados e as duas VMs foram sincronizadas com a main pós-PR #131.
> O único gate OPS-01 ainda aberto nesta linha é a correlação
> **pfSense -> Wazuh pós-reboot**. Para esse gate, usar
> `scripts/evidencias/pfsense_wazuh_postreboot_readonly.py`.
> As classificações históricas abaixo permanecem como documentação do preflight,
> não como estado atual canônico.

## Estado operacional — 27/09/2026

- WAZ-02 Rootcheck pós-reboot: **DONE**;
- WAF `rule.id=110300` pós-reboot: **DONE**;
- TIME-01: **DONE_WITH_ACCEPTED_RISK**;
- CRED-01: **DONE** em EP125 e EP126;
- pfSense -> Wazuh pós-reboot: readiness **PASS**, correlação real ainda aberta.

O único fechamento OPS-01 ainda pendente é um evento real pós-reboot com
proveniência pfSense chegando ao Wazuh. A conta WebGUI disponível não possui
`Diagnostics -> Command Prompt`; suporte institucional foi acionado em
27/09/2026 para executar um único `logger`/marker ou conceder privilégio
temporário mínimo. Não contornar esse boundary.

Para a correlação final usar
`scripts/evidencias/pfsense_wazuh_postreboot_readonly.py`. Somente
`PFSENSE_WAZUH_POSTREBOOT=CORRELATED_ALERT_PASS` fecha o gate.

## Objetivo

Deixar preparado, antes de abrir a VM, um único preflight read-only para os
gates pós-reboot que ainda dependem da EP126.

O script:

```text
scripts/evidencias/ops01_ep126_readonly.py
```

não altera configuração, não injeta tráfego de teste e não reinicia serviços.
Ele apenas coleta o estado necessário para decidir qual mudança live ainda é
necessária.

## Cobertura

O preflight cobre:

- Git/main e worktree;
- kernel e reboot-required;
- estado NTP/time;
- listener host UDP/5514;
- runtime do Wazuh Manager;
- configuração do receiver pfSense -> Wazuh;
- grupo central `conectaeduca-dmz` e materialização Rootcheck;
- presença da rule WAF `110300`;
- contagem atual de alertas `110300`.

Ele **não** declara sozinho E2E pós-reboot concluído.

No estado operacional de 27/09/2026, Rootcheck, WAF e TIME-01 já foram
fechados. Permanece separado apenas o evento correlacionado
pfSense -> UDP/5514 -> Wazuh, que depende do estímulo autorizado no pfSense.

## Execução

Na EP126, dentro do repositório atualizado:

```bash
cd /opt/conectaeduca
git switch main
git pull --ff-only

python3 scripts/evidencias/ops01_ep126_readonly.py
```

Se o usuário não possuir acesso direto ao Docker, o script tenta apenas
`sudo -n docker`, sem prompt e sem shell root. Nesse caso, antes da execução,
pode ser necessário autenticar o sudo uma única vez:

```bash
sudo -v
python3 scripts/evidencias/ops01_ep126_readonly.py
```

Não usar `sudo -s`.

## Evidência

O script cria no HOME:

```text
conectaeduca-ops01-ep126-readonly-<host>-<UTC>.txt
conectaeduca-ops01-ep126-readonly-<host>-<UTC>.txt.sha256
```

Os arquivos são criados novos, em modo 0600, com proteção contra symlink quando
suportada pelo kernel.

A saída registra cada comando executado e seu retorno.

## Classificações esperadas

### pfSense -> Wazuh

```text
PFSENSE_WAZUH_POSTREBOOT=READY_FOR_CORRELATED_PROBE
```

significa apenas que listener, Manager e receiver estão prontos para o probe
correlacionado. O fechamento exige:

```text
PFSENSE_WAZUH_POSTREBOOT=CORRELATED_ALERT_PASS
```

com o mesmo evento contendo marcador e proveniência pfSense.

### Rootcheck

```text
WAZ02_ROOTCHECK_MANAGER_SIDE=REMEDIATION_PENDING
```

é esperado enquanto as bases/referências ainda não tiverem sido
materializadas no grupo DMZ.

Após a correção central:

```text
WAZ02_ROOTCHECK_MANAGER_SIDE=READY_FOR_AGENT_VALIDATION
```

### WAF

```text
WAF_RULE110300=READY_FOR_EP125_CORRELATED_PROBE
```

significa que a regra existe no Manager; ainda é necessário gerar um novo
estímulo na EP125 para fechar a prova pós-reboot.

## Self-test de repo

Sem VM:

```bash
python3 scripts/evidencias/ops01_ep126_readonly.py --self-test
```

Resultado esperado:

```text
OPS01_EP126_READONLY_SELFTEST=PASS
```

## Segurança

O kit não:

- imprime senhas, tokens ou chaves;
- lê conteúdo de secrets Docker;
- executa `docker exec` mutante;
- usa `sudo -s`;
- reinicia/recria containers;
- altera pfSense;
- gera tráfego sintético automaticamente.

Qualquer mudança necessária após o diagnóstico deve ser executada em uma
mini-fase separada, com precheck e rollback.
