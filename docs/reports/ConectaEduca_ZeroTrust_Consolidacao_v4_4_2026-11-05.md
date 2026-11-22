# ConectaEduca — Zero Trust / Twingate
## Consolidação complementar v4.4 — 05/11/2026

**Autora:** Andréa Kozicki  
**Projeto:** Experiência Criativa 8 / PUCPR  
**Escopo:** evidências de 31/10 a 05/11/2026, com corte em CE-ZT38 (18h08 BRT).  
**Versão de referência:** relatório ilustrado Zero Trust **v4.3, 03/11/2026**. Este arquivo **não substitui** as páginas e figuras históricas desse documento, indisponível para edição no ambiente atual.  
**Modo:** documentação somente; **nenhuma alteração adicional em Docker, pfSense ou Twingate**.

### 1. Síntese de aceite

| Frente | Estado |
| --- | --- |
| EP125 / DMZ: Connector -> aplicação HTTPS | **PASS LOCAL CE-ZT37** (host e namespace Docker, HTTP 200; `curl -k`) |
| EP126 / Intranet: Connector -> Wazuh | **PASS LOCAL CE-ZT38** (host e namespace host, HTTP 302; `curl -k`) |
| Connectors registrados e heartbeat na nuvem | **PENDENTE / última API reportava DEAD_HEARTBEAT_TOO_OLD** |
| Saída HTTPS PubNub | **FALHA REPRODUZIDA**; conexão padrão reseta com ALPN oferecendo h2 |
| Resolução DNS pessoal openSUSE | **FALHA** para DNS virtual Twingate 100.95.0.251 |
| RBAC/MFA/TLS estrito/negação | **PENDENTE** de testes ponta a ponta atuais |
| Segmentação pfSense | **NÃO COMPROVADA**; regras personalizadas desabilitadas, permissões gerais ativas |

Um container `healthy` não comprova Connector `ALIVE`. Resposta HTTP 200/302 ao recurso a partir da rede Docker não comprova autorização pelo Twingate, MFA, certificado estrito ou isolamento de rotas alternativas.

### 2. Topologia validada

- **EP125**: `192.168.6.34`, gateway `192.168.6.33`; Connector `conectaeduca-dmz-01`, rede bridge `conectaeduca-twingate-dmz_connector-egress`. Resource `ConectaEducaAPP` -> `192.168.6.34:443`.
- **EP126**: `192.168.6.50`, gateway `192.168.6.49`; Connector `conectaeduca-twingate-connector`, `network_mode=host`; Wazuh Dashboard publicado em `127.0.0.1:443` com redirecionamento HTTP 302.
- **Políticas**: `CE-PORTAL` / `CE-PORTAL-MFA-1DIA`; `CE-SOC-OPERACAO` / `CE-SOC-MFA-1DIA`; `CE-INFRA-ADMIN` ainda sem recursos/usuários; `CE-PENTESTB-LIMITADO` vinculado ao portal.
- O FortiClient continua necessário para acesso institucional às VMs; no openSUSE há convivência com cliente Twingate.

### 3. Evidências por código

| Referência | Observação | Conclusão |
| --- | --- | --- |
| CE-ZT21 | Controller e `ps.pndsn.com` HTTPS 200; `pubsub.pubnub.com` e `h2.pubnubapi.com` TLS reset nas VMs | Falha seletiva de egress, causa ainda desconhecida |
| CE-ZT22/23 | API Read Only: Connectors EP125/EP126 `DEAD_HEARTBEAT_TOO_OLD`, três amostras sem avanço do heartbeat | Recuperação cloud **não comprovada** |
| CE-ZT26 | Script de reconciliação API Read Only na PR #213 | Ferramenta, não prova de correção |
| CE-ZT27 EP125 (17h28) | Running/healthy, 0 restarts, 6 logs PubNub TLS I/O e 6 transaction; Controller + pndsn HTTP200; pubsub + h2 curl35 | Não recriar Connector |
| CE-ZT27 EP126 (17h33) | Mesmo estado, mesmos 6+6 logs. Pubsub default curl35, forçando HTTP/1.1 HTTP200; h2 falha | Possível diferença ALPN/host/intermediário |
| CE-ZT31 | Script Read Only identidades/grupos/políticas/portas criado; **consulta ao tenant não executada** | Pendente |
| CE-ZT32/33 | Cliente openSUSE `online`, NetworkManager ativo; `resolv.conf` somente 100.95.0.251–254; rota a .251 via `wlan0` | DNS virtual Twingate inacessível na sessão |
| CE-ZT34 | `dig @1.1.1.1 raw.githubusercontent.com` responde (10 ms); `dig @100.95.0.251` timeout | Falha não é DNS público geral |
| CE-ZT35 EP125/EP126 | Mesmo IP `204.57.240.8:443`: curl padrão RC35/HTTP000/TLS1; `--http1.1` RC0/HTTP200/TLS0. Gateways .33/.49, respectivamente | TCP443 não é indiscriminadamente bloqueado |
| CE-ZT36 EP126 (17h46) | Reprodução com captura WAN hn0. ClientHello oferecendo ALPN `h2,http/1.1` seguido de reset; só `http/1.1` recebe ServerHello/HTTP200 | Investigação upstream/TLS; não prova autor RST |
| CE-ZT37 EP125 (18h05) | HTTPS `192.168.6.34` host HTTP200 RC0 e namespace Docker HTTP200 RC0 | **PASS LOCAL** |
| CE-ZT38 EP126 (18h08) | HTTPS `127.0.0.1` host HTTP302 RC0 e namespace Connector host HTTP302 RC0 | **PASS LOCAL**; `sudo` reclamou de hostname sem resolução |

