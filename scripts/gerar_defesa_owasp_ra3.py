from pathlib import Path
from datetime import datetime
import html
import os
import subprocess

ROOT = Path("/srv/www/htdocs/conectaeduca")
os.chdir(ROOT)

OUT = ROOT / "docs" / "evidencias" / "html" / "defesa-owasp-top10-ra3.html"
OUT.parent.mkdir(parents=True, exist_ok=True)

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

def code_link(path):
    return f"{gh}/{path}" if gh else path

cards = [
    {
        "owasp": "A01 — Broken Access Control",
        "requisito": "Controle de acesso baseado em perfil e bloqueio de rotas protegidas no backend.",
        "risco": "Usuário comum ou visitante acessar funcionalidades administrativas, alterar recursos de outra empresa ou forçar URLs manualmente.",
        "impacto": "Exposição de dados, alteração indevida de oportunidades/inscrições e quebra de segregação de perfis.",
        "cwe": "CWE-284, CWE-862, CWE-863",
        "cve": "CVE-2022-22978, usada como referência de classe para falha de autorização/bypass de autorização.",
        "mitigacao": "Authorization.php centraliza requireAuth, requireRole e requireAnyRole. Controllers chamam essas funções antes de executar ações sensíveis.",
        "arquivos": [
            ("src/Security/Authorization.php", "Camada central de autorização."),
            ("src/Controller/FaleConoscoController.php", "Exige admin para listar mensagens recebidas."),
            ("src/Controller/OportunidadeController.php", "Aplica regras de perfil e ownership nas oportunidades."),
            ("tests/Unit/Security/AuthorizationTest.php", "Testa comportamento de autorização.")
        ],
        "evidencias": [
            "10_bloqueio-dashboard-sem-login.txt",
            "11_bloqueio-admin-sem-login.txt",
            "05_phpunit-testdox.txt"
        ],
        "fala": "Este item mitiga Broken Access Control porque a autorização está no backend, não apenas no menu. Mesmo que alguém tente acessar a URL diretamente, o servidor retorna 401 sem sessão ou 403 sem perfil adequado."
    },
    {
        "owasp": "A02 — Cryptographic Failures",
        "requisito": "Criptografia híbrida de dados sensíveis e armazenamento cifrado no banco.",
        "risco": "Mensagem sensível ou dado pessoal ficar exposto em trânsito, no backend ou diretamente no banco.",
        "impacto": "Vazamento de dados pessoais e quebra de confidencialidade.",
        "cwe": "CWE-311, CWE-312, CWE-319",
        "cve": "CVE-2014-0160, Heartbleed, usada como referência histórica de vazamento de informação sensível.",
        "mitigacao": "O frontend/backend usam envelope híbrido: AES-256-GCM cifra o dado; RSA-OAEP protege a chave simétrica; o banco guarda encrypted_key, iv, tag e ciphertext.",
        "arquivos": [
            ("api/public_key.php", "Entrega apenas a chave pública ao frontend."),
            ("assets/js/crypto-utils.js", "Gera envelope criptográfico no navegador."),
            ("assets/js/encrypted-form.js", "Envia formulários sensíveis como JSON criptografado."),
            ("src/Core/SecureFormRequest.php", "Detecta e abre envelope criptográfico no backend."),
            ("src/Security/CryptoHybrid.php", "Implementa AES-256-GCM + RSA-OAEP."),
            ("src/Service/FaleConoscoService.php", "Criptografa mensagem antes de salvar e descriptografa no fluxo admin.")
        ],
        "evidencias": [
            "17_envelope-criptografico-terminal.txt",
            "18_public-key-endpoint.txt",
            "19_banco-mensagens-cifradas.txt"
        ],
        "fala": "A criptografia híbrida protege o conteúdo e também protege a chave de sessão. A evidência do banco mostra que a mensagem não está em texto claro; a aplicação só recupera no fluxo autorizado."
    },
    {
        "owasp": "A03 — Injection",
        "requisito": "Validação server-side, uso de PDO/prepared statements e escape de saída.",
        "risco": "SQL Injection, XSS ou manipulação de parâmetros para quebrar consultas e executar conteúdo malicioso.",
        "impacto": "Vazamento de dados, alteração indevida do banco ou execução de JavaScript no navegador da vítima.",
        "cwe": "CWE-89, CWE-79, CWE-20",
        "cve": "CVE-2017-5638 como referência de exploração por entrada maltratada; CVE-2020-11023 como referência de XSS.",
        "mitigacao": "InputValidator valida tipos, IDs e enums; repositories usam camada PDO; OutputEncoder escapa HTML, atributo, URL e JSON; testes simulam payloads de SQLi e XSS.",
        "arquivos": [
            ("src/Security/InputValidator.php", "Validação server-side."),
            ("src/Security/OutputEncoder.php", "Escape de saída."),
            ("src/Repository/OportunidadeRepository.php", "Camada de persistência com PDO."),
            ("src/Repository/FaleConoscoRepository.php", "Persiste mensagens cifradas."),
            ("tests/Unit/Security/SqlInjectionTest.php", "Testa payloads de SQL Injection."),
            ("tests/Unit/Security/XssProtectionTest.php", "Testa neutralização de XSS.")
        ],
        "evidencias": [
            "05_phpunit-testdox.txt",
            "24_injection-validacao-explicada.txt",
            "25_xss-explicado.txt"
        ],
        "fala": "Aqui a defesa é em camadas: entrada validada, consulta parametrizada e saída escapada. Mesmo que o usuário envie payload malicioso, ele não vira comando SQL nem script executável."
    },
    {
        "owasp": "A04 — Insecure Design",
        "requisito": "Regras de negócio e segurança aplicadas no backend, não apenas no frontend.",
        "risco": "Confiar no navegador, permitir troca manual de IDs, permitir alteração de recurso de outra empresa ou aceitar fluxo sensível sem controle.",
        "impacto": "Bypass de regra de negócio, escalada funcional e acesso indevido a objetos de domínio.",
        "cwe": "CWE-840, CWE-841, CWE-863, CWE-307",
        "cve": "CVE de referência deve ser entendida como classe de risco; no relatório, este item é melhor defendido por DFD/STRIDE e pelos testes de regra de negócio.",
        "mitigacao": "Controllers e services validam perfil, ownership, status permitido, CSRF, rate limit e regras de transição; STRIDE mapeia spoofing, tampering, repudiation, information disclosure, DoS e elevation of privilege.",
        "arquivos": [
            ("src/Service/OportunidadeService.php", "Regras do CRUD de oportunidades."),
            ("src/Service/InscricaoService.php", "Regras de inscrição/cancelamento/status."),
            ("src/Security/RateLimiter.php", "Controle de abuso por janela de tempo."),
            ("src/Security/Authorization.php", "Controle de perfil no backend.")
        ],
        "evidencias": [
            "27_sessao-rate-limit-explicados.txt",
            "05_phpunit-testdox.txt",
            "docs/RELATORIO_EVIDENCIAS_RA3.md"
        ],
        "fala": "Este é o item de Design Inseguro: a aplicação não confia apenas no frontend. As decisões críticas ficam em services/controllers, com autorização, validação, CSRF, rate limit e logs."
    },
    {
        "owasp": "A05 — Security Misconfiguration",
        "requisito": "Configuração segura, headers de segurança e ausência de segredos no repositório.",
        "risco": "Expor credenciais, chaves, arquivos sensíveis, logs ou executar a aplicação sem headers mínimos de proteção.",
        "impacto": "Exposição de dados, sequestro de sessão, clickjacking, vazamento de segredo e superfície de ataque maior.",
        "cwe": "CWE-16, CWE-200, CWE-798, CWE-614",
        "cve": "CVE-2021-41773 pode ser usada como referência de exposição por configuração inadequada em servidor web.",
        "mitigacao": "Segredos ficam fora do Git; .env e storage/keys não são rastreados; SecurityHeaders aplica headers; composer audit verifica dependências.",
        "arquivos": [
            ("src/Security/SecurityHeaders.php", "Headers de segurança."),
            ("src/Config/Env.php", "Leitura de variáveis de ambiente."),
            ("src/Security/Secrets.php", "Acesso centralizado a segredos."),
            (".gitignore", "Evita versionar artefatos sensíveis.")
        ],
        "evidencias": [
            "08_segredos-rastreados.txt",
            "03_composer-audit.txt",
            "10_bloqueio-dashboard-sem-login.txt"
        ],
        "fala": "Este item mostra higiene de configuração: nada sensível rastreado no Git, headers de segurança nas respostas e dependências auditadas."
    },
    {
        "owasp": "A06 — Vulnerable and Outdated Components",
        "requisito": "Auditoria de dependências e pipeline de testes.",
        "risco": "Usar biblioteca com vulnerabilidade conhecida ou lockfile inconsistente.",
        "impacto": "Exploração por falha conhecida em componente de terceiro.",
        "cwe": "CWE-1104",
        "cve": "As CVEs dependem das bibliotecas afetadas; a evidência do composer audit mostra que não há advisories conhecidos no momento do teste.",
        "mitigacao": "composer audit sem vulnerabilidades, composer validate válido e pipeline verde no GitHub Actions.",
        "arquivos": [
            ("composer.json", "Declara dependências e metadados."),
            ("composer.lock", "Trava versões instaladas."),
            (".github/workflows", "Executa testes no pipeline.")
        ],
        "evidencias": [
            "02_composer-validate.txt",
            "03_composer-audit.txt",
            "22_github-actions-terminal.txt"
        ],
        "fala": "A defesa aqui é mostrar que o projeto valida o Composer, audita dependências e executa testes no GitHub Actions."
    },
    {
        "owasp": "A07 — Identification and Authentication Failures",
        "requisito": "Autenticação com Cognito, MFA/2FA, sessão segura e rate limit.",
        "risco": "Login fraco, conta comprometida, sessão fixa, cookie exposto ou tentativas abusivas.",
        "impacto": "Tomada de conta e acesso indevido ao sistema.",
        "cwe": "CWE-287, CWE-308, CWE-384, CWE-614, CWE-307",
        "cve": "CVE-2022-22978 é usada como referência de falha em autenticação/autorização no ecossistema web.",
        "mitigacao": "Cognito realiza autenticação e MFA; backend valida id_token; SecureSession configura cookies seguros; RateLimiter reduz abuso.",
        "arquivos": [
            ("src/Service/AuthService.php", "Processa login/logout."),
            ("src/Security/CognitoJwtVerifier.php", "Valida o token."),
            ("src/Security/SecureSession.php", "Configura sessão."),
            ("src/Security/RateLimiter.php", "Limita tentativas/ações.")
        ],
        "evidencias": [
            "12_iam-cognito-jwt-explicado.txt",
            "14_mfa-2fa-fluxo-cognito.txt",
            "27_sessao-rate-limit-explicados.txt"
        ],
        "fala": "O login não é caseiro: a identidade é delegada ao Cognito. A aplicação só cria sessão depois de validar token e ainda usa cookie seguro, regeneração de sessão e rate limit."
    },
    {
        "owasp": "A09 — Security Logging and Monitoring Failures",
        "requisito": "Logs de auditoria para ações sensíveis.",
        "risco": "Não conseguir identificar ação crítica, alteração indevida ou tentativa de acesso não autorizado.",
        "impacto": "Dificuldade de investigação, ausência de rastreabilidade e negação de autoria.",
        "cwe": "CWE-778",
        "cve": "Sem CVE única obrigatória; o item é defendido por requisito, CWE e evidência de eventos registrados.",
        "mitigacao": "AuditLogger registra eventos como login_success, unauthorized_access_attempt, alterações de oportunidade, favoritos e mensagens criptografadas.",
        "arquivos": [
            ("src/Security/AuditLogger.php", "Centraliza logs e redige campos sensíveis."),
            ("src/Service/FaleConoscoService.php", "Registra envio criptografado."),
            ("src/Security/Authorization.php", "Registra tentativas não autorizadas.")
        ],
        "evidencias": [
            "26_logs-auditoria-explicados.txt",
            "10_bloqueio-dashboard-sem-login.txt",
            "11_bloqueio-admin-sem-login.txt"
        ],
        "fala": "Logs mitigam repudiation no STRIDE. A aplicação registra quem fez, quando fez e qual ação crítica ocorreu, sem gravar segredos em claro."
    },
]

