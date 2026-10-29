#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=/opt/conectaeduca; BR=origin/docs/fase3-arquitetura-zero-trust-20261021
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"; OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"; LOG="$OUT/GA08_COMPOSE_SANITIZADO_$(date +%Y%m%dT%H%M%S).txt"; TMP=$(mktemp -d); STATUS=INCONCLUSIVO
finish(){ rc=$?; trap - EXIT; rm -rf "$TMP"; printf '\n## GA-08 — Compose diagnóstico sanitizado — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; echo "STATUS=$STATUS"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
python3 - "$ROOT" "$BR" "$TMP" <<'PY'
import os,pathlib,re,subprocess,sys
root,branch,tmp=sys.argv[1:]
files=['compose.yml','compose.database.yml','compose.app-secrets.yml','compose.waf.yml','compose.waf-tls.yml','compose.waf-policy.yml','compose.host.yml','compose.vm.yml','compose.database-tls.yml','compose.audit-persistent.yml']
paths=[str(pathlib.Path(root)/'deploy/dmz'/n) for n in files]
for p in paths:
 if not pathlib.Path(p).is_file():print('BLOQUEIO=BASE_AUSENTE');sys.exit(2)
r=subprocess.run(['git','-C',root,'show',branch+':deploy/dmz/compose.ga08-socket.candidate.yml'],capture_output=True)
if r.returncode:print('BLOQUEIO=OVERLAY_INDISPONIVEL');sys.exit(2)
overlay=pathlib.Path(tmp)/'overlay.yml';overlay.write_bytes(r.stdout);paths.append(str(overlay))
text='\n'.join(pathlib.Path(p).read_text(errors='replace') for p in paths)
variables=sorted(set(re.findall(r'\$\{([A-Za-z_][A-Za-z0-9_]*)',text)))
env=os.environ.copy()
for v in variables:env[v]='ga08-placeholder'
env.update({'COMPOSE_PROJECT_NAME':'ga08validacao','CONECTAEDUCA_GA08_SOCKET_DIR':tmp+'/socket','CONECTAEDUCA_GA08_NGINX_CONF':tmp+'/nginx.conf','CONECTAEDUCA_GA08_FPM_CONF':tmp+'/fpm.conf'})
args=['docker','compose','--project-directory',root+'/deploy/dmz']
for p in paths:args+=['-f',p]
args+=['config','--quiet']
p=subprocess.run(args,env=env,capture_output=True)
print('COMPOSE_EXIT='+str(p.returncode))
if p.returncode==0:print('STATUS=PASS');sys.exit(0)
raw=p.stderr.decode('utf-8','replace').strip()
# Allowlist: só imprime uma mensagem se corresponder exatamente a uma forma conhecida e não incluir valores ou caminhos.
safe=[
(r'^invalid project name$', 'invalid project name'),
(r'^no configuration file provided: not found$', 'no configuration file provided: not found'),
(r'^empty compose file$', 'empty compose file'),
(r'^no service selected$', 'no service selected'),
(r'^service .+ has neither an image nor a build context specified$', 'service <redacted> has neither an image nor a build context specified'),
]
out=next((msg for pattern,msg in safe if re.fullmatch(pattern,raw,re.I)),None)
if out:print('ERRO_SANITIZADO='+out)
else:
 print('ERRO_SANITIZADO=NAO_CORRESPONDE_ALLOWLIST')
 print('PALAVRAS='+','.join(re.sub(r'[^a-zA-Z]','',w).lower() if re.fullmatch(r'[A-Za-z]{1,18}',w) and w.lower() in {'error','failed','invalid','empty','compose','project','name','service','file','configuration','provided','found','not','no','docker','daemon','network','external','missing','required','invalid'} else '<redacted>' for w in raw.split()))
print('PRODUCAO=NAO_ALTERADA')
sys.exit(2)
PY
