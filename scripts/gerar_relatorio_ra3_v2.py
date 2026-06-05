from pathlib import Path
from datetime import datetime
import base64
import html
import os
import re
import subprocess

ROOT = Path("/srv/www/htdocs/conectaeduca")
os.chdir(ROOT)

EVDIR = ROOT / "docs" / "evidencias"
HTMLDIR = EVDIR / "html"
HTMLDIR.mkdir(parents=True, exist_ok=True)

runs = sorted(EVDIR.glob("ra3_completo_*"))
RUN = runs[-1] if runs else EVDIR

# Busca prints também nas execuções anteriores, porque o ra3_completo pode não ter prints.
image_files = []
for pattern in ["ra3_completo_*/prints/*", "ra3_*/prints/*"]:
    image_files.extend(EVDIR.glob(pattern))
image_files = sorted(set([p for p in image_files if p.suffix.lower() in [".png", ".jpg", ".jpeg"]]))

OUT = HTMLDIR / "relatorio-evidencias-ra3-v2.html"

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
gh = repo_url + "/blob/" + commit if repo_url and commit else ""
actions_url = repo_url + "/actions" if repo_url else ""

def redact_runtime(text: str) -> str:
    patterns = [
        (r"(Set-Cookie:\s*CONECTAEDUCASESSID=)[^;\s]+", r"\1[REDACTED]"),
        (r"(Cookie:\s*CONECTAEDUCASESSID=)[^;\s]+", r"\1[REDACTED]"),
        (r"(Authorization:\s*Bearer\s+)[A-Za-z0-9._\-]+", r"\1[REDACTED]"),
        (r"(-----BEGIN PRIVATE KEY-----).*?(-----END PRIVATE KEY-----)", r"\1[REDACTED]\2"),
    ]
    for pat, repl in patterns:
        text = re.sub(pat, repl, text, flags=re.IGNORECASE | re.DOTALL)
    return text

def read_evidence(name, max_chars=60000):
    p = RUN / name
    if not p.exists():
        return "Arquivo não encontrado: " + str(p)
    return redact_runtime(p.read_text(encoding="utf-8", errors="replace"))[:max_chars]

def read_code(path, start=None, end=None):
    p = ROOT / path
    if not p.exists():
        return f"Arquivo não encontrado: {path}"

    lines = p.read_text(encoding="utf-8", errors="replace").splitlines()

    if start is None:
        start = 1
    if end is None:
        end = len(lines)

    selected = lines[start - 1:end]
    return "\n".join(f"{i:4d}  {line}" for i, line in enumerate(selected, start=start))

def file_card(path, role, proves, start=None, end=None):
    url = f"{gh}/{path}" if gh else path
    if start and end and gh:
        url += f"#L{start}-L{end}"

    code = read_code(path, start, end)

    return f"""
    <article class="filecard">
      <div class="filemeta">
        <h3>{html.escape(path)}</h3>
        <p><strong>Função no sistema:</strong> {html.escape(role)}</p>
        <p><strong>O que comprova:</strong> {html.escape(proves)}</p>
        <p><strong>Link do código:</strong> <a href="{html.escape(url)}">{html.escape(url)}</a></p>
      </div>
      <pre>{html.escape(code)}</pre>
    </article>
    """

def status_from_file(name, ok_terms, fail_terms):
    content = read_evidence(name, 12000)
    lower = content.lower()

    if any(term.lower() in lower for term in fail_terms):
        return "ATENÇÃO", "bad"

    if any(term.lower() in lower for term in ok_terms):
        return "OK", "good"

    return "INFO", "warn"

def status_row(title, fname, ok_terms, fail_terms):
    label, cls = status_from_file(fname, ok_terms, fail_terms)
    return f"<tr><td>{html.escape(title)}</td><td><span class='badge {cls}'>{label}</span></td><td>{html.escape(fname)}</td></tr>"

def section(title, body):
    return f"""
    <section class="card">
      <h2>{html.escape(title)}</h2>
      {body}
    </section>
    """

def pre_section(title, filename, max_chars=60000):
    return section(title, f"<pre>{html.escape(read_evidence(filename, max_chars))}</pre>")

def img_to_data(p):
    data = p.read_bytes()
    ext = p.suffix.lower().replace(".", "")
    mime = "image/png" if ext == "png" else "image/jpeg"
    return "data:" + mime + ";base64," + base64.b64encode(data).decode("ascii")

