#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=/opt/conectaeduca
BASE="$HOME/ConectaEduca_Fase2_Evidencias/EP125"; OUT="$BASE/GA08"; DIARIO="$BASE/diario.md"
mkdir -p "$OUT"; LOG="$OUT/GA08_COMPOSE_ERRO_PRECISO_$(date +%Y%m%dT%H%M%S).txt"
TMP=$(mktemp -d); STATUS=INCONCLUSIVO
finish(){ rc=$?; trap - EXIT; rm -rf "$TMP"; printf '\n## GA-08 — Compose erro preciso — %s\nStatus: %s\nEvidência: %s\nProdução: não alterada\n' "$(date -Is)" "$STATUS" "$LOG" >> "$DIARIO" || true; echo "STATUS=$STATUS"; exit "$rc"; }
trap finish EXIT
exec > >(tee "$LOG") 2>&1
python3 - "$ROOT" "$TMP" <<'PY'
import os,re,subprocess,sys,pathlib
root,tmp=sys.argv[1:]
branch='origin/docs/fase3-arquitetura-zero-trust-20261021'
names=['compose.yml','compose.database.yml','compose.app-secrets.yml','compose.waf.yml','compose.waf-tls.yml','compose.waf-policy.yml','compose.host.yml','compose.vm.yml','compose.database-tls.yml','compose.audit-persistent.yml']
paths=[str(pathlib.Path(root)/'deploy/dmz'/n) for n in names]
for p in paths:
 if not pathlib.Path(p).is_file(): print('BLOQUEIO=ARQUIVO_BASE_AUSENTE');sys.exit(2)
r=subprocess.run(['git','-C',root,'show',branch+':deploy/dmz/compose.ga08-socket.candidate.yml'],capture_output=True)
if r.returncode:print('BLOQUEIO=OVERLAY_INDISPONIVEL');sys.exit(2)
overlay=pathlib.Path(tmp)/'ga08.yml';overlay.write_bytes(r.stdout);paths.append(str(overlay))
body='\n'.join(pathlib.Path(p).read_text(errors='replace') for p in paths)
names=sorted(set(re.findall(r'\$\{([A-Za-z_][A-Za-z0-9_]*)',body)))
env=os.environ.copy()
for name in names:env[name]='ga08-placeholder'
env.update({'CONECTAEDUCA_GA08_SOCKET_DIR':tmp+'/socket','CONECTAEDUCA_GA08_NGINX_CONF':tmp+'/nginx.conf','CONECTAEDUCA_GA08_FPM_CONF':tmp+'/fpm.conf','COMPOSE_PROJECT_NAME':'ga08validacao'})
cmd=['docker','compose','--project-directory',root+'/deploy/dmz']
for p in paths:cmd+=['-f',p]
cmd+=['config','--quiet']
p=subprocess.run(cmd,env=env,capture_output=True)
print('COMPOSE_EXIT='+str(p.returncode))
if p.returncode==0:print('COMPOSE_SINTAXE=PASS');sys.exit(0)
raw=p.stderr.decode('utf-8','replace').strip()
# Exibir somente mensagem se pertencer a um conjunto seguro conhecido; sem paths, nomes de variaveis ou valores.
patterns=[
 ('SEM_CONFIG',r'no configuration file provided'),
 ('SEM_COMPOSE',r'no such file or directory'),
 ('INVALID_PROJECT',r'invalid project name'),
 ('INVALID_FLAG',r'unknown flag'),
 ('COMPOSE_PARSE',r'parsing|yaml|unmarshal'),
 ('COMPOSE_SCHEMA',r'validating|additional properties|invalid type'),
 ('ENV_REQUIRED',r'required variable|is required|is not set'),
 ('INVALID_OVERRIDE',r'override|reset'),
 ('EMPTY_COMPOSE',r'empty compose file'),
 ('MISSING_FILE',r'file not found|does not exist'),
 ('PERMISSION',r'permission denied'),
 ('EXEC',r'executable file not found'),
]
hits=[label for label,pat in patterns if re.search(pat,raw,re.I)]
print('CLASSES='+(','.join(hits) if hits else 'NAO_IDENTIFICADO'))
print('STDERR_BYTES='+str(len(p.stderr)))
print('STDERR_CARACTERES='+str(len(raw)))
print('STDERR_APENAS_ASCII='+str(raw.isascii()))
# Permite reconhecer a mensagem sem revelar conteudo: cada palavra reduzida ao comprimento e categoria.
tokens=re.findall(r'\S+',raw)
print('TOKEN_LENGTHS='+','.join(str(len(t)) for t in tokens[:25]))
print('STDERR_BRUTO=OCULTADO')
print('PRODUCAO=NAO_ALTERADA')
sys.exit(2)
PY
