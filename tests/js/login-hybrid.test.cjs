'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const script = fs.readFileSync(
    path.join(__dirname, '../../public/assets/js/login-hybrid.js'),
    'utf8'
);

function criarCenario(opcoes = {}) {
    const eventos = {};
    const email = { value: 'usuario@example.test' };
    const senha = { value: 'SenhaSimuladaSomenteEmMemoria!' };
    const csrf = { value: 'csrf-ficticio' };
    const botao = { disabled: false, textContent: 'Entrar' };
    const alerta = { hidden: true, textContent: '' };
    const rotas = [];
    const requisicoes = [];
    const cifradas = [];
    let bloqueiosDeEnvio = 0;

    const campos = {
        'input[name="email"]': email,
        'input[name="senha"]': senha,
        'input[name="csrf_token"]': csrf,
        'button[type="submit"]': botao,
    };
    const form = {
        querySelector: (nome) => campos[nome],
        reportValidity: () => opcoes.valido !== false,
        addEventListener: (nome, callback) => { eventos[nome] = callback; },
    };
    const document = {
        querySelector: (nome) =>
            nome === 'form[data-login-hybrid="true"]' ? form : null,
        getElementById: (id) => id === 'login-client-error' ? alerta : null,
        addEventListener: (nome, callback) => { eventos[nome] = callback; },
    };
    const href = 'https://conectaeduca.local/login.php';
    const window = {
        isSecureContext: opcoes.contextoSeguro !== false,
        crypto: opcoes.semCriptografia ? null : { subtle: {} },
        ConectaEduca: opcoes.semCriptografia ? null : {
            encryptHybridEnvelope: async (dados) => {
                cifradas.push(dados);
                return { version: 2, encrypted_key: 'segredo-cifrado', iv: 'iv',
                    tag: 'tag', ciphertext: 'cifrado' };
            },
        },
        location: {
            href,
            origin: 'https://conectaeduca.local',
            assign: (url) => rotas.push(url),
        },
    };
    const fetch = async (url, init) => {
        requisicoes.push({ url, init });
        return {
            status: opcoes.status ?? 200,
            ok: opcoes.status === undefined
                ? true : opcoes.status >= 200 && opcoes.status < 300,
            redirected: opcoes.redirected ?? true,
            url: opcoes.url ?? 'https://conectaeduca.local/mfa.php',
        };
    };
    vm.runInNewContext(script, { window, document, fetch, URL });
    eventos.DOMContentLoaded();

    return {
        email, senha, csrf, alerta, botao, rotas, requisicoes, cifradas,
        async submeter() {
            await eventos.submit({ preventDefault() { bloqueiosDeEnvio++; } });
        },
        get bloqueiosDeEnvio() { return bloqueiosDeEnvio; },
    };
}

test('POST criptografado preserva CSRF e redireciona para MFA', async () => {
    const c = criarCenario();
    await c.submeter();
    assert.deepEqual(c.rotas, ['/mfa.php']);
    assert.equal(c.requisicoes.length, 1);
    const req = c.requisicoes[0];
    assert.equal(req.url, '/login.php');
    assert.equal(req.init.method, 'POST');
    assert.equal(req.init.credentials, 'same-origin');
    assert.equal(req.init.headers['X-CSRF-Token'], 'csrf-ficticio');
    assert.equal(req.init.headers['Content-Type'], 'application/json');
    assert.deepEqual(JSON.parse(req.init.body), {
        version: 2, encrypted_key: 'segredo-cifrado',
        iv: 'iv', tag: 'tag', ciphertext: 'cifrado',
    });
    assert.equal(req.init.body.includes('SenhaSimulada'), false);
    assert.equal(req.init.body.includes('usuario@example.test'), false);
    assert.equal(c.cifradas[0].email, 'usuario@example.test');
    assert.equal(c.cifradas[0].senha, 'SenhaSimuladaSomenteEmMemoria!');
});

test('novo usuário pode seguir para configurar MFA', async () => {
    const c = criarCenario({url:'https://conectaeduca.local/mfa-configurar.php'});
    await c.submeter();
    assert.deepEqual(c.rotas, ['/mfa-configurar.php']);
});

test('login concluído pode seguir ao dashboard', async () => {
    const c = criarCenario({url:'https://conectaeduca.local/dashboard.php'});
    await c.submeter();
    assert.deepEqual(c.rotas, ['/dashboard.php']);
});

test('401 não redireciona, limpa senha e mostra mensagem genérica', async () => {
    const c = criarCenario({status:401, redirected:false});
    await c.submeter();
    assert.equal(c.rotas.length, 0);
    assert.equal(c.senha.value, '');
    assert.equal(c.alerta.textContent, 'E-mail ou senha inválidos.');
});

test('419 CSRF exige atualizar página', async () => {
    const c = criarCenario({status:419, redirected:false});
    await c.submeter();
    assert.match(c.alerta.textContent,/sessão expirou/);
    assert.equal(c.rotas.length,0);
});

test('429 preserva aviso de limitação sem nova tentativa', async () => {
    const c = criarCenario({status:429, redirected:false});
    await c.submeter();
    assert.match(c.alerta.textContent,/Muitas tentativas/);
    assert.equal(c.requisicoes.length,1);
});

test('falha de suporte criptográfico não reenvia login em texto claro', async () => {
    const c = criarCenario({semCriptografia:true});
    await c.submeter();
    assert.equal(c.requisicoes.length,0);
    assert.equal(c.rotas.length,0);
    assert.match(c.alerta.textContent,/login criptografado/);
});

test('contexto inseguro não envia requisição', async () => {
    const c = criarCenario({contextoSeguro:false});
    await c.submeter();
    assert.equal(c.requisicoes.length,0);
});

test('redirecionamento para origem externa não é seguido via window.location', async () => {
    const c = criarCenario({url:'https://example.test/mfa.php'});
    await c.submeter();
    assert.equal(c.rotas.length,0);
    assert.match(c.alerta.textContent,/login criptografado/);
});

test('redirecionamento para rota não listada é recusado', async () => {
    const c = criarCenario({url:'https://conectaeduca.local/admin.php'});
    await c.submeter();
    assert.equal(c.rotas.length,0);
});

test('HTTP 200 sem redirect não é classificado como login aprovado', async () => {
    const c = criarCenario({status:200,redirected:false});
    await c.submeter();
    assert.equal(c.rotas.length,0);
    assert.match(c.alerta.textContent,/Não foi possível entrar/);
});

test('formulário inválido não envia nenhuma requisição', async () => {
    const c = criarCenario({valido:false});
    await c.submeter();
    assert.equal(c.requisicoes.length,0);
    assert.equal(c.bloqueiosDeEnvio,1);
});
