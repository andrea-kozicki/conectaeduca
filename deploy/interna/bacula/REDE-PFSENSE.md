# Fluxos de rede Bacula / pfSense

Bacula usa três portas TCP padrão:
- 9101: Director;
- 9102: File Daemon;
- 9103: Storage Daemon.

O projeto pode parametrizá-las, mas o contrato de fluxo permanece o mesmo.

## Fluxos necessários

### Controle do Director para o File Daemon da DMZ

```text
origem: VM interna / Bacula Director
destino: VM DMZ / Bacula File Daemon
TCP 9102
```

### Dados do File Daemon da DMZ para o Storage

Após autorização do job, o File Daemon transfere os dados ao Storage Daemon:

```text
origem: VM DMZ / Bacula File Daemon
destino: VM interna / Bacula Storage Daemon
TCP 9103
```

Esse é o único fluxo iniciado da DMZ para o núcleo de backup.

### Director para Storage

Mesmo host/VM interna no desenho final, porém logicamente:

```text
Bacula Director -> Bacula Storage Daemon -> TCP 9103
```

### Console

TCP 9101 não deve ser publicado para Internet nem liberado da DMZ. Acesso
administrativo fica na rede interna/host administrativo e, futuramente, pode ser
mediado por Twingate.

## Regra pfSense alvo

- permitir Interna(Director) -> DMZ(FD): TCP 9102;
- permitir DMZ(FD) -> Interna(Storage): TCP 9103;
- negar DMZ -> Interna para o restante, salvo regras já justificadas por outros
  componentes;
- não expor 9101/9102/9103 à Internet.

## Validação efetiva em 14/09/2026

O fluxo cross-zone foi validado nas VMs finais, sem depender apenas de teste
host-level.

### Director -> File Daemon DMZ

A partir do próprio namespace de rede do container do Director na EP126:

```text
192.168.6.34:9102
connect_ex=0
```

O `bconsole` também alcançou `conectaeduca-dmz-fd` e indicou sessão usando TLS.

### File Daemon DMZ -> Storage

Na EP125:

```text
192.168.6.50:9103
connect_ex=0
```

O fluxo foi então exercitado por um backup real `DmzSmokeBackup` e por restore
real `DmzSmokeRestore`, ambos concluídos com status `T` e zero erros.

### Director -> Storage no backend

Após a promoção do `bacula-uplink`, o Director preservou simultaneamente a rede
`bacula-backend` e alcançou o Storage em TCP/9103 pelo endereço interno da rede
Docker.

A evidência completa está em:

```text
docs/evidencias/bacula-crosszone-dmz-20260914.md
```

## NAT e endereço do Storage

A configuração do Director deve usar endereço/FQDN que o File Daemon realmente
consiga alcançar. Quando Director e FD enxergarem o Storage por endereços
diferentes, usar o mecanismo equivalente a `FD Storage Address`.

## TLS

As regras de firewall restringem caminho; TLS autentica e cifra os peers.
Um controle não substitui o outro.

Na validação de 14/09/2026, o fluxo Director -> File Daemon DMZ foi comprovado
com TLS ativo.
