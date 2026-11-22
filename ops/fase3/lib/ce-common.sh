#!/usr/bin/env bash
# ConectaEduca Fase 3 — funcoes comuns dos kits EP125 / EP126.
# MODO SEGURO: nenhuma operacao em contêiner, servico, firewall, Git index ou CA.
set -euo pipefail
umask 077

ce_err() { printf 'ERRO=%s\n' "$*" >&2; exit 2; }
ce_notice() { printf '%s\n' "$*"; }
ce_cmd() { command -v "$1" >/dev/null 2>&1; }

ce_usage() {
cat <<'TXT'
Uso: bash ops/fase3/ep125/ce-ep125.sh [list|check TASK|plan TASK|prepare TASK|reconcile|postcheck TASK]
     bash ops/fase3/ep126/ce-ep126.sh [list|check TASK|plan TASK|prepare TASK|reconcile|postcheck TASK]
TASK EP125: twingate, waf, login, audit, tls
TASK EP126: twingate, wazuh, ferret, bacula, openbao, firewall, tls
COMANDOS PROIBIDOS: apply, deploy, restart, rollback, merge (nao automatizados).
'prepare' grava APENAS documentos no home do usuario; todos os demais sao somente leitura.
TXT
}

ce_check_host() {
  local h dh
  h="$(hostname -s)"
  [[ "$h" == "$CE_EXPECTED_HOST" ]] || ce_err "HOST_INCORRETO esperado=$CE_EXPECTED_HOST atual=$h"
  if ce_cmd docker && docker info --format '{{.Name}}' >/dev/null 2>&1; then
    dh="$(docker info --format '{{.Name}}' 2>/dev/null)"
    [[ "$dh" == "$CE_EXPECTED_HOST" ]] || ce_err "DOCKER_HOST_DIFERENTE esperado=$CE_EXPECTED_HOST atual=$dh"
    ce_notice "DOCKER_HOST=$dh"
  else
    ce_notice "DOCKER=SEM_ACESSO_OU_INDISPONIVEL"
  fi
  ce_notice "HOST=$h VM=$CE_VM"
}

ce_header() {
  printf '\n=== CE FASE3 | %s | %s | %s ===\n' "$CE_VM" "$1" "$(date -Is)"
}

ce_git() {
  local base
  base="$CE_REPO_ROOT"
  ce_header "RECONCILIACAO_GIT"
  if [[ ! -d "$base/.git" ]]; then
    ce_notice "GIT_LOCAL=NAO_ENCONTRADO caminho=$base"
    return 0
  fi
  ce_notice "GIT_LOCAL=$base"
  ce_notice "BRANCH=$(git -C "$base" branch --show-current 2>/dev/null || true)"
  ce_notice "HEAD=$(git -C "$base" rev-parse HEAD 2>/dev/null || true)"
  ce_notice "ORIGIN_MAIN_CACHE=$(git -C "$base" rev-parse --verify refs/remotes/origin/main 2>/dev/null || echo INDISPONIVEL)"
  ce_notice "DIRTY_ENTRIES=$(git -C "$base" status --porcelain=v1 --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')"
  ce_notice "INDEX_LOCAL_ONLY=SIM"
  ce_notice "REMOTO_ATUAL=NAO_CONSULTADO"
  ce_notice "NOTA=NAO foi executado git fetch, pull, reset ou checkout."
}

ce_docker_filtered() {
  local pattern
  pattern="$1"
  if ! ce_cmd docker || ! docker info >/dev/null 2>&1; then
    ce_notice "DOCKER_LISTAGEM=INDISPONIVEL"
    return 0
  fi
  docker ps -a --filter "name=$pattern" \
    --format 'Nome={{.Names}} Estado={{.Status}} Portas={{.Ports}}' 2>&1 || true
}