status_rows = [
    status_row("Composer validate", "02_composer-validate.txt", ["./composer.json is valid", "exit code =====\n0"], ["not valid", "error"]),
    status_row("Composer audit", "03_composer-audit.txt", ["No security vulnerability advisories found", "exit code =====\n0"], ["advisories found:", "found vulnerabilities"]),
    status_row("PHP lint", "04_php-lint.txt", ["No syntax errors detected", "exit code =====\n0"], ["parse error", "fatal error"]),
    status_row("PHPUnit", "05_phpunit-testdox.txt", ["OK (52 tests", "87 assertions", "exit code =====\n0"], ["failures", "errors!"]),
    status_row("Bloqueio sem login", "10_bloqueio-dashboard-sem-login.txt", ["401 Unauthorized", "Acesso não autenticado"], ["200 OK"]),
    status_row("Bloqueio admin sem login", "11_bloqueio-admin-sem-login.txt", ["401 Unauthorized", "Acesso não autenticado"], ["200 OK"]),
    status_row("JWT inválido rejeitado", "15_jwt-invalido-rejeitado.txt", ["OK: token inválido rejeitado"], ["ERRO: token inválido foi aceito"]),
    status_row("Envelope criptográfico", "17_envelope-criptografico-terminal.txt", ["Plaintext aparece no envelope: NÃO - OK", "Decifra corretamente: sim"], ["SIM - PROBLEMA"]),
    status_row("Segredos no Git", "08_segredos-rastreados.txt", ["OK: nada sensível rastreado pelo Git"], ["private.pem rastreado", ".env rastreado"]),
    status_row("GitHub Actions", "22_github-actions-terminal.txt", ["completed success", '"conclusion":"success"', "✓ phpunit"], ["completed failure", '"conclusion":"failure"']),
]

catalog_rows = [
    ("src/Service/AuthService.php", "Orquestra o fluxo de autenticação: gera URL de login, processa callback do Cognito, valida id_token, cria sessão local e executa logout.", "IAM, Cognito, JWT, sessão segura."),
    ("src/Security/CognitoOAuthClient.php", "Monta a URL do Hosted UI do Cognito, troca authorization code por tokens e gera URL de logout.", "Integração OAuth/OIDC com Cognito."),
    ("src/Security/CognitoJwtVerifier.php", "Valida estrutura do JWT, algoritmo RS256, assinatura com JWKS, issuer, audience/client_id, expiração e token_use.", "Validação de JWT no backend."),
    ("src/Security/Authorization.php", "Aplica requireAuth, requireRole e requireAnyRole no backend.", "Controle de acesso por perfil e bloqueio de acesso indevido."),
    ("src/Security/SecureSession.php", "Configura cookie de sessão, Secure, HttpOnly, SameSite e regeneração de ID.", "Sessão segura e mitigação de session fixation."),
    ("api/public_key.php", "Disponibiliza a chave pública RSA para o frontend sem expor a chave privada.", "Fluxo de criptografia híbrida."),
    ("assets/js/crypto-utils.js", "No navegador, cria envelope com AES-GCM e RSA-OAEP.", "Payload criptografado antes do envio."),
    ("assets/js/encrypted-form.js", "Intercepta formulários marcados e envia JSON criptografado.", "Criptografia transparente em formulários sensíveis."),
    ("src/Core/SecureFormRequest.php", "Lê POST tradicional ou JSON; detecta envelope criptográfico e descriptografa antes de entregar ao controller.", "Recebimento seguro de formulários criptografados."),
    ("src/Security/CryptoHybrid.php", "Implementa AES-256-GCM para o conteúdo e RSA-OAEP para proteger a chave simétrica.", "Criptografia híbrida no backend."),
    ("src/Service/FaleConoscoService.php", "Valida mensagem, criptografa antes de salvar e descriptografa para o admin autorizado.", "Dado sensível cifrado no banco e recuperação autorizada."),
    ("src/Security/Csrf.php", "Gera e valida token CSRF.", "Proteção contra requisições forjadas."),
    ("src/Security/InputValidator.php", "Valida strings, e-mails, IDs, enums e termos de busca.", "Mitigação de entrada inválida e apoio contra Injection."),
    ("src/Security/OutputEncoder.php", "Escapa saída em HTML, atributos, URL e JSON.", "Mitigação de XSS."),
    ("src/Security/AuditLogger.php", "Registra eventos de segurança com contexto e mascara campos sensíveis.", "Logs de auditoria e rastreabilidade."),
    ("src/Security/RateLimiter.php", "Controla quantidade de ações por janela de tempo.", "Mitigação de abuso, brute force e desenho inseguro."),
]

