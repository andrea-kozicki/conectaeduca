#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=/opt/conectaeduca
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"
OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"
LOG="$OUT/GA08_COMPOSE_CANDIDATO_$(date +%Y%m%dT%H%M%S).txt"
TMP=$(mktemp -d)
STATUS=INCONCLUSIVO
finish() {
  rc=$?
  trap - EXIT
  rm -rf "$TMP"
  printf '\n## GA-08 — Compose candidato socket — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true
  echo "STATUS=$STATUS"
  exit "$rc"
}
trap finish EXIT
exec > >(tee "$LOG") 2>&1
python3 - "$ROOT" "$TMP" <<'PY'
import os,pathlib,re,subprocess,sys,json
root,tmp=sys.argv[1:]
names=['compose.yml','compose.database.yml','compose.app-secrets.yml','compose.waf.yml','compose.waf-tls.yml','compose.waf-policy.yml','compose.host.yml','compose.vm.yml','compose.database-tls.yml','compose.audit-persistent.yml']
paths=[str(pathlib.Path(root)/'deploy/dmz'/n) for n in names]
if not all(pathlib.Path(p).is_file() for p in paths):
 print('BLOQUEIO=COMPOSE_BASE_AUSENTE');sys.exit(2)
ref='FETCH_HEAD:deploy/dmz/compose.ga08-socket.candidate.yml'
p=subprocess.run(['git','-C',root,'show',ref],capture_output=True)
if p.returncode:
 print('BLOQUEIO=CANDIDATO_AUSENTE_EM_FETCH_HEAD');sys.exit(2)
candidate=pathlib.Path(tmp)/'compose.ga08-socket.candidate.yml'
candidate.write_bytes(p.stdout)
paths.append(str(candidate))
contents='\n'.join(pathlib.Path(x).read_text(errors='replace') for x in paths)
variables=set(re.findall(r'\$\{([A-Za-z_][A-Za-z0-9_]*)',contents))
env=os.environ.copy()
for key in variables:env[key]='/tmp/ga08-placeholder'
env.update({'COMPOSE_PROJECT_NAME':'ga08validacao','CONECTAEDUCA_DB_HOST':'192.0.2.10','CONECTAEDUCA_DB_PORT':'3306','CONECTAEDUCA_HTTP_PORT':'8080','CONECTAEDUCA_HTTPS_PORT':'8443','CONECTAEDUCA_WAF_BIND_ADDRESS':'127.0.0.1','CONECTAEDUCA_GA08_SOCKET_DIR':tmp+'/socket','CONECTAEDUCA_GA08_NGINX_CONF':tmp+'/nginx.conf','CONECTAEDUCA_GA08_FPM_CONF':tmp+'/fpm.conf'})
args=['docker','compose','-p','ga08validacao','--project-directory',root+'/deploy/dmz']
for path in paths:args.extend(['-f',path])
r=subprocess.run(args+['config','--format','json'],env=env,capture_output=True,timeout=45)
print('COMPOSE_EXIT='+str(r.returncode))
if r.returncode:
 err=r.stderr.decode('utf-8','replace').lower()
 print('CLASSE='+('VARIAVEL' if 'required' in err else 'INVALIDO' if 'invalid' in err else 'OUTRO'))
 print('STATUS=BLOQUEADO');sys.exit(2)
cfg=json.loads(r.stdout)
services=cfg.get('services',{})
for name in ['waf','nginx','php']:
 svc=services.get(name,{})
 nets=svc.get('networks',{})
 actual=sorted(nets if isinstance(nets,list) else nets.keys())
 print(name.upper()+'_REDES='+','.join(actual))
expected={'waf':['waf_backend'],'nginx':['waf_backend'],'php':['php_egress']}
net_ok=all(sorted((services.get(name,{}).get('networks') or {}).keys())==nets for name,nets in expected.items())
nginx=services.get('nginx',{})
php=services.get('php',{})
print('REDES_SEGREGADAS='+('PASS' if net_ok else 'FAIL'))
print('NGINX_GRUPO_82='+('PASS' if '82' in [str(v) for v in nginx.get('group_add',[])] else 'FAIL'))
def has_mount(svc,target):
 return any(v.get('target')==target for v in svc.get('volumes',[]) if isinstance(v,dict))
print('NGINX_SOCKET_MOUNT='+('PASS' if has_mount(nginx,'/run/conectaeduca-fpm') else 'FAIL'))
print('PHP_SOCKET_MOUNT='+('PASS' if has_mount(php,'/run/conectaeduca-fpm') else 'FAIL'))
print('PRODUCAO=NAO_ALTERADA')
checks=net_ok and '82' in [str(v) for v in nginx.get('group_add',[])] and has_mount(nginx,'/run/conectaeduca-fpm') and has_mount(php,'/run/conectaeduca-fpm')
print('STATUS='+('COMPOSE_CANDIDATO_PASS' if checks else 'COMPOSE_CANDIDATO_CONTRATO_FAIL'))
sys.exit(0 if checks else 2)
PY
STATUS=VALIDACAO_EXECUTADA
