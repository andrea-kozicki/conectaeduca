/* ConectaEduca — login híbrido. Mantém MFA e erros sem fallback silencioso para POST claro. */
(function () {
    "use strict";

    const REDIRECTS_PERMITIDOS = new Set([
        "/mfa.php",
        "/mfa-configurar.php",
        "/dashboard.php",
        "/login.php",
    ]);

    function destinoSeguro(responseUrl) {
        const url = new URL(responseUrl, window.location.href);

        if (
            url.origin !== window.location.origin ||
            !REDIRECTS_PERMITIDOS.has(url.pathname)
        ) {
            throw new Error("Redirecionamento de autenticação inesperado.");
        }

        return url.pathname + url.search;
    }

    function mensagemHttp(status) {
        switch (status) {
            case 401:
                return "E-mail ou senha inválidos.";
            case 403:
                return "O controle de segurança bloqueou o envio. Verifique a solicitação.";
            case 419:
                return "A sessão expirou. Atualize a página e tente novamente.";
            case 429:
                return "Muitas tentativas. Aguarde antes de tentar novamente.";
            default:
                return "Não foi possível entrar. Verifique a conexão e tente novamente.";
        }
    }

    document.addEventListener("DOMContentLoaded", () => {
        const form = document.querySelector('form[data-login-hybrid="true"]');
        if (!form) return;

        const email = form.querySelector('input[name="email"]');
        const senha = form.querySelector('input[name="senha"]');
        const csrf = form.querySelector('input[name="csrf_token"]');
        const botao = form.querySelector('button[type="submit"]');
        const alerta = document.getElementById("login-client-error");

        if (!email || !senha || !csrf || !botao || !alerta) return;

        let enviando = false;

        function exibirErro(texto) {
            alerta.textContent = texto;
            alerta.hidden = false;
        }

        form.addEventListener("submit", async (event) => {
            event.preventDefault();

            if (enviando || !form.reportValidity()) return;

            alerta.textContent = "";
            alerta.hidden = true;
            enviando = true;
            botao.disabled = true;
            const textoOriginal = botao.textContent;
            botao.textContent = "Enviando com criptografia...";

            try {
                if (
                    !window.isSecureContext ||
                    !window.crypto ||
                    !window.crypto.subtle ||
                    !window.ConectaEduca ||
                    typeof window.ConectaEduca.encryptHybridEnvelope !== "function"
                ) {
                    throw new Error("Criptografia de login indisponível neste navegador.");
                }

                if (!csrf.value) {
                    throw new Error("Token CSRF ausente.");
                }

                const payload = await window.ConectaEduca.encryptHybridEnvelope({
                    email: email.value.trim(),
                    senha: senha.value,
                });

                // Nunca substituir silenciosamente o envelope por FormData/POST em claro.
                const response = await fetch("/login.php", {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        "Accept": "text/html",
                        "X-CSRF-Token": csrf.value,
                    },
                    credentials: "same-origin",
                    cache: "no-store",
                    redirect: "follow",
                    body: JSON.stringify(payload),
                });

                if (response.redirected) {
                    if (!response.ok) {
                        exibirErro(mensagemHttp(response.status));
                        senha.value = "";
                        return;
                    }

                    // A resposta 302 do backend é seguida pelo fetch.
                    // Navegar apenas para destinos conhecidos preserva o MFA.
                    window.location.assign(destinoSeguro(response.url));
                    return;
                }

                // Erros do backend continuam em HTML: não tentar JSON.parse().
                exibirErro(mensagemHttp(response.status));
                senha.value = "";
            } catch (_error) {
                // Não registrar email, senha, envelope ou exceções que os contenham.
                exibirErro("Não foi possível enviar o login criptografado. Atualize a página se necessário.");
                senha.value = "";
            } finally {
                enviando = false;
                botao.disabled = false;
                botao.textContent = textoOriginal;
            }
        });
    });
})();
