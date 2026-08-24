# Scripts das VMs — ordem de execução

Use as pastas como etapas sequenciais:

```text
00-base
  ↓
10-interna
  ↓
20-dmz
  ↓
30-integracao
  ↓
40-bacula
  ↓
90-evidencias
```

A pasta `lib/` não é uma etapa: contém somente funções compartilhadas.

Dentro de cada pasta, execute os arquivos pela numeração crescente. Em
`00-base`, o primeiro script é `00-orientar-topologia.sh`: ele usa o cartão de
IPs para identificar em qual Ubuntu você está e dizer qual conjunto de serviços
pertence àquela VM.

Não pule checkpoint para avançar à etapa seguinte.

A documentação operacional completa está em:

```text
deploy/vms/RUNBOOK-FASE1.md
```

## Despachante por IP

Depois de configurar `/etc/conectaeduca/vms/topologia.env`, use:

```text
00-base/07-despachar-containers-fase1.sh --topology ... --plan
```

O script detecta pfSense, DMZ ou interna pelos três IPs. Em `--apply`, somente
nas Ubuntu, ele executa o stack correspondente à máquina detectada. O pfSense
nunca recebe containers.

`15-segredos/` transfere o password DB da interna para a DMZ por SSH/SCP com validações.