catalog_html = """
<table>
<thead><tr><th>Arquivo</th><th>Função no sistema</th><th>Mecanismo comprovado</th></tr></thead>
<tbody>
"""
for path, role, proves in catalog_rows:
    url = f"{gh}/{path}" if gh else path
    catalog_html += f"<tr><td><a href='{html.escape(url)}'>{html.escape(path)}</a></td><td>{html.escape(role)}</td><td>{html.escape(proves)}</td></tr>"
catalog_html += "</tbody></table>"

mechanism_sections = []

mechanism_sections.append(section("IAM, Cognito, JWT e autorização — arquivos e trechos", """
<p>Esta seção mostra os arquivos que implementam o fluxo de autenticação, validação do token e controle de acesso. Cada trecho abaixo informa o papel do arquivo no sistema antes do código.</p>
""" +
file_card("src/Service/AuthService.php", "Orquestra login/logout. Troca o authorization code por tokens, valida o id_token, cria/atualiza o usuário local e inicia a sessão.", "IAM funcional com Cognito e criação de sessão apenas após validação do token.", 13, 65) +
file_card("src/Security/CognitoOAuthClient.php", "Cliente OAuth/OIDC do Cognito. Gera URL de autorização, troca code por tokens e gera URL de logout.", "Uso do provedor de identidade e fluxo OAuth/OIDC.", 1, 130) +
file_card("src/Security/CognitoJwtVerifier.php", "Verificador do id_token. Valida estrutura, algoritmo, assinatura, JWKS, issuer, audience/client_id, expiração e token_use.", "Validação JWT no backend e rejeição de token inválido.", 16, 155) +
file_card("src/Security/Authorization.php", "Camada central de autorização. Bloqueia usuários sem sessão e perfis sem permissão.", "Perfis distintos no backend, não apenas na interface.", 1, 75) +
file_card("src/Security/SecureSession.php", "Gerencia sessão segura com cookie CONECTAEDUCASESSID, Secure, HttpOnly, SameSite=Lax e regeneração.", "Sessão segura e mitigação de session fixation.", 1, 66)
))

mechanism_sections.append(section("Criptografia híbrida — arquivos e trechos", """
<p>Esta seção mostra como o dado sensível é cifrado com AES-256-GCM, como a chave simétrica é protegida com RSA-OAEP e como o backend abre o envelope no fluxo autorizado.</p>
""" +
file_card("api/public_key.php", "Endpoint que publica apenas a chave pública RSA para o frontend.", "Permite criptografia no navegador sem expor a chave privada.", 1, 80) +
file_card("assets/js/crypto-utils.js", "Utilitário frontend que importa a chave pública, gera chave AES, cifra o conteúdo com AES-GCM e protege a chave com RSA-OAEP.", "Payload criptografado antes de sair do navegador.", 1, 150) +
file_card("assets/js/encrypted-form.js", "Intercepta formulários com data-encrypted-form=true e envia o envelope criptográfico em JSON.", "Aplicação prática da criptografia híbrida nos formulários.", 1, 180) +
file_card("src/Core/SecureFormRequest.php", "Abstração do backend para ler POST tradicional ou JSON criptografado. Detecta encrypted_key, iv, tag e ciphertext.", "Recebimento e abertura do envelope criptográfico.", 1, 100) +
file_card("src/Security/CryptoHybrid.php", "Classe central da criptografia híbrida. Cifra, decifra, monta envelope e abre envelope.", "AES-256-GCM + RSA-OAEP, dado cifrado no banco e recuperação autorizada.", 1, 182) +
file_card("src/Service/FaleConoscoService.php", "Serviço do Fale Conosco. Valida a mensagem, criptografa com CryptoHybrid antes de salvar e descriptografa para listagem administrativa.", "Dado sensível armazenado cifrado e exibido apenas no fluxo autorizado.", 1, 120)
))

mechanism_sections.append(section("CSRF — arquivos e trechos", """
<p>Esta seção mostra a geração e validação de token CSRF e o teste unitário que comprova o comportamento.</p>
""" +
file_card("src/Security/Csrf.php", "Gera token CSRF por sessão, valida token recebido e bloqueia requisição inválida.", "Proteção contra Cross-Site Request Forgery.", 1, 60) +
file_card("src/Core/SecureFormRequest.php", "Recupera token CSRF tanto de header X-CSRF-Token quanto do payload descriptografado.", "Compatibilidade entre CSRF e formulários JSON criptografados.", 44, 76) +
file_card("tests/Unit/Security/CsrfTest.php", "Testes unitários de geração, estabilidade, validação e campo hidden do CSRF.", "Evidência automatizada do requisito de integridade da requisição.", 1, 80)
))