def render_card(c):
    arquivos = "".join(
        f"<li><a href='{html.escape(code_link(path))}'>{html.escape(path)}</a> — {html.escape(desc)}</li>"
        for path, desc in c["arquivos"]
    )
    evidencias = "".join(f"<li>{html.escape(e)}</li>" for e in c["evidencias"])

    return f"""
    <section class="owasp-card">
      <h2>{html.escape(c["owasp"])}</h2>
      <div class="grid2">
        <div>
          <h3>Requisito atendido</h3>
          <p>{html.escape(c["requisito"])}</p>
          <h3>Risco</h3>
          <p>{html.escape(c["risco"])}</p>
          <h3>Impacto</h3>
          <p>{html.escape(c["impacto"])}</p>
        </div>
        <div>
          <h3>CWE</h3>
          <p>{html.escape(c["cwe"])}</p>
          <h3>CVE de referência</h3>
          <p>{html.escape(c["cve"])}</p>
          <h3>Mitigação</h3>
          <p>{html.escape(c["mitigacao"])}</p>
        </div>
      </div>
      <h3>Arquivos de implementação</h3>
      <ul>{arquivos}</ul>
      <h3>Evidências</h3>
      <ul>{evidencias}</ul>
      <h3>Como defender oralmente</h3>
      <p class="fala">{html.escape(c["fala"])}</p>
    </section>
    """

