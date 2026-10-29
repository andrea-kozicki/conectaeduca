#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=/opt/conectaeduca
BRANCH=origin/docs/fase3-arquitetura-zero-trust-20261021
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"
OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"
LOG="$OUT/GA08_COMPOSE_SINTAXE_PLACEHOLDERS_$(date +%Y%m%dT%H%M%S).txt"
TMP=$(mktemp -d)
STATUS=BLOQUEADO
finish(){ rc=$?; trap - EXIT; rm -rf "$TMP"; [[ $rc -eq 0 ]] && STATUS=SINTAXE_VALIDADA || STATUS=BLOQUEADO; printf '\n## GA-08 — Compose sintaxe com placeholders — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; echo "STATUS=$STATUS"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
echo "=== GA08 COMPOSE SINTAXE ISOLADA ==="
echo "DATA=$(date -Is)"
python3 - "$ROOT" "$BRANCH" "$TMP" <<'PY'
import os,re,subprocess,sys,pathlib
root,branch,tmp=sys.argv[1:]
files=['compose.yml','compose.database.yml','compose.app-secrets.yml','compose.waf.yml','compose.waf-tls.yml','compose.waf-policy.yml','compose.host.yml','compose.vm.yml','compose.database-tls.yml','compose.audit-persistent.yml']
paths=[str(pathlib.Path(root)/'deploy/dmz'/f) for f in files]
for p in paths:
 if not os.path.isfile(p): print('BLOQUEIO=BASE_AUSENTE:'+os.path.basename(p));sys.exit(2)
overlay='deploy/dmz/compose.ga08-socket.candidate.yml'
res=subprocess.run(['git','-C',root,'show',branch+':'+overlay],capture_output=True)
if res.returncode: print('BLOQUEIO=OVERLAY_AUSENTE');sys.exit(2)
ovpath=os.path.join(tmp,'ga08.yml')
pathlib.Path(ovpath).write_bytes(res.stdout)
paths.append(ovpath)
content='\n'.join(pathlib.Path(p).read_text(errors='replace') for p in paths)
names=sorted(set(re.findall(r'\$\{([A-Za-z_][A-Za-z0-9_]*)',content)))
env={'PATH':os.environ.get('PATH','/usr/bin:/bin'),'HOME':tmp,'COMPOSE_DISABLE_ENV_FILE':'1'}
for n in names: env[n]='ga08-placeholder'
env['CONECTAEDUCA_GA08_SOCKET_DIR']=tmp+'/socket'
env['CONECTAEDUCA_GA08_NGINX_CONF']=tmp+'/nginx.conf'
env['CONECTAEDUCA_GA08_FPM_CONF']=tmp+'/fpm.conf'
# Nao criar arquivos de segredos: placeholders usados exclusivamente na interpolacao.
cmd=['docker','compose','--project-directory',root+'/deploy/dmz']
for p in paths: cmd+=['-f',p]
cmd+=['config','--quiet']
r=subprocess.run(cmd,env=env,cwd=tmp,capture_output=True)
print('VARIAVEIS_INTERPOLADAS_QUANTIDADE='+str(len(names)))
print('COMPOSE_EXIT='+str(r.returncode))
if r.returncode:
 s=r.stderr.decode(errors='replace')
 tags=[]
 for tag,pattern in [('YAML','yaml|mapping|parsing'),('SCHEMA','validating|additional properties|invalid type'),('INTERPOLACAO','required variable|not set'),('ARQUIVO','no such file|not found'),('OUTRO','.')]:
  if re.search(pattern,s,re.I):
   tags.append(tag)
   if tag!='OUTRO':break
 print('CLASSE_ERRO='+','.join(tags))
 print('ERRO_BRUTO=OCULTADO')
 sys.exit(2)
print('COMPOSE_SINTAXE=PASS')
print('VALIDACAO_AMBIENTE_REAL=NAO_REALIZADA')
print('SEGREDOS_REAIS=NAO_UTILIZADOS')
print('PRODUCAO=NAO_ALTERADA')
PY
