# ConectaEduca — Fechamento de 31/10/2026 e plano de execução enxuto

**Escopo:** Experiência Criativa 8 / Daily 9 / Fase 3. **Origem:** saídas informadas pela responsável em 31/10 (EP126, openSUSE, painel), revisão das PRs #200/#203/#205/#206/#207/#213/#214/#215 e cartões Trello Fase 3.  
**Natureza da evidência:** observação relatada e documentada; não representa nova execução independente em VM nem teste de intrusão em produção.  
**Congelamento acadêmico planejado:** 07/11; segundo pentest previsto em 08–14/11; apresentação prevista para 17/11 (datas do plano acadêmico, confirmar com a turma).

## 1. Resultado do dia — leitura rápida

- **ZT-06 / EP126 — Connector institucional:** `conectaeduca-interna-ep126` no Docker do host EP126, `Running=true`, `Health=healthy`, `Network=host`, `RestartCount=0`; painel `Connected`. Connector pessoal Docker no openSUSE foi parado; Client Twingate no openSUSE manteve `online`. Não confundir Connector com Client.
- **ZT-07 — Resource Wazuh:** tenant `conectaeducalab`, Rede Interna, destino `127.0.0.1`, alias `wazuh.dashboard`, TCP/443, grupo `CE-SOC-OPERACAO`, política `CE-SOC-MFA-1DIA`. Sem Everyone. Dashboard Docker publicado no host `127.0.0.1:443 → container:5601`; localmente HTTP 302 (teste diagnóstico sem CA foi marcado como TLS não validado).
- **Causa de falha inicial de acesso:** Wazuh não visível enquanto `CE-SOC-OPERACAO` tinha 0 membros; após associação ficou visível. Falha inicial `curl RC=28` e `Pending` correlacionada a autenticação adicional ainda não concluída. O ícone de área de notificação KDE não apareceu, mas o Client disponibilizou `twingate auth`; após autenticação `Authentication successful`, `Auth expires in 23 hours` na coleta.
- **ZT-07.16 — conexão alcançou TLS:** `curl https://wazuh.dashboard/` por IP virtual `100.98.166.92` retornou `RC=60 TLS_VERIFY=20`, falta de confiança na CA local do Wazuh; não era novo timeout.
- **ZT-07.17–07.18C — CA pública comprovada:** CA do Dashboard em `/opt/conectaeduca/deploy/interna/wazuh/.runtime/certs/root-ca.pem`; leitura direta bloqueada pela conta. `docker cp` permitiu CA pública no home; tentativa de copiar certificado servidor não se completou e encerrou shell ao usar `set -e` de modo interativo; serviço permaneceu `healthy`. Captura do certificado público via `openssl s_client` funcionou. CA: `CA:TRUE`, fingerprint X.509 SHA256 `EE:68:D3:51:A4:AE:B9:49:D3:34:68:82:D6:9B:33:89:75:15:18:4E:6B:C9:19:36:7F:22:21:70:BF:D9:EB:A5`; cert servidor fingerprint `DB:56:D8:D9:6C:08:90:E1:DB:72:27:46:06:F2:60:CD:F8:36:10:49:5E:BE:56:F5:14:CC:20:6B:1C:2D:BE:F0`; SAN `DNS:wazuh.dashboard`; `openssl verify -CAfile ... -verify_hostname wazuh.dashboard` = `OK`, `OPENSSL_VERIFY_RC=0`. Hash do ARQUIVO CA `68fa6e5bcdeaca4f4759932619887638594f26aff5b2269a7b833db49c498065`.
- **ZT-07.19 — transporte:** `scp` direto openSUSE→EP126 `192.168.6.50:22` deu timeout; não comprova problema no Twingate, pois o Resource é somente TCP/443. Sem mudanças de pfSense, SSH, UFW ou NAT. Como Guacamole não disponibilizou transferência de arquivo, CA pública foi recebida no openSUSE via armazenamento Google Drive autorizado. A **comparação SHA-256 no destino não foi exibida**, e deverá ser comprovada posteriormente.
- **ZT-07.20 — marco positivo HTTPS remoto:** com `--cacert ~/Downloads/root-ca.pem` no openSUSE, a chamada a `https://wazuh.dashboard/` retornou **`HTTP=302 IP=100.98.166.92 TLS_VERIFY=0 CURL_RC=0`**. TLS e acesso HTTPS pelo Twingate **PASS**, mas não é prova de tela de login ou de autenticação no sistema Wazuh; cabeçalho Location não foi exibido.
- **Cliente Firefox:** ainda sem confiança explícita da CA no navegador/perfil dedicado; sem acesso confirmado à página ou login Wazuh. Não usar bypass do certificado como aceite nem compartilhar chave privada.
- **Guarda dos segredos:** somente CA e certificado servidor públicos inspecionados; nenhum token MFA, segredo do Connector, chave privada Wazuh ou credencial foi incluído no relatório. Não publicar CA em Git automaticamente.
- **Diários:** espelhos documentais GitHub atualizados; diário operacional **local** EP126 `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP126/diario.md` não recebeu automaticamente os registros pós-ZT-07.6. Último hash local confirmado do recorte anterior: `248b7e2c8d983e19741b07e62e6cc89c57a3f387411e156eb6d9439558b90b37`; novos registros locais exigem backup/validação/hashes novos.