ce_inspect_safe() {
  local name
  name="$1"
  if ! ce_cmd docker; then return 0; fi
  if ! docker inspect "$name" >/dev/null 2>&1; then
    ce_notice "CONTAINER=$name NAO_ENCONTRADO"
    return 0
  fi
  # Nunca imprimir env, config, labels, tokens nem docker inspect bruto.
  docker inspect "$name" --format \
    'Nome={{.Name}} Running={{.State.Running}} RestartCount={{.RestartCount}} Rede={{.HostConfig.NetworkMode}} Health={{if .State.Health}}{{.State.Health.Status}}{{else}}NA{{end}}'
}

ce_local_http() {
  local url
  url="$1"
  if ! ce_cmd curl; then ce_notice "CURL=INDISPONIVEL"; return 0; fi
  curl --noproxy '*' --silent --show-error --insecure \
    --output /dev/null --connect-timeout 3 --max-time 6 \
    --write-out 'HTTP_STATUS=%{http_code} REMOTE_IP=%{remote_ip}\n' \
    "$url" 2>&1 || ce_notice "HTTP_FALHOU=SIM"
  ce_notice "TLS_CONFIANCA=NAO_VALIDADA_NESTE_SMOKE"
}

ce_listeners() {
  local regex
  regex="$1"
  if ! ce_cmd ss; then ce_notice "SS=INDISPONIVEL"; return 0; fi
  ce_notice "LISTENERS_FILTRADOS=SIM"
  ss -lntH 2>/dev/null | grep -E "$regex" || ce_notice "NENHUM_LISTENER_NESSAS_PORTAS"
}

ce_file_metadata() {
  local file
  file="$1"
  if [[ -e "$file" ]]; then
    stat -c 'FILE=%n PERMS=%a OWNER=%U GROUP=%G BYTES=%s' -- "$file" 2>&1 || true
    # Hash de arquivo e metadados apenas; nunca imprimir conteudo.
    if [[ -r "$file" ]]; then sha256sum "$file"; fi
  else
    ce_notice "FILE_AUSENTE=$file"
  fi
}

ce_task_allowed() {
  local task
  task="$1"
  case "$CE_VM:$task" in
    EP125:twingate|EP125:waf|EP125:login|EP125:audit|EP125:tls|\
    EP126:twingate|EP126:wazuh|EP126:ferret|EP126:bacula|EP126:openbao|EP126:firewall|EP126:tls) ;;
    *) ce_err "TASK_INVALIDA=$task";;
  esac
}

ce_list() {
  ce_header "TAREFAS_DISPONIVEIS"
  if [[ "$CE_VM" == EP125 ]]; then
    cat <<'TXT'
twingate  Connector DMZ + Resource privado; PR #213; reachability/painel pendentes.
waf       PA-02: acesso interno Nginx contorna WAF; alteracao exige autorizacao.
login     Login MFA/RBAC: PR #205 ainda draft; validar em homologacao.
audit     PA-06: E2E PHP->Wazuh JA COMPROVADO; falta retencao/privacidade; PR #203.
tls       Certificados, CA e publicacao HTTPS: validar antes de alterar.
TXT
  else
    cat <<'TXT'
twingate  Connector EP126 healthy; Wazuh Resource criado; E2E/MFA/TLS pendentes.
wazuh     Rules DLP, telemetria e policy; PR #206 e Wazuh 80710/FIM/YARA.
ferret    Ferret 2.4.3 ativo; v5 candidata PR #207, sem deploy definitivo.
bacula    12 Jobs historicos; schedules/backup/restore ainda nao homologados.
openbao   Unsealed/healthy; AppRole, audit e custodia de shares pendentes.
firewall  SSH/XRDP/Bacula-FD e demais listeners; pfSense/host a validar.
tls       CA do WAF EP125 e Wazuh Dashboard; nao instalar sem fingerprint.
TXT
  fi
}

