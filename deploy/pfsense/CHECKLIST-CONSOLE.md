# Checklist — Console do pfSense

Não execute containers antes desta etapa estar estável.

## Antes de ligar

- [ ] Confirmar três NICs virtuais.
- [ ] Registrar MAC de cada NIC.
- [ ] Saber qual NIC pertence à rede externa/laboratório.
- [ ] Saber qual NIC pertence à DMZ.
- [ ] Saber qual NIC pertence à rede interna.
- [ ] Ter IP WAN, máscara/CIDR e gateway fornecidos pelo laboratório.

## Console

- [ ] `Assign Interfaces`: atribuir WAN, DMZ e INTERNA.
- [ ] Não confiar apenas na ordem `em0/vtnet0/vmx0`; conferir MAC.
- [ ] Configurar WAN com o IP fixo fornecido.
- [ ] Configurar o endereço do pfSense na DMZ.
- [ ] Configurar o endereço do pfSense na rede INTERNA.
- [ ] Confirmar gateway default.
- [ ] Confirmar DNS/NTP conforme o laboratório.
- [ ] Não habilitar SSH nesta fase.
- [ ] Não editar `/conf/config.xml` manualmente.
- [ ] Não instalar pacotes adicionais nesta fase.

## Atenção à WAN privada

Se o IP WAN fornecido pertencer a RFC1918 (`10/8`, `172.16/12` ou `192.168/16`),
a opção de bloquear redes privadas na WAN precisa ser avaliada conforme o
desenho do laboratório. Não altere essa opção por hábito: confirme primeiro a
topologia entregue pelo professor.

## Depois

Rodar:

```sh
sh scripts/implantacao/pfsense/00-preflight-pfsense.sh
```

Depois preencher uma cópia de `deploy/pfsense/pfsense-rede.env.example` em
`/tmp/conectaeduca-pfsense.env` e executar o checkpoint de interfaces.