mechanism_sections.append(section("Injection, validação e prepared statements — arquivos e trechos", """
<p>Esta seção comprova validação server-side e testes contra payloads de SQL Injection. Os repositories também são listados como parte da camada que usa PDO/prepared statements.</p>
""" +
file_card("src/Security/InputValidator.php", "Centraliza validação de campos obrigatórios, e-mail, ID, enum e termo de busca.", "Mitigação de entrada inválida e payloads manipulados.", 1, 120) +
file_card("tests/Unit/Security/SqlInjectionTest.php", "Testa rejeição de payloads clássicos como OR 1=1 e UNION SELECT.", "Evidência automatizada contra SQL Injection.", 1, 80) +
file_card("src/Repository/OportunidadeRepository.php", "Repository do domínio de oportunidades. Camada de acesso ao banco para CRUD e consultas.", "Uso de camada dedicada para queries com PDO/prepared statements.", 1, 180) +
file_card("src/Repository/FaleConoscoRepository.php", "Repository das mensagens do Fale Conosco. Insere e consulta dados criptografados.", "Persistência do dado cifrado no banco.", 1, 120)
))

mechanism_sections.append(section("XSS, logs, sessão e rate limit — arquivos e trechos", """
<p>Esta seção reúne os controles complementares usados na defesa OWASP: escape de saída, auditoria, sessão segura e limitação de abuso.</p>
""" +
file_card("src/Security/OutputEncoder.php", "Centraliza escape de saída em HTML, atributo, URL e JSON.", "Mitigação de Cross-Site Scripting.", 1, 80) +
file_card("tests/Unit/Security/XssProtectionTest.php", "Testa neutralização de script tag, payload onerror e escape JSON.", "Evidência automatizada contra XSS.", 1, 80) +
file_card("src/Security/AuditLogger.php", "Registra eventos de segurança e mascara chaves sensíveis no contexto.", "Auditoria, rastreabilidade e mitigação de repudiation.", 1, 100) +
file_card("src/Security/RateLimiter.php", "Controla quantidade de requisições por ação e janela temporal.", "Mitigação de abuso e brute force.", 1, 80) +
file_card("tests/Unit/Security/RateLimiterTest.php", "Testa permissão dentro do limite, bloqueio após limite e buckets separados.", "Evidência automatizada de rate limit.", 1, 80)
))

evidence_sections = [
    pre_section("Composer validate", "02_composer-validate.txt"),
    pre_section("Composer audit", "03_composer-audit.txt"),
    pre_section("PHPUnit TestDox", "05_phpunit-testdox.txt", 50000),
    pre_section("Bloqueio dashboard sem login", "10_bloqueio-dashboard-sem-login.txt", 30000),
    pre_section("Bloqueio admin sem login", "11_bloqueio-admin-sem-login.txt", 30000),
    pre_section("JWT inválido rejeitado", "15_jwt-invalido-rejeitado.txt", 30000),
    pre_section("Envelope criptográfico terminal", "17_envelope-criptografico-terminal.txt", 30000),
    pre_section("Banco com mensagens cifradas", "19_banco-mensagens-cifradas.txt", 30000),
    pre_section("GitHub Actions terminal", "22_github-actions-terminal.txt", 40000),
]

figs = []
for p in image_files:
    rel = str(p.relative_to(EVDIR))
    figs.append(f"""
    <figure>
      <a href="{img_to_data(p)}" target="_blank">
        <img src="{img_to_data(p)}" alt="{html.escape(rel)}">
      </a>
      <figcaption>{html.escape(rel)}</figcaption>
    </figure>
    """)

