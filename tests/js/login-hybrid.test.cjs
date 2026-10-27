'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '../..');
const script = fs.readFileSync(path.join(root, 'public/assets/js/login-hybrid.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'src/View/auth/login.php'), 'utf8');

function criarCenario(opcoes = {}) {
    const handlers = {};
    const email = {value: 'usuario@example.test', disabled: true};
    const senha = {value: 'SenhaSomenteMemoria!', disabled: true};
    const csrf = {value: opcoes.semCsrf ? '' : 'csrf-ficticio'};
    const botao = {disabled: true, textContent: 'Entrar'};
    const alerta = {hidden: true, textContent: ''};
    const rotas = [], requests = [], cifradas = [];
    let prevented = 0;
    const campos = {
        'input[name="email"]': email,
        'input[name="senha"]': senha,
        'input[name="csrf_token"]': csrf,
        'button[type="submit"]': botao,
    };
    const form = {
        querySelector: (nome) => campos[nome],
        reportValidity: () => opcoes.valido !== false,
        addEventListener: (nome, fn) => { handlers[nome] = fn; },
    };
    const document = {
        querySelector: (nome) => nome === 'form[data-login-hybrid="true"]' ? form : null,
        getElementById: (nome) => nome === 'login-client-error' ? alerta : null,
        addEventListener: (nome, fn) => { handlers[nome] = fn; },
    };
    const window = {
        isSecureContext: opcoes.contextoSeguro !== false,
        crypto: opcoes.semCriptografia ? null : {subtle: {}},
        ConectaEduca: opcoes.semCriptografia ? null : {
            encryptHybridEnvelope: async dados => {
                cifradas.push(dados);
                return {version: 2, algorithm: 'AES-256-GCM + RSA-OAEP-SHA256',
                    encrypted_key: 'RSA-encrypted', iv: 'iv', tag: 'tag',
                    ciphertext: 'AES-encrypted'};
            },
        },
        location: {
            href: 'https://conectaeduca.local/login.php',
            origin: 'https://conectaeduca.local',
            assign: dest => rotas.push(dest),
        },
    };
    const fetch = async (url, init) => {
        requests.push({url, init});
        if (opcoes.falhaRede || opcoes.redirectHttp) {
            throw new TypeError('Falha ou 30x rejeitado por redirect:error');
        }
        const status = opcoes.status ?? 200;
        return {
            status,
            ok: status >= 200 && status < 300,
            headers: {
                get: nome => nome.toLowerCase() === 'content-type'
                    ? (opcoes.tipo ?? 'application/json; charset=UTF-8') : null,
            },
            json: async () => opcoes.resposta ?? {ok:true, next:'/mfa.php'},
        };
    };
    vm.runInNewContext(script, {window, document, fetch, URL});
    handlers.DOMContentLoaded();
    return {
        email, senha, csrf, botao, alerta, rotas, requests, cifradas,
        async submeter() {
            await handlers.submit({preventDefault() { prevented++; }});
        },
        get prevented() { return prevented; },
    };
}

test('HTML falha fechado com campos e botão desabilitados inicialmente', () => {
    assert.match(html, /<form[^>]+data-login-hybrid="true"/);
    assert.match(html, /name="email"\s+disabled/);
    assert.match(html, /name="senha"\s+disabled/);
    assert.match(html, /type="submit"\s+disabled/);
    assert.match(html, /<noscript>[\s\S]*?<\/noscript>/);
});

test('só libera os campos após o listener de submit estar registrado', () => {
    const c = criarCenario();
    assert.equal(c.email.disabled, false);
    assert.equal(c.senha.disabled, false);
    assert.equal(c.botao.disabled, false);
});

test('login v2 usa JSON + CSRF e recebe destino MFA sem 302', async () => {
    const c = criarCenario();
    await c.submeter();
    assert.deepEqual(c.rotas, ['/mfa.php']);
    assert.equal(c.requests.length, 1);
    const r = c.requests[0];
    assert.equal(r.url, '/login.php');
    assert.equal(r.init.method, 'POST');
    assert.equal(r.init.redirect, 'error');
    assert.equal(r.init.credentials, 'same-origin');
    assert.equal(r.init.headers['X-CSRF-Token'], 'csrf-ficticio');
    assert.equal(r.init.headers['Accept'], 'application/json');
    assert.equal(r.init.headers['Content-Type'], 'application/json');
    assert.deepEqual(JSON.parse(r.init.body), {
        version: 2, algorithm: 'AES-256-GCM + RSA-OAEP-SHA256',
        encrypted_key: 'RSA-encrypted', iv: 'iv', tag: 'tag', ciphertext: 'AES-encrypted',
    });
    assert.equal(r.init.body.includes('SenhaSomenteMemoria'), false);
    assert.equal(r.init.body.includes('usuario@example.test'), false);
    assert.equal(c.cifradas[0].email, 'usuario@example.test');
    assert.equal(c.cifradas[0].senha, 'SenhaSomenteMemoria!');
});

test('conta nova segue destino de configuração MFA', async () => {
    const c = criarCenario({resposta:{ok:true,next:'/mfa-configurar.php'}});
    await c.submeter();
    assert.deepEqual(c.rotas, ['/mfa-configurar.php']);
});

test('dashboard na allowlist é aceito', async () => {
    const c = criarCenario({resposta:{ok:true,next:'/dashboard.php'}});
    await c.submeter();
    assert.deepEqual(c.rotas, ['/dashboard.php']);
});

for (const [nome, destino] of [
    ['origem externa', 'https://evil.example.test/mfa.php'],
    ['URL com userinfo', 'https://conectaeduca.local@evil.example.test/mfa.php'],
    ['rota admin', '/admin.php'],
    ['caminho não previsto', '/mfa.php/extra'],
    ['protocolo externo', 'javascript:alert(1)'],
]) {
    test('destino rejeitado: ' + nome, async () => {
        const c = criarCenario({resposta:{ok:true,next:destino}});
        await c.submeter();
        assert.equal(c.rotas.length, 0);
        assert.match(c.alerta.textContent, /login criptografado/);
    });
}

test('redirect HTTP é recusado antes de seguir; não navega', async () => {
    const c = criarCenario({redirectHttp:true});
    await c.submeter();
    assert.equal(c.requests[0].init.redirect, 'error');
    assert.equal(c.rotas.length, 0);
    assert.match(c.alerta.textContent, /login criptografado/);
});

for (const [nome,status,trecho] of [
    ['credenciais inválidas',401,/senha inválidos/],
    ['WAF',403,/controle de segurança/],
    ['CSRF',419,/sessão expirou/],
    ['limitação',429,/Muitas tentativas/],
    ['perfil não aceito',415,/Não foi possível entrar/],
]) {
    test('HTTP ' + status + ': ' + nome + ' não navega e limpa senha', async () => {
        const c = criarCenario({status});
        await c.submeter();
        assert.equal(c.rotas.length,0);
        assert.equal(c.senha.value,'');
        assert.match(c.alerta.textContent,trecho);
        assert.equal(c.requests.length,1);
    });
}

test('resposta 200 em HTML não é autenticada', async () => {
    const c = criarCenario({tipo:'text/html'});
    await c.submeter();
    assert.equal(c.rotas.length,0);
    assert.match(c.alerta.textContent,/login criptografado/);
});

for(const response of [{ok:true}, {ok:false,next:'/mfa.php'}, {ok:true,next:42}]) {
    test('resposta JSON malformada não libera acesso: ' + JSON.stringify(response), async () => {
        const c = criarCenario({resposta:response});
        await c.submeter();
        assert.equal(c.rotas.length,0);
        assert.match(c.alerta.textContent,/login criptografado/);
    });
}

test('sem suporte criptográfico não habilita credenciais nem envia POST', async () => {
    const c = criarCenario({semCriptografia:true});
    assert.equal(c.email.disabled,true);
    assert.equal(c.senha.disabled,true);
    assert.equal(c.botao.disabled,true);
    await c.submeter();
    assert.equal(c.requests.length,0);
    assert.equal(c.rotas.length,0);
});

test('contexto inseguro mantém controles desabilitados', async () => {
    const c = criarCenario({contextoSeguro:false});
    assert.equal(c.botao.disabled,true);
    await c.submeter();
    assert.equal(c.requests.length,0);
});

test('CSRF ausente mantém controles desabilitados', async () => {
    const c = criarCenario({semCsrf:true});
    assert.equal(c.botao.disabled,true);
    await c.submeter();
    assert.equal(c.requests.length,0);
});

test('validação HTML inválida bloqueia a requisição', async () => {
    const c = criarCenario({valido:false});
    await c.submeter();
    assert.equal(c.requests.length,0);
    assert.equal(c.prevented,1);
});

test('falha de rede não causa fallback para POST comum', async () => {
    const c = criarCenario({falhaRede:true});
    await c.submeter();
    assert.equal(c.requests.length,1);
    assert.equal(c.rotas.length,0);
    assert.match(c.alerta.textContent,/login criptografado/);
});