ce_task_check() {
  local task
  task="$1"
  ce_task_allowed "$task"
  ce_header "CHECK:$task"
  case "$CE_VM:$task" in
    EP125:twingate)
      ce_docker_filtered 'twingate'
      ce_notice "NOTA=Estado Connected so pode ser confirmado no painel."
      ;;
    EP125:waf)
      ce_docker_filtered 'waf'
      ce_docker_filtered 'nginx'
      ce_docker_filtered 'php'
      ce_listeners ':(80|443|8080|8088)[[:space:]]'
      ce_notice "NAO_TESTADO=Bypass bridge WAF; depende de ensaio autorizado."
      ;;
    EP125:login)
      ce_docker_filtered 'php'
      ce_notice "NAO_TESTADO=Login real, MFA e ownership; requer identidades sinteticas e roteiro."
      ;;
    EP125:audit)
      ce_file_metadata '/var/log/conectaeduca/php-audit/audit.log'
      ce_docker_filtered 'php'
      ce_notice "HISTORICO=Integracao E2E PHP-Wazuh ja comprovada; nao emitir novo evento aqui."
      ;;
    EP125:tls)
      ce_listeners ':(80|443)[[:space:]]'
      ce_local_http 'https://127.0.0.1:443/'
      ;;
    EP126:twingate)
      ce_inspect_safe 'conectaeduca-twingate-connector'
      ce_notice "NAO_TESTADO=Conectividade fim a fim e negacao de identidade."
      ;;
    EP126:wazuh)
      ce_docker_filtered 'wazuh'
      ce_local_http 'https://127.0.0.1:443/'
      ce_notice "NAO_TESTADO=Regras ativas de confidence e MFA no Client."
      ;;
    EP126:ferret)
      ce_docker_filtered 'ferret'
      ce_local_http 'http://127.0.0.1:18082/'
      ce_notice "NAO_DEPLOYAR=Versao candidata v5 somente via change control."
      ;;
    EP126:bacula)
      ce_docker_filtered 'bacula'
      ce_docker_filtered 'bacularis'
      ce_notice "NAO_TESTADO=Restore real; nao executar jobs."
      if [[ -r /etc/bacula-runtime/bacula-dir.conf ]]; then
        ce_notice "FILE_CONF=LEGIVEL"
        ce_notice "JOB_DECLARACOES=$(grep -Ec '^[[:space:]]*Job[[:space:]]*\{' /etc/bacula-runtime/bacula-dir.conf || true)"
        ce_notice "SCHEDULE_DECLARACOES=$(grep -Ec '^[[:space:]]*Schedule[[:space:]]*\{' /etc/bacula-runtime/bacula-dir.conf || true)"
      else
        ce_notice "FILE_CONF=SEM_PERMISSAO_OU_AUSENTE"
      fi
      ;;
    EP126:openbao)
      ce_docker_filtered 'openbao'
      ce_notice "NAO_LEITURA=Tokens, AppRole secrets e unseal shares."
      ce_local_http 'http://127.0.0.1:18200/v1/sys/health'
      ;;
    EP126:firewall)
      ce_listeners ':(22|3390|9102|9103|1514|3306|18200|9443)[[:space:]]'
      ce_notice "AVISO=Listener nao prova reachability atraves do pfSense."
      ;;
    EP126:tls)
      ce_local_http 'https://127.0.0.1:443/'
      ce_notice "NOTA=Testar CA oficial em plano separado, sem -k, apos validar fingerprint."
      ;;
  esac
  ce_notice "ALTERACOES_RUNTIME=NAO"
}