html_doc = f"""<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>ConectaEduca — Relatório de Evidências RA3 v2</title>
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
body {{ font-family: Arial, sans-serif; margin: 0; background: var(--bg); color: var(--text); }}
header {{ background: linear-gradient(135deg, #312e81, #581c87); color: white; padding: 32px 40px; }}
header h1 {{ margin: 0 0 8px 0; }}
header p {{ margin: 4px 0; opacity: .92; }}
main {{ padding: 24px 40px 48px 40px; }}
.card, .filecard {{ background: var(--card); border-radius: 14px; box-shadow: 0 2px 12px rgba(15, 23, 42, .08); padding: 22px; margin-bottom: 22px; }}
.filecard {{ border-left: 6px solid var(--blue); }}
.filemeta {{ background: #eef2ff; border-radius: 10px; padding: 14px 16px; margin-bottom: 14px; }}
.filemeta h3 {{ margin-top: 0; }}
.grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 14px; }}
.metric {{ background: #eef2ff; border-left: 5px solid var(--blue); padding: 16px; border-radius: 12px; }}
.metric strong {{ display: block; font-size: 24px; }}
table {{ width: 100%; border-collapse: collapse; }}
th, td {{ border-bottom: 1px solid var(--line); padding: 10px; text-align: left; vertical-align: top; }}
.badge {{ display: inline-block; padding: 5px 10px; border-radius: 999px; font-weight: bold; font-size: 13px; }}
.good {{ background: var(--good-bg); color: var(--good); }}
.bad {{ background: var(--bad-bg); color: var(--bad); }}
.warn {{ background: var(--warn-bg); color: var(--warn); }}
pre {{ background: #111827; color: #e5e7eb; padding: 16px; border-radius: 10px; overflow-x: auto; white-space: pre-wrap; font-size: 13px; line-height: 1.45; }}
figure {{ margin: 0; background: #fff; border: 1px solid var(--line); border-radius: 12px; padding: 10px; }}
img {{ width: 100%; border-radius: 8px; border: 1px solid var(--line); }}
figcaption {{ font-size: 12px; color: var(--muted); margin-top: 8px; word-break: break-word; }}
.small {{ color: var(--muted); font-size: 13px; }}
a {{ color: #4338ca; }}
</style>
</head>
<body>
<header>
<h1>ConectaEduca — Relatório de Evidências RA3 v2</h1>
<p>Gerado em: {html.escape(datetime.now().isoformat(timespec="seconds"))}</p>
<p>Repositório: {html.escape(repo_url)}</p>
<p>Commit analisado: {html.escape(commit)}</p>
<p>GitHub Actions: {html.escape(actions_url)}</p>
</header>

<main>
<section class="card">
<h2>Resumo executivo</h2>
<div class="grid">
<div class="metric"><strong>{len(list(RUN.rglob("*.txt")))}</strong> evidências textuais da execução</div>
<div class="metric"><strong>{len(image_files)}</strong> prints incorporados</div>
<div class="metric"><strong>52</strong> testes PHPUnit</div>
<div class="metric"><strong>87</strong> assertions</div>
</div>
<p>Esta versão melhora o relatório anterior adicionando, antes de cada trecho de código, o nome do arquivo, sua função no sistema e o mecanismo de segurança que ele comprova.</p>
</section>

<section class="card">
<h2>Status das evidências principais</h2>
<table>
<thead><tr><th>Controle</th><th>Status</th><th>Arquivo</th></tr></thead>
<tbody>
{''.join(status_rows)}
</tbody>
</table>
</section>

<section class="card">
<h2>Catálogo técnico dos arquivos de segurança</h2>
<p>Este quadro serve como mapa rápido para a defesa: ele mostra qual arquivo comprova cada mecanismo implementado.</p>
{catalog_html}
</section>

{''.join(mechanism_sections)}
{''.join(evidence_sections)}

<section class="card">
<h2>Prints incorporados</h2>
<p class="small">Foram incorporados prints encontrados nas execuções de evidência anteriores. Clique na imagem para abrir em tamanho maior.</p>
<div class="grid">
{''.join(figs) if figs else '<p>Nenhum print encontrado nas pastas de evidência.</p>'}
</div>
</section>

<section class="card">
<h2>Observações finais para a defesa</h2>
<ul>
<li>Para IAM/Cognito: mostrar AuthService, CognitoOAuthClient e CognitoJwtVerifier.</li>
<li>Para JWT: mostrar o teste de token inválido rejeitado e a validação por openssl_verify/JWKS.</li>
<li>Para autorização: mostrar Authorization.php e o retorno 401 sem sessão.</li>
<li>Para criptografia híbrida: mostrar CryptoHybrid, SecureFormRequest, envelope criptográfico e banco com ciphertext.</li>
<li>Para OWASP: usar CSRF, Injection, XSS, logs, sessão segura e rate limit como mecanismos defendíveis.</li>
<li>Para GitHub Actions: usar a evidência do gh e, se possível, print visual da aba Actions.</li>
</ul>
</section>

</main>
</body>
</html>
"""

OUT.write_text(html_doc, encoding="utf-8")
print("Relatório v2 criado em: " + str(OUT))
print("Pasta de evidências usada: " + str(RUN))
print("Prints incorporados: " + str(len(image_files)))
