#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=/opt/conectaeduca
BRANCH=origin/docs/fase3-arquitetura-zero-trust-20261021
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"; OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"
LOG="$OUT/GA08_COMPOSE_DIAGNOSTICO_V2_$(date +%Y%m%dT%H%M%S).txt"
TMP=$(mktemp -d)
STATUS=INCONCLUSIVO
finish(){ rc=$?; trap - EXIT; rm -rf "$TMP"; printf '\n## GA-08 — Diagnóstico Compose v2 — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; echo "STATUS=$STATUS"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 COMPOSE V2 — CLASSIFICACAO SEGURA ==="
python3 - "$ROOT" "$BRANCH" "$TMP" <<'PY'
import os,re,subprocess,sys,pathlib
root,branch,tmp=sys.argv[1:]
names=['compose.yml','compose.database.yml','compose.app-secrets.yml','compose.waf.yml','compose.waf-tls.yml','compose.waf-policy.yml','compose.host.yml','compose.vm.yml','compose.database-tls.yml','compose.audit-persistent.yml']
paths=[str(pathlib.Path(root)/'deploy/dmz'/n) for n in names]
for p in paths:
 if not os.path.isfile(p): print('BLOQUEIO=ARQUIVO_BASE_AUSENTE:'+os.path.basename(p));sys.exit(2)
res=subprocess.run(['git','-C',root,'show',branch+':deploy/dmz/compose.ga08-socket.candidate.yml'],capture_output=True)
if res.returncode:print('BLOQUEIO=OVERLAY_INDISPONIVEL');sys.exit(2)
overlay=pathlib.Path(tmp)/'ga08.yml';overlay.write_bytes(res.stdout)
paths.append(str(overlay))
body='\n'.join(pathlib.Path(p).read_text(errors='replace') for p in paths)
variables=sorted(set(re.findall(r'\$\{([A-Za-z_][A-Za-z0-9_]*)',body)))
env={'PATH':os.environ.get('PATH','/usr/bin:/bin'),'HOME':tmp,'COMPOSE_PROJECT_NAME':'ga08-diagnostico'}
for name in variables:env[name]='ga08-placeholder'
for name,filename in [('CONECTAEDUCA_GA08_SOCKET_DIR','socket'),('CONECTAEDUCA_GA08_NGINX_CONF','nginx.conf'),('CONECTAEDUCA_GA08_FPM_CONF','fpm.conf')]:env[name]=str(pathlib.Path(tmp)/filename)
args=['docker','compose','--project-directory',root+'/deploy/dmz']
for p in paths:args+=['-f',p]
args+=['config','--quiet']
result=subprocess.run(args,env=env,cwd=tmp,capture_output=True)
print('COMPOSE_EXIT='+str(result.returncode))
print('VARIAVEIS_FICTICIAS='+str(len(variables)))
if result.returncode==0:print('COMPOSE_SINTAXE=PASS');sys.exit(0)
err=result.stderr.decode(errors='replace')
# Somente categorias e nomes de campos YAML conhecidos, nunca o stderr.
checks=[('CAMINHO_RELATIVO',r'relative path|path.*(invalid|not found)|invalid mount'),('YAML',r'yaml|mapping|parsing|unmarshal'),('SCHEMA',r'validating|additional properties|invalid type|unsupported config'),('INTERPOLACAO',r'required variable|not set|must be set'),('ARQUIVO',r'no such file|not found|does not exist'),('PERMISSAO',r'permission denied'),('SECRET',r'secret.*(invalid|file|missing)'),('OUTRO',r'.')]
print('CLASSE_ERRO='+next((name for name,pattern in checks if re.search(pattern,err,re.I)),'SEM_STDERR'))
print('ERRO_LINHAS='+str(len(err.splitlines())))
print('ERRO_TAMANHO_BYTES='+str(len(result.stderr)))
print('ERRO_BRUTO=NAO_EXIBIDO')
sys.exit(2)
PY