html_doc = f"""<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>ConectaEduca — Defesa OWASP Top 10 RA3</title>
<style>
body {{
  font-family: Arial, sans-serif;
  margin: 0;
  background: #f4f6fb;
  color: #1f2937;
}}
header {{
  background: linear-gradient(135deg, #7e22ce, #312e81);
  color: white;
  padding: 34px 42px;
}}
header h1 {{ margin: 0 0 8px 0; }}
header p {{ margin: 4px 0; }}
main {{ padding: 24px 42px 50px; }}
.intro, .owasp-card {{
  background: white;
  border-radius: 16px;
  padding: 24px;
  margin-bottom: 22px;
  box-shadow: 0 2px 12px rgba(15, 23, 42, .08);
}}
.owasp-card {{ border-left: 7px solid #7e22ce; }}
.grid2 {{
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
  gap: 18px;
}}
h2 {{ margin-top: 0; }}
h3 {{ margin-bottom: 4px; color: #312e81; }}
ul {{ margin-top: 6px; }}
li {{ margin-bottom: 7px; }}
a {{ color: #4338ca; }}
.fala {{
  background: #eef2ff;
  border-left: 5px solid #4338ca;
  padding: 14px 16px;
  border-radius: 10px;
}}
.badge {{
  display: inline-block;
  padding: 7px 11px;
  background: #dcfce7;
  color: #166534;
  border-radius: 999px;
  font-weight: bold;
  margin-right: 8px;
}}
</style>
</head>
<body>
<header>
<h1>ConectaEduca — Defesa OWASP Top 10 RA3</h1>
<p>Gerado em: {html.escape(datetime.now().isoformat(timespec="seconds"))}</p>
<p>Repositório: {html.escape(repo_url)}</p>
<p>Commit analisado: {html.escape(commit)}</p>
</header>
<main>
<section class="intro">
<h2>Objetivo desta seção</h2>
<p>Este documento organiza a defesa dos mecanismos OWASP implementados no ConectaEduca. Cada item relaciona requisito, risco, impacto, CWE, CVE de referência, mitigação, arquivos do código e evidências.</p>
<p><span class="badge">Foco da defesa</span> risco → impacto → mitigação → código → evidência prática.</p>
</section>
{''.join(render_card(c) for c in cards)}
</main>
</body>
</html>
"""

OUT.write_text(html_doc, encoding="utf-8")
print("Relatório OWASP criado em: " + str(OUT))
