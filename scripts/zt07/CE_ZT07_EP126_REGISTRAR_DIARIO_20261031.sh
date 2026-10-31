#!/usr/bin/env bash
# ConectaEduca - EP126 / ZT-07.1 e ZT-07.2 - diario incremental.
# Registra resultados ja apresentados pela operadora em 31/10/2026.
# Nao altera Docker, Wazuh, Twingate, rede, pfSense ou tokens.
set -euo pipefail
set +x
umask 077

BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP126"
DIARIO="$BASE/diario.md"
MARCADOR="CE-ZT07-EP126-WAZUH-20261031"

if [[ "$(hostname -s)" != "ep126-pucpr-br" ]]; then
    echo "ERRO_HOST=NAO_EP126" >&2
    exit 2
fi
if [[ ! -f "$DIARIO" || ! -r "$DIARIO" || ! -w "$DIARIO" ]]; then
    echo "ERRO_DIARIO=INDISPONIVEL" >&2
    exit 3
fi

exec 9>"$BASE/.diario-zt07.lock"
flock -n 9 || { echo "ERRO=DIARIO_EM_USO" >&2; exit 4; }

if grep -Fq "$MARCADOR" "$DIARIO"; then
    echo "REGISTRO_JA_EXISTE=SIM"
    echo "ALTERACOES_REALIZADAS=NAO"
    sha256sum "$DIARIO"
    exit 0
fi

TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
BACKUP="$DIARIO.bak.ZT07-$TIMESTAMP"
TMP="$(mktemp "$BASE/.diario-ZT07.XXXXXX")"
trap 'rm -f -- "$TMP"' EXIT

HASH_ANTES="$(sha256sum "$DIARIO" | awk '{print $1}')"
cp -p -- "$DIARIO" "$BACKUP"
cp -p -- "$DIARIO" "$TMP"

cat >> "$TMP" <<'REGISTRO'

---
## CE-ZT07-EP126-WAZUH-20261031 — Inventario focal e acesso Wazuh (31/10/2026, BRT)

### ZT-07.1 — Retificacao do alvo, 19:27:12 BRT
- A arquitetura atual da Intranet usa Wazuh, nao Graylog. O teste anterior contra Graylog/9000 serviu apenas para demonstrar ausencia daquele servico, e nao e falha do Twingate ou do Wazuh.
- docker ps --filter name=graylog: nenhum conteiner listado.
- ss -lnt (sport=9000): nenhum listener.
- curl http://127.0.0.1:9000/: HTTP=000, CONNECT=0.000000, RC=7.
- curl http://192.168.6.50:9000/: HTTP=000, CONNECT=0.000000, RC=7.
- Resultado classificado: alvo fora da arquitetura. NAO criar Resource Graylog. Nenhuma alteracao realizada.

### ZT-07 — Identificacao Wazuh em Docker, 19:30:28 BRT
- systemctl is-active: wazuh-manager=inactive; wazuh-dashboard=inactive; wazuh-indexer=inactive; wazuh-agent=active. Os tres primeiros sao executados por Docker e o agente do host e um servico systemd.
- conectaeduca-wazuh-wazuh.manager-1: Up 10 hours (healthy); 1515-1516/tcp internos; 192.168.6.50:1514->1514/tcp; 55000/tcp interno; 192.168.6.50:5514->514/udp.
- conectaeduca-wazuh-wazuh.dashboard-1: Up 10 hours (healthy); 443/tcp no container; publicacao 127.0.0.1:443->5601/tcp.
- conectaeduca-wazuh-wazuh.indexer-1: Up 10 hours (healthy); 9200/tcp interno.
- ss -lnt: listeners relevantes 192.168.6.50:1514 e 127.0.0.1:443.
- Resultado classificado: Wazuh operacional por Docker nas evidencias coletadas. Manager e Indexer NAO devem ser publicados como Resources gerais.

### ZT-07.2 — Conectividade do Wazuh Dashboard, 19:33:21 BRT
- Dashboard conectaeduca-wazuh-wazuh.dashboard-1: Running=true; Health=healthy; RestartCount=0.
- docker port: 5601/tcp -> 127.0.0.1:443.
- Rede Docker: conectaeduca-wazuh_wazuh-backend; IP observado 172.19.0.3 (atribuicao dinamica, nao tratar como endereco permanente).
- curl -k https://127.0.0.1:443/: HTTPS_LOOPBACK=302, REMOTE_IP=127.0.0.1, RC=0.
- curl -k https://172.19.0.3:5601/: HTTPS_DOCKER=302, REMOTE_IP=172.19.0.3, RC=0.
- HTTP 302 indica resposta HTTPS com redirecionamento, NAO login funcional, confianca TLS ou autorizacao ZT. -k desabilitou a verificacao do certificado apenas durante o teste.
- Resultado classificado: caminho local HOST->Dashboard e HOST->Docker comprovados; nenhum Resource criado e nenhuma alteracao realizada.

### Limitacoes e proximos gates
- Confirmar destino do redirecionamento 302 e TLS com hostname adequado.
- Nao cadastrar 127.0.0.1 como Resource remoto sem comprovar enderecamento no cliente. IP 172.19.0.3 e dinamico e pode nao ser alcancado pelo Connector do openSUSE.
- Selecionar rota/nome estavel para o Dashboard a partir do Connector EP126 sem expor a interface indiscriminadamente.
- Definir grupo Operacao/SOC (e Administracao se aprovado), MFA e TCP/443 ou porta efetiva; nao publicar portas de ingestao/API/Indexer indiscriminadamente.
- Testes E2E positivo/negativo, client->Connector EP126->Dashboard, sem FortiClient quando autorizado, isolamento do Connector pessoal e retestes PA-01..07 permanecem PENDENTES.
- Fontes: saidas fornecidas pela operadora na sessao de 31/10/2026. Nao foram copiados tokens nem logs de autenticacao.
REGISTRO

printf '\nRegistro efetuado em %s no host %s.\n' "$(date -Is)" "$(hostname -s)" >> "$TMP"

mv -f -- "$TMP" "$DIARIO"
trap - EXIT
sha256sum "$DIARIO" > "$BASE/diario.sha256"

echo "RESULTADO=DIARIO_LOCAL_ZT07_ATUALIZADO"
echo "MARCADOR=$MARCADOR"
echo "BACKUP=$BACKUP"
echo "DIARIO=$DIARIO"
echo "SHA256_ANTES=$HASH_ANTES"
echo "SHA256_DEPOIS=$(sha256sum "$DIARIO" | awk '{print $1}')"
echo "ALTERACAO_DOCKER_WAZUH_TWINGATE=NAO"