### Matriz de aceite atual

| Área | Estado | Evidência/limite |
|---|---|---|
| Connector EP126 | **PASS operacional** | Healthy/Connected, sem prova automática de todos os fluxos |
| Resource Wazuh mínimo | **PASS configuração** | SOC, TCP 443, MFA; não substitui RBAC da aplicação |
| MFA Twingate | **PASS** | Authentication successful e sessão autorizada |
| TLS/HTTPS Wazuh remoto | **PASS** | HTTP302/verify0/RC0 com CA pública explícita |
| Firefox e login Wazuh | **PENDENTE** | Não testados |
| Negativa de acesso por identidade | **PENDENTE** | Necessário usuário sem grupo/sem acesso e telemetria |
| Reconciliar Connector com Git | **PENDENTE** | Override/runtime e digest revisados sem reinício cego |
| Exposição WAN/segmentação pfSense | **PENDENTE DE SUPORTE/DECISÃO** | Não inferir NAT WAN apenas de Resource/Connector |
| Pentest B / PA-01..PA-07 | **PENDENTE** | Testes separados por cenário com comparação antes/depois |

## 2. Mudança de abordagem: execução por pacotes e gates, não por diagnósticos isolados

**Problema:** cada suspeita vinha gerando inventário ou script isolado, com repetição de coleta, novos anexos e retrabalho.  
**Método proposto:** uma única matriz `requisito → evidência existente → lacuna → responsável → teste mínimo → aceite`, com estado `PASS / FAIL / PENDENTE / FORA DE ESCOPO`. Executar por **blocos de mudanças autorizadas**, sem alterar serviços fora da janela. Um **preflight por VM**, um **plano/diff**, execução controlada, **um pós-teste por VM**, uma evidência consolidada e seu hash. Nenhum script deve aplicar/merge/restart por padrão.

| Faixa | Bloco | Principal entrega de valor | Dependência |
|---|---|---|---|
| **P0 — externo, resolver já** | **SUP-PFSENSE** | Professor/suporte decidir fronteira portal público vs privado, NAT reverso, regras LAN33/LAN49, tráfego lateral privado e rotas externas. Receber screenshots/exports sanitizados + change window/rollback | Suporte/autoridade institucional |
| **P0 — EP125** | **WAF/PA-02 + DMZ** | Corrigir/retomar isolamento do upstream Nginx atrás do WAF; confirmar Connector DMZ e Resource portal com allow/deny por identidade; revisar publicação pública | pfSense/decisão público × privado; PR #213 |
| **P0 — EP126** | **ZT Wazuh conclusão** | Firefox perfil isolado + confiança CA, login válido, teste negativo e log Twingate/Wazuh | Já há HTTPS/MFA/TLS PASS |
| **P0 — controle de mudanças** | **Reconciliação das VMs** | GitHub→VM comparação de HEAD, Compose, imagens/digests, montagens, scripts; PR/rollback, sem deploy em massa | Suporte para snapshot e janela |
| **P1 — EP126** | **Bacula GA-09** | Director healthy é precondição; comprovar agenda autorizada, backup de teste e restore verificado por hash (BAC-05 requer decisão); não declarar backup automático sem Schedule | política de retenção/janela |
| **P1 — EP126** | **Ferret GA-06/PA-07** | Produção 2.4.3; candidato v5 fail-closed/config match ainda não homologado; priorizar resolver falso “limpo” após erro HTTP e teste controlado | PR #206/#207 e janela |
| **P1 — EP125/EP126** | **MFA app, auditoria, CA** | PR #205, PA-06 audit.log já persistente/ingestão confirmada mas retenção pendente; CA confiança entre serviços e gates do Wazuh | revisão PR #203/#205 |
| **P2 / condicional** | **OpenBao e interfaces de gestão** | Custódia de shares, AppRole/audit, exposição mínima por identidade e gates de acesso | professor/suporte |
| **Freeze / Pentest B** | **Roteiro 7 PAs** | 1 teste positivo + 1 negativo + 1 evidência por ponto relevante; marcar os não endereçados por ZTNA como limite técnico | aprovação/snapshot/controle de escopo |