**CE-ZT36 / cadeia de custódia:** `packetcapture-hn0-20261105164558.pcap` contém **38 pacotes**, snaplen 512; SHA-256 `2911ac35229349372fbcbff13b849c77a6dba46a951d9409563eedfaa43494a1`. Na WAN, reset visto com IP origem aparente `204.57.240.8:443` para `10.96.41.206:31968` (pós-NAT). Não afirmar que a origem real do reset é o servidor PubNub; equipamento intermediário pode injetá-lo. A oferta de h2 no ClientHello **não comprova negociação HTTP/2** (não houve ServerHello no fluxo falho).

### 4. pfSense — estado e cuidados

Prints de 05/11 das abas LAN33/LAN49: regras personalizadas específicas de MariaDB 3306, Wazuh 1514/1515, Bacula 9102/9103, WAF 80/443, bloqueios interzonas e egress aparecem **desabilitadas**; permitem-se fluxos amplos pelas regras `IPv4 * -> *` e `Default allow LAN to any` ainda ativas. Regras Floating personalizadas também aparecem desabilitadas.

O menu **Diagnostics > Backup & Restore** não aparece para a responsável — hipótese de privilégios limitados, ainda sem confirmação do suporte. O guacd/Guacamole teve acesso à EP126 interrompido por regras anteriores; a origem IP institucional não foi fornecida apesar de solicitação prévia. **Não** reativar regras em bloco, desligar permissões gerais, limpar state table nem mudar NAT sem backup e recuperação via console confirmados. Suporte acionado para backup/rollback e dependências institucionais.

### 5. Próximo teste

**CE-ZT39 — EXECUTADO em 05/11/2026, 18h19 BRT, EP126 (somente leitura).** Hostname `ep126-pucpr-br`, `getent ahostsv4 "$(hostname)"` sem resposta, `/etc/hosts` sem entrada com nome local, `getent hosts localhost` retornou `127.0.0.1 localhost`. Diagnóstico: `HOSTNAME_NAO_RESOLVIDO`, `ENTRADA_NAO_ENCONTRADA`; corresponde ao aviso prévio de `sudo` em CE-ZT38. **Correção não realizada**. Avaliar alteração pontual e reversível de `/etc/hosts` (sem mudança de DNS geral nem reiniciar rede), somente após confirmar convenção de mapeamento local autorizada pela instituição. Causa independente de PubNub e DNS pessoal.

```bash
echo "=== CE-ZT39 — HOSTNAME EP126 ==="
whoami
date -Is
hostname
getent ahostsv4 "$(hostname)" || echo HOSTNAME_NAO_RESOLVIDO
grep -nE '(^|[[:space:]])ep126-pucpr-br([[:space:]]|$)' /etc/hosts || echo ENTRADA_NAO_ENCONTRADA
getent hosts localhost
echo ALTERACOES=NAO
echo CE-ZT39_CONCLUIDO
```

Depois, **CE-ZT40**, principal gate de aceite: console administrativo/API Read Only deve mostrar ambos os Connectors **ALIVE** e heartbeats avançando em instantes distintos, após a rede corrigir o egress. Não reproduzir indefinidamente os mesmos resets sem intervenção do suporte.

Em seguida: executar CE-ZT31 (auditoria de portas/grupos), testar TLS estrito por alias/hostname no Wazuh e CE-ZT41 (MFA com usuário autorizado, negação com identidade independente e tentativa de rota direta, evidenciando sem bypass). A segmentação pfSense exige backup, reversão e validação do Guacamole.

**Rastreabilidade:** PR #213; cartões Trello ZT-06 (Twingate) e ZT-05 (pfSense); saídas completas CE-ZT27–38 em conversa; PCAP e screenshots originais não contidos no GitHub por política de minimização de dados.

**Nota de rigor:** CE-ZT28–30 e outros números não listados não recebem PASS implícito. CE-ZT39–41 descrevem procedimentos pendentes, não testes concluídos.
