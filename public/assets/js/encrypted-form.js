(function () {
    "use strict";

    function formToObject(form) {
        const data = {};
        const formData = new FormData(form);

        for (const [key, value] of formData.entries()) {
            if (key === "csrf_token") {
                continue;
            }

            data[key] = value;
        }

        return data;
    }

    function csrfTokenFromForm(form) {
        const input = form.querySelector("input[name=\"csrf_token\"]");

        if (input && input.value) {
            return input.value;
        }

        if (
            window.ConectaEduca &&
            typeof window.ConectaEduca.getCsrfToken === "function"
        ) {
            return window.ConectaEduca.getCsrfToken();
        }

        return null;
    }

    function normalizedInternalPath(target) {
        const value = String(target || "").trim();

        if (value === "" || value.includes('\\') || value.startsWith("//")) {
            return null;
        }

        try {
            const url = new URL(value, window.location.origin);

            if (url.origin !== window.location.origin) {
                return null;
            }

            return url.pathname;
        } catch {
            return null;
        }
    }

    function redirectToKnownDestination(target) {
        const path = normalizedInternalPath(target);

        switch (path) {
            case "/":
                window.location.assign("/");
                return true;

            case "/index.php":
                window.location.assign("/index.php");
                return true;

            case "/login.php":
                window.location.assign("/login.php");
                return true;

            case "/dashboard.php":
                window.location.assign("/dashboard.php");
                return true;

            case "/perfil.php":
                window.location.assign("/perfil.php");
                return true;

            case "/oportunidades.php":
                window.location.assign("/oportunidades.php");
                return true;

            case "/oportunidade.php":
                window.location.assign("/oportunidades.php");
                return true;

            case "/cadastro_usuario.php":
                window.location.assign("/cadastro_usuario.php");
                return true;

            case "/fale_conosco.php":
                window.location.assign("/fale_conosco.php");
                return true;

            default:
                return false;
        }
    }

    function sameOriginAction(form) {
        const rawAction = form.getAttribute("action") || window.location.href;

        try {
            const url = new URL(rawAction, window.location.origin);

            if (url.origin !== window.location.origin) {
                throw new Error("Destino externo recusado.");
            }

            return `${url.pathname}${url.search}`;
        } catch (error) {
            throw new Error("Destino inválido para formulário protegido.");
        }
    }

    async function submitEncryptedForm(form) {
        if (
            !window.ConectaEduca ||
            typeof window.ConectaEduca.encryptHybridEnvelope !== "function"
        ) {
            throw new Error("Utilitário de criptografia híbrida não carregado.");
        }

        const action = sameOriginAction(form);
        const csrfToken = csrfTokenFromForm(form);
        const data = formToObject(form);
        const envelope = await window.ConectaEduca.encryptHybridEnvelope(data);

        const response = await fetch(action, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                Accept: "application/json, text/html;q=0.9,*/*;q=0.8",
                ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
            },
            credentials: "same-origin",
            cache: "no-store",
            body: JSON.stringify(envelope),
        });

        if (response.redirected) {
            if (!redirectToKnownDestination(response.url)) {
                window.location.assign("/dashboard.php");
            }

            return;
        }

        const contentType = response.headers.get("content-type") || "";

        if (contentType.includes("application/json")) {
            const json = await response.json();

            if (json.redirect) {
                if (!redirectToKnownDestination(json.redirect)) {
                    throw new Error("Redirecionamento inválido recebido do servidor.");
                }

                return;
            }

            if (!response.ok || json.ok === false) {
                throw new Error(json.message || "Falha ao enviar formulário criptografado.");
            }

            window.location.reload();
            return;
        }

        if (!response.ok) {
            throw new Error(`Falha ao enviar formulário criptografado. HTTP ${response.status}`);
        }

        window.location.reload();
    }

    document.addEventListener("DOMContentLoaded", () => {
        const forms = document.querySelectorAll("form[data-encrypted-form=\"true\"]");

        forms.forEach((form) => {
            form.addEventListener("submit", async (event) => {
                event.preventDefault();

                const confirmationMessage = (form.getAttribute("data-confirm") || "").trim();

                if (confirmationMessage !== "" && !window.confirm(confirmationMessage)) {
                    return;
                }

                const submitButton = form.querySelector("button[type=\"submit\"]");
                const originalText = submitButton ? submitButton.textContent : null;

                try {
                    if (submitButton) {
                        submitButton.disabled = true;
                        submitButton.textContent = "Enviando com criptografia...";
                    }

                    await submitEncryptedForm(form);
                } catch (error) {
                    alert(error.message || "Erro ao enviar formulário criptografado.");
                } finally {
                    if (submitButton) {
                        submitButton.disabled = false;
                        submitButton.textContent = originalText;
                    }
                }
            });
        });
    });
})();
