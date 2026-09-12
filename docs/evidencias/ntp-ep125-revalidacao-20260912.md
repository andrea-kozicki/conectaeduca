# Evidência — revalidação NTP após retorno do suporte / EP125

Data da revalidação local: 12/09/2026  
Host: `ep125-pucpr`  
Zona: DMZ  
Status: **não encerrado / pendência institucional reaberta**

## Contexto

O suporte informou que o NTP estaria ativo e sincronizado nas VMs e encaminhou capturas de teste realizadas em 11/09/2026.

As próprias capturas, porém, mostram em EP125 e EP126:

```text
System clock synchronized: no
NTP service: active
Packet count: 0
```

Também foi executado pelo suporte:

```bash
sudo timeout 30 tcpdump -ni eth0 'udp port 123'
```

Nas capturas disponibilizadas, foram observados datagramas NTPv4 **saindo** das VMs para servidores externos em UDP/123, por exemplo:

```text
EP125:
192.168.6.34:<porta-efemera> > 91.189.91.157:123
192.168.6.34:<porta-efemera> > 185.125.190.57:123

EP126:
192.168.6.50:<porta-efemera> > 91.189.91.157:123
192.168.6.50:<porta-efemera> > 185.125.190.57:123
```

As capturas não apresentaram, no material recebido, a resposta inversa do servidor NTP para a porta efêmera do cliente.

O suporte também reiniciou `systemd-timesyncd` nas duas VMs durante o troubleshooting.

## Validação local — EP125

Foi executado um checkpoint read-only em 12/09/2026.

Resultado inicial:

```text
PASS=7
WARN=0
FAIL=1
GAP=0
```

Pontos confirmados:

- host correto;
- NTP habilitado;
- timezone `America/Sao_Paulo`;
- RTC não configurado como horário local;
- `systemd-timesyncd.service` ativo e habilitado;
- servidor NTP identificado.

Falha principal:

```text
System clock synchronized: no
NTP_SYNCHRONIZED=no
Packet count: 0
```

## Diagnóstico aprofundado — EP125

A segunda coleta, também read-only, terminou em:

```text
PASS=9
WARN=0
FAIL=4
GAP=1
```

Estado observado:

```text
NTP habilitado: sim
systemd-timesyncd: active/enabled
DNS ntp.ubuntu.com: 4 IPv4 + 3 IPv6
rota IPv4 de saída: presente
servidor selecionado: 2620:2d:4000:1::40
Packet count: 0
System clock synchronized: no
rota IPv6 global para o servidor selecionado: ausente
```

Rotas IPv6 da VM estavam limitadas a prefixos link-local `fe80::/64`; não foi encontrada rota utilizável para o servidor NTP IPv6 selecionado.

## Interpretação

O estado atual prova que:

```text
DNS                         OK
rota IPv4                   OK
systemd-timesyncd ativo     OK
NTP habilitado              OK
requisição UDP/123 saindo   observada pelo suporte

resposta NTP observada      não comprovada
Packet count > 0            não
NTPSynchronized=yes         não
rota IPv6 global            não
```

Portanto, **serviço NTP ativo não equivale a relógio sincronizado**.

O critério de encerramento desta pendência permanece:

```text
System clock synchronized: yes
```

e uma evidência de troca NTP efetiva, como:

```text
Packet count > 0
```

ou captura contendo requisição **e** resposta.

## Decisão operacional

Nenhuma alteração local foi aplicada para contornar a infraestrutura:

- não foi forçado servidor IPv4;
- não foi criado drop-in do `timesyncd`;
- não foi alterado firewall/ACL;
- não foi alterada rota;
- não foi reiniciado novamente o serviço pela equipe do projeto.

A pendência permanece classificada como **boundary institucional**, aguardando nova verificação do retorno UDP/123/NAT/ACL pelo suporte.

## Segurança e rastreabilidade

Os scripts usados foram somente leitura e geraram evidências locais com `PASS/WARN/FAIL/GAP`.

Nenhuma credencial, token, chave privada ou segredo foi coletado ou versionado.

## Estado

**NTP EP125: ainda não validado como sincronizado.**

Não marcar como concluído até que a própria VM reporte:

```text
System clock synchronized: yes
```