**Redução de retrabalho:** não recapturar `healthy`, portas e inventários já comprovados a menos que haja mudança de imagem, Compose, horário/caminho de acesso ou prova de regressão; usar os kits **read-only** da PR #215 onde cabível; não confundir CI `PASS` com deploy na VM. Priorizar **pontos de ataque e controles** em vez de “todos os serviços”.

## 3. Pacote único para o suporte — pfSense e rede

**Pedido:** por gentileza, confirmar em uma única resposta técnica, antes de qualquer mudança, os itens abaixo relativos ao pfSense institucional e ao projeto ConectaEduca:

1. **Exposição:** decidir com professor se o portal EP125 (WAF/Nginx/PHP, 192.168.6.34) deve ser público em 80/443 mediante NAT reverso transparente ou privado via Twingate; distinguir portal final e console administrativo/URLs restritas. Não permitir que Twingate substitua RBAC da aplicação.
2. **Políticas atuais, sem segredos:** apresentar tabela/capturas sanitizadas das regras efetivas das interfaces LAN33/EP125 e LAN49/EP126, prioridades, `Default allow LAN to any`, aliases relevantes, NAT port forwards, Floating e logs/counters pertinentes. Revisar especialmente destino RFC1918 não pertencente aos segmentos autorizados, e consequências para movimento lateral (cartão Trello ZT-05).
3. **Matriz mínima de fluxos:** validar EP125→EP126 (MariaDB 3306, Wazuh 1514, Bacula 9103) e EP126→EP125 (WAF 80/443, Bacula FD 9102), além de DNS/NTP/HTTPS de saída e acesso administrativo institucional apenas do escopo aprovado. As portas da matriz são referência histórica, não autorização irrestrita automática.
4. **Connectors e VPN:** assegurar egress TCP/443 do Connector EP125/DMZ e EP126/interna a destinos oficiais do Twingate; confirmar coexistência com FortiClient/Guacamole institucional e impedir rotas redundantes via Connector pessoal.
5. **Mudanças controladas:** retornar regra específica a alterar (ID, interface, ordem, origem, destino, porta), avaliação de impacto, janela, backup do pfSense sob custódia do suporte, rollback e teste de regressão. Não enviar export XML completo com segredos nem credenciais.
6. **Critério de aceite:** provar pelo menos 1 comunicação permitida requerida, 1 negação lateral privada indevida, 1 serviço administrativo não exposto e, se autorizado, prova de WAN→WAF sem vazamento direto de backends.

**Não interpretar SCP 22 timeout como falha do Twingate:** Resource Wazuh expõe somente TCP/443 por identidade; SSH direto no IP privado EP126 é outro fluxo.

## 4. Plano para a próxima sessão

**Bloco único curto de testes (Wazuh):**
1. Conferir `sha256sum ~/Downloads/root-ca.pem` no openSUSE (deve ser `68fa6e5bcdeaca4f4759932619887638594f26aff5b2269a7b833db49c498065`).
2. Usar Firefox **perfil exclusivo** `ConectaEduca-Lab` com CA pública Wazuh adicionada apenas para sites; abrir `https://wazuh.dashboard/`, capturar login e tentar autenticação com conta autorizada.
3. Validar acesso negado por identidade **sem grupo** via procedimento aprovado; preservar evento/captura do painel Twingate e Wazuh.
4. Registrar gate, rollback e hash no diário local da EP126, sem atualizar sem a VM disponível.

**Bloco de preparo offline (sem VM):** revisar 8 PRs abertas (#200, #203, #205, #206, #207, #213, #214, #215) por impacto; preparar 2 pacotes de execução (EP125 e EP126) e pedido único pfSense para suporte; evitar nova PR para cada sintoma.

## 5. Fontes documentais e mudança de estado

- [PR #214 — evidências Twingate 31/10](https://github.com/andrea-kozicki/conectaeduca/pull/214) — permanece **draft**, não aplicada nem mergeada.
- [Consolidado ZT EP126](CONSOLIDADO-ZT-EP126-20261031-TESTES-E-PENDENCIAS.md) — histórico ZT-06–ZT-07.20, com estados superados preservados.
- [Diário-espelho GitHub EP126](DIARIO-OPERACIONAL-20261031-EP126-ZT06-GA09.md) — observações, não substitui diário local.
- [Trello ZT-06](https://trello.com/c/Rdadjeud), [ZT-07](https://trello.com/c/2lanN6ZC), [ZT-05 pfSense](https://trello.com/c/W1xNx4wx), [Reconciliação](https://trello.com/c/bYvwRICQ), [Grupo A](https://trello.com/c/Ql5kqfUS).
- **Daily 9 v29** possui snapshot operacional anterior (19h11 BRT) no bloco C9. O **C10 da v30** é a atualização posterior do dia e prevalece em caso de diferença temporal; H preserva a v27 histórica sem reger o estado atual.