ce_plan() {
  local task
  task="$1"
  ce_task_allowed "$task"
  ce_header "PLANO:$task"
  cat <<TXT
CHANGE_ID: [PREENCHER]
VM: $CE_VM
TASK: $task
ORIGEM: GitHub PR / Trello card / issue [REFERENCIAR]
APROVACAO: professor/suporte/responsavel [PENDENTE]
JANELA: [DEFINIR]
BASELINE: executar 'check $task' e 'reconcile', guardar hashes e referencia do pacote
ALTERACAO: [A SER IMPLEMENTADA EM SCRIPT ESPECIFICO APROVADO]
PRECONDICOES: snapshot/backup validos, caminho de administracao alternativo,
               controle de segredos, recursos e dependencias conhecidos
ROLLBACK: [COMANDOS ESPECIFICOS E PRECONDICOES A VALIDAR ANTES DO APPLY]
POSTCHECK: executar 'postcheck $task' + testes funcionais e de seguranca autorizados
ACEITE: permitido/negado por identidade, integridade e disponibilidade comprovados
ESTADO: PLAN_ONLY; NAO_IMPLANTADO_PELO_KIT
TXT
  case "$CE_VM:$task" in
    EP125:waf) ce_notice "GATE_ESPECIFICO=Demonstrar allow via WAF e negar rota direta no teste controlado.";;
    EP125:audit) ce_notice "GATE_ESPECIFICO=Revisar retencao, ACL, PII e restart; nao refazer E2E antigo.";;
    EP125:login) ce_notice "GATE_ESPECIFICO=Homologar PR205 em fixtures, TLS e MFA; rollback completo antes de deploy.";;
    EP125:twingate) ce_notice "GATE_ESPECIFICO=Confirmar Connector DMZ Connected e diferenciar portal publico/admin.";;
    EP126:ferret) ce_notice "GATE_ESPECIFICO=PR207, CI, digest, canario, smoke fail-closed e versao baseline.";;
    EP126:bacula) ce_notice "GATE_ESPECIFICO=Schedules autorizados, retention, backup real, restore e SHA256.";;
    EP126:wazuh) ce_notice "GATE_ESPECIFICO=Consultar regras efetivas; teste logtest autorizado; nao reiniciar manager.";;
    EP126:openbao) ce_notice "GATE_ESPECIFICO=Validar AppRole sem revelar valores e plano de re-unseal.";;
    EP126:firewall) ce_notice "GATE_ESPECIFICO=Mapa pfSense e acesso institucional alternativo antes de qualquer regra.";;
    EP126:twingate) ce_notice "GATE_ESPECIFICO=MFA CE-SOC-MFA-1DIA, grupo SOC, TLS e testes allow/deny.";;
    *) ce_notice "GATE_ESPECIFICO=CA, SAN, hostname e rollback verificados antes de ajuste TLS.";;
  esac
}

ce_prepare() {
  local task dir target
  task="$1"
  ce_task_allowed "$task"
  target="$HOME/ConectaEduca_Fase3_Preparacao/$CE_VM"
  install -d -m 0700 -- "$target"
  dir="$(mktemp -d "$target/$task-$(date +%Y%m%dT%H%M%S).XXXXXX")"
  ce_task_check "$task" > "$dir/01-preflight.txt" 2>&1
  ce_git > "$dir/02-reconcile.txt" 2>&1
  ce_plan "$task" > "$dir/03-change-plan.txt" 2>&1
  printf '%s\n' "vm=$CE_VM" "task=$task" "host=$(hostname -s)" \
    "generated=$(date -Is)" "runtime_changes=none" > "$dir/00-manifest.txt"
  (
    cd "$dir"
    sha256sum 00-manifest.txt 01-preflight.txt 02-reconcile.txt 03-change-plan.txt > HASHES.sha256
    sha256sum -c HASHES.sha256
  )
  ce_notice "PREPARACAO_GERADA=$dir"
  ce_notice "RUNTIME_MODIFICADO=NAO"
}

ce_main() {
  local action task
  action="$1"
  task="$2"
  case "$action" in
    help|--help|-h) ce_usage; return 0;;
    apply|deploy|restart|rollback|merge)
      ce_err "OPERACAO_NAO_AUTOMATIZADA; criar PR de change control, aprovar, implementar e revisar rollback";;
    list|check|plan|prepare|reconcile|postcheck) ;;
    *) ce_usage; ce_err "ACAO_INVALIDA=$action";;
  esac
  ce_check_host
  case "$action" in
    list) ce_list ;;
    reconcile) ce_git ;;
    check|postcheck) ce_task_check "$task" ;;
    plan) ce_plan "$task" ;;
    prepare) ce_prepare "$task" ;;
  esac
}
