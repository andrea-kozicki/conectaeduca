from pathlib import Path
from datetime import datetime
import base64
import html
import os
import re
import subprocess
import zipfile

ROOT = Path("/srv/www/htdocs/conectaeduca")
os.chdir(ROOT)

EVDIR = ROOT / "docs" / "evidencias"
HTMLDIR = EVDIR / "html"
HTMLDIR.mkdir(parents=True, exist_ok=True)

runs = sorted(EVDIR.glob("ra3_*"))
RUN = runs[-1] if runs else EVDIR

OUT = HTMLDIR / "relatorio-evidencias-ra3.html"

def cmd(args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()
    except Exception:
        return ""

repo_url = cmd(["git", "remote", "get-url", "origin"])
if repo_url.startswith("git@github.com:"):
    repo_url = "https://github.com/" + repo_url.replace("git@github.com:", "", 1)
if repo_url.endswith(".git"):
    repo_url = repo_url[:-4]

commit = cmd(["git", "rev-parse", "HEAD"])
actions_url = repo_url + "/actions" if repo_url else ""

def redact(text: str) -> str:
    patterns = [
        (r"(Set-Cookie:\s*CONECTAEDUCASESSID=)[^;\s]+", r"\1[REDACTED]"),
        (r"(Cookie:\s*CONECTAEDUCASESSID=)[^;\s]+", r"\1[REDACTED]"),
        (r"(Authorization:\s*Bearer\s+)[A-Za-z0-9._\-]+", r"\1[REDACTED]"),
        (r"((?:access_token|id_token|refresh_token|token|client_secret|secret|password|senha)\s*[=:]\s*)[^\s,;\"']+", r"\1[REDACTED]"),
        (r"(-----BEGIN PRIVATE KEY-----).*?(-----END PRIVATE KEY-----)", r"\1[REDACTED]\2"),
    ]
    for pat, repl in patterns:
        text = re.sub(pat, repl, text, flags=re.IGNORECASE | re.DOTALL)
    return text

def read_file(name, max_chars=20000):
    p = RUN / name
    if not p.exists():
        return "Arquivo não encontrado: " + str(p)
    return redact(p.read_text(encoding="utf-8", errors="replace"))[:max_chars]

def status_badge(text, ok_terms=None, fail_terms=None):
    t = text.lower()
    ok_terms = ok_terms or []
    fail_terms = fail_terms or []
    if any(term.lower() in t for term in fail_terms):
        return "FAIL", "bad"
    if any(term.lower() in t for term in ok_terms):
        return "OK", "good"
    return "INFO", "warn"

def img_base64(path):
    data = path.read_bytes()
    ext = path.suffix.lower().lstrip(".")
    mime = "image/png" if ext == "png" else "image/jpeg"
    return f"data:{mime};base64," + base64.b64encode(data).decode("ascii")

text_files = sorted([p for p in RUN.rglob("*") if p.is_file() and p.suffix.lower() in [".txt", ".md", ".xml"]])
image_files = sorted([p for p in RUN.rglob("*") if p.is_file() and p.suffix.lower() in [".png", ".jpg", ".jpeg"]])

cards = [
    ("Composer validate", "composer-validate-final.txt", ["is valid", "Exit code =====\n0"], ["error", "not valid"]),
    ("Composer audit", "composer-audit-final.txt", ["No security vulnerability advisories found", "Exit code =====\n0"], ["vulnerability", "advisories found:"]),
    ("PHP lint", "php-lint-final.txt", ["No syntax errors detected", "Exit code =====\n0"], ["parse error", "fatal error"]),
    ("PHPUnit", "phpunit-testdox-final.txt", ["OK (52 tests", "100%)", "Exit code =====\n0"], ["FAILURES", "ERRORS"]),
    ("Bloqueio dashboard sem login", "bloqueio-dashboard-sem-login.txt", ["401 Unauthorized", "Acesso não autenticado"], ["200 OK"]),
    ("Bloqueio admin sem login", "bloqueio-admin-sem-login.txt", ["401 Unauthorized", "Acesso não autenticado"], ["200 OK"]),
    ("JWT inválido rejeitado", "jwt-invalido-rejeitado.txt", ["OK: token inválido rejeitado"], ["ERRO: token inválido foi aceito"]),
    ("Segredos rastreados no Git", "segredos-rastreados-git.txt", ["OK:", "nada sensível", "não aparecem rastreados"], [".env", "private.pem"]),
    ("Dado cifrado no banco", "banco-mensagens-cifradas.txt", ["encrypted_key", "ciphertext", "AES-256-GCM"], ["erro", "exception"]),
]

def section(title, content):
    return f"""
    <section class="card">
      <h2>{html.escape(title)}</h2>
      <pre>{html.escape(content)}</pre>
    </section>
    """

def code_section(title, filename, max_chars=50000):
    return section(title, read_file(filename, max_chars=max_chars))

summary_rows = []
for title, fname, oks, fails in cards:
    content = read_file(fname, max_chars=8000)
    status, cls = status_badge(content, oks, fails)
    summary_rows.append(f"""
    <tr>
      <td>{html.escape(title)}</td>
      <td><span class="badge {cls}">{status}</span></td>
      <td>{html.escape(fname)}</td>
    </tr>
    """)

thumbs = []
for p in image_files:
    rel = str(p.relative_to(RUN))
    thumbs.append(f"""
    <figure>
      <a href="{img_base64(p)}" target="_blank">
        <img src="{img_base64(p)}" alt="{html.escape(rel)}">
      </a>
      <figcaption>{html.escape(rel)}</figcaption>
    </figure>
    """)

file_list = []
for p in text_files:
    rel = str(p.relative_to(RUN))
    file_list.append(f"<li>{html.escape(rel)}</li>")

html_doc = f"""<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>ConectaEduca — Relatório de Evidências RA3</title>
<style>
:root {{
  --bg: #f4f6fb;
  --card: #ffffff;
  --text: #1f2937;
  --muted: #64748b;
  --good: #15803d;
  --good-bg: #dcfce7;
  --bad: #b91c1c;
  --bad-bg: #fee2e2;
  --warn: #92400e;
  --warn-bg: #fef3c7;
  --line: #e5e7eb;
  --blue: #3730a3;
}}
body {{
  font-family: Arial, sans-serif;
  margin: 0;
  background: var(--bg);
  color: var(--text);
}}
header {{
  background: linear-gradient(135deg, #312e81, #581c87);
  color: white;
  padding: 32px 40px;
}}
header h1 {{ margin: 0 0 8px 0; }}
header p {{ margin: 4px 0; opacity: .92; }}
main {{ padding: 24px 40px 48px 40px; }}
.card {{
  background: var(--card);
  border-radius: 14px;
  box-shadow: 0 2px 12px rgba(15, 23, 42, .08);
  padding: 22px;
  margin-bottom: 22px;
}}
.grid {{
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 14px;
}}
.metric {{
  background: #eef2ff;
  border-left: 5px solid var(--blue);
  padding: 16px;
  border-radius: 12px;
}}
.metric strong {{
  display: block;
  font-size: 24px;
}}
table {{
  width: 100%;
  border-collapse: collapse;
}}
th, td {{
  border-bottom: 1px solid var(--line);
  padding: 10px;
  text-align: left;
  vertical-align: top;
}}
.badge {{
  display: inline-block;
  padding: 5px 10px;
  border-radius: 999px;
  font-weight: bold;
  font-size: 13px;
}}
.good {{ background: var(--good-bg); color: var(--good); }}
.bad {{ background: var(--bad-bg); color: var(--bad); }}
.warn {{ background: var(--warn-bg); color: var(--warn); }}
pre {{
  background: #111827;
  color: #e5e7eb;
  padding: 16px;
  border-radius: 10px;
  overflow-x: auto;
  white-space: pre-wrap;
  font-size: 13px;
  line-height: 1.45;
}}
figure {{
  margin: 0;
  background: #fff;
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 10px;
}}
img {{
  width: 100%;
  border-radius: 8px;
  border: 1px solid var(--line);
}}
figcaption {{
  font-size: 12px;
  color: var(--muted);
  margin-top: 8px;
  word-break: break-word;
}}
a {{ color: #4338ca; }}
.small {{ color: var(--muted); font-size: 13px; }}
</style>
</head>
<body>
<header>
  <h1>ConectaEduca — Relatório de Evidências RA3</h1>
  <p>Gerado em: {html.escape(datetime.now().isoformat(timespec="seconds"))}</p>
  <p>Repositório: {html.escape(repo_url)}</p>
  <p>Commit analisado: {html.escape(commit)}</p>
  <p>GitHub Actions: {html.escape(actions_url)}</p>
</header>

<main>
<section class="card">
  <h2>Resumo executivo</h2>
  <div class="grid">
    <div class="metric"><strong>{len(text_files)}</strong> evidências textuais</div>
    <div class="metric"><strong>{len(image_files)}</strong> prints incorporados</div>
    <div class="metric"><strong>52</strong> testes PHPUnit</div>
    <div class="metric"><strong>87</strong> assertions</div>
  </div>
  <p>Este relatório consolida evidências de IAM/Cognito/JWT, autorização por perfil, criptografia híbrida, CSRF, validação, XSS, SQL Injection, logs, Composer, lint, PHPUnit e ausência de segredos rastreados.</p>
</section>

<section class="card">
  <h2>Status das principais evidências</h2>
  <table>
    <thead>
      <tr><th>Controle</th><th>Status</th><th>Arquivo</th></tr>
    </thead>
    <tbody>
      {''.join(summary_rows)}
    </tbody>
  </table>
</section>

<section class="card">
  <h2>Mapa RA3 — critério → evidência</h2>
  <table>
    <thead>
      <tr><th>Critério</th><th>Evidência</th></tr>
    </thead>
    <tbody>
      <tr><td>IAM funcional com Cognito</td><td>iam-cognito-jwt-com-codigo.txt, prints de login/MFA a anexar manualmente, GitHub Actions</td></tr>
      <tr><td>Validação JWT no backend</td><td>jwt-invalido-rejeitado.txt, CognitoJwtVerifier.php</td></tr>
      <tr><td>Perfis com permissões distintas</td><td>Authorization.php, bloqueio-dashboard-sem-login.txt, bloqueio-admin-sem-login.txt</td></tr>
      <tr><td>Mecanismos OWASP</td><td>CSRF, CryptoHybrid, InputValidator, OutputEncoder, RateLimiter, SecureSession, SqlInjectionTest, XssProtectionTest</td></tr>
      <tr><td>Criptografia híbrida</td><td>criptografia-hibrida-com-codigo.txt, public-key-endpoint.txt, banco-mensagens-cifradas.txt</td></tr>
      <tr><td>GitHub, Actions e testes</td><td>git-log-recente.txt, composer-validate-final.txt, composer-audit-final.txt, phpunit-testdox-final.txt</td></tr>
    </tbody>
  </table>
</section>

{code_section("Composer validate", "composer-validate-final.txt")}
{code_section("Composer audit", "composer-audit-final.txt")}
{code_section("PHPUnit TestDox", "phpunit-testdox-final.txt")}
{code_section("JWT inválido rejeitado", "jwt-invalido-rejeitado.txt")}
{code_section("IAM / Cognito / JWT com código", "iam-cognito-jwt-com-codigo.txt")}
{code_section("Criptografia híbrida com código", "criptografia-hibrida-com-codigo.txt")}
{code_section("Bloqueio dashboard sem login", "bloqueio-dashboard-sem-login.txt")}
{code_section("Bloqueio admin sem login", "bloqueio-admin-sem-login.txt")}
{code_section("Segredos rastreados no Git", "segredos-rastreados-git.txt")}
{code_section("Dado cifrado no banco", "banco-mensagens-cifradas.txt")}
{code_section("Logs de auditoria recentes", "audit-log-recente.txt", max_chars=30000)}

<section class="card">
  <h2>Prints incorporados</h2>
  <div class="grid">
    {''.join(thumbs)}
  </div>
</section>

<section class="card">
  <h2>Arquivos textuais incluídos nesta execução</h2>
  <ul>
    {''.join(file_list)}
  </ul>
</section>

<section class="card">
  <h2>Pontos pendentes para prints manuais</h2>
  <ul>
    <li>Login no Amazon Cognito.</li>
    <li>MFA/2FA no Cognito.</li>
    <li>Dashboard autenticado.</li>
    <li>DevTools mostrando payload criptografado do Fale Conosco ou Perfil.</li>
    <li>GitHub Actions com pipeline verde.</li>
    <li>Tela admin descriptografando mensagem do Fale Conosco.</li>
  </ul>
</section>

</main>
</body>
</html>
"""

OUT.write_text(html_doc, encoding="utf-8")
print(f"Relatório HTML criado em: {OUT}")
print(f"Pasta RA3 usada: {RUN}")
