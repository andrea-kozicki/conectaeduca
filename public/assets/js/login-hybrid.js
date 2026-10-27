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
        const pronto = Boolean(
            window.isSecureContext &&
            window.crypto &&
            window.crypto.subtle &&
            window.ConectaEduca &&
            typeof window.ConectaEduca.encryptHybridEnvelope === "function" &&
            csrf.value
        );

        function exibirErro(texto) {
            alerta.textContent = texto;
            alerta.hidden = false;
        }

        form.addEventListener("submit", async (event) => {
            event.preventDefault();

            // A view desabilita os campos antes de o JavaScript carregar.
            if (!pronto) {
                exibirErro("O login criptografado está indisponível neste navegador.");
                return;
            }

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

                // O backend retorna JSON; redirecionamento HTTP e falha.
                // O navegador NAO deve seguir 302/307/308 antes da validação.
                const response = await fetch("/login.php", {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        "Accept": "application/json",
                        "X-CSRF-Token": csrf.value,
                    },
                    credentials: "same-origin",
                    cache: "no-store",
                    redirect: "error",
                    body: JSON.stringify(payload),
                });

                if (!response.ok) {
                    exibirErro(mensagemHttp(response.status));
                    senha.value = "";
                    return;
                }

                const contentType = response.headers.get("content-type") || "";
                if (response.status !== 200 ||
                    !contentType.toLowerCase().includes("application/json")) {
                    throw new Error("Resposta de autenticação incompatível.");
                }

                const result = await response.json();
                if (!result || result.ok !== true ||
                    typeof result.next !== "string") {
                    throw new Error("Destino MFA ausente ou inválido.");
                }

                // A allowlist é validada ANTES de qualquer navegação.
                // O destino é um caminho de MFA definido no servidor.
                window.location.assign(destinoSeguro(result.next));
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

        // Somente libera entradas depois de registrar o bloqueio de submit.
        // Com JS ausente/incompleto, as credenciais permanecem desabilitadas.
        if (pronto) {
            email.disabled = false;
            senha.disabled = false;
            botao.disabled = false;
        } else {
            exibirErro("O login criptografado está indisponível neste navegador.");
        }
    });
})();
