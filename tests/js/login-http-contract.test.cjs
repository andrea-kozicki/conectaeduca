'use strict';

/**
 * Contrato HTTP REAL do login PHP sem MariaDB e sem VMs.
 * Inicia somente um servidor PHP loopback efemero no runner do GitHub Actions.
 * Todos os payloads sao ficticios e rejeitados antes do acesso ao banco.
 * Fluxos de sucesso e MFA autenticado ainda exigem homologacao controlada.
 */

const {test} = require('node:test');
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const {createServer} = require('node:net');
const {createCipheriv, generateKeyPairSync, randomBytes, publicEncrypt, constants} = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '../..');

async function freePort() {
    return new Promise((resolve, reject) => {
        const server = createServer();
        server.once('error', reject);
        server.listen(0, '127.0.0.1', () => {
            const port = server.address().port;
            server.close(error => error ? reject(error) : resolve(port));
        });
    });
}

function delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function waitReady(child, url) {
    for (let attempt = 0; attempt < 80; attempt++) {
        if (child.exitCode !== null) {
            throw new Error('Servidor PHP encerrou antes de ficar disponível.');
        }
        try {
            const response = await fetch(url + '/login.php', {
                method: 'GET', redirect: 'manual',
                signal: AbortSignal.timeout(1500),
            });
            if (response.status === 200) return;
        } catch { /* servidor ainda nao iniciou */ }
        await delay(100);
    }
    throw new Error('Servidor PHP loopback não respondeu.');
}

async function stopServer(child) {
    if (child.exitCode !== null || child.killed) return;
    child.kill('SIGTERM');
    await Promise.race([
        new Promise(resolve => child.once('exit', resolve)),
        delay(3000),
    ]);
    if (child.exitCode === null) child.kill('SIGKILL');
}

async function post(base, contentType, payload, extraHeaders = {}) {
    return fetch(base + '/login.php', {
        method: 'POST',
        redirect: 'manual',
        headers: {'Content-Type': contentType, 'Accept': 'application/json', ...extraHeaders},
        body: payload,
        signal: AbortSignal.timeout(3500),
    });
}

function envelopeV2(publicKeyPem, fields = {email:'usuario@example.test', senha:'SenhaFicticia!'}) {
    const key = randomBytes(32);
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', key, iv);
    const ciphertext = Buffer.concat([
        cipher.update(JSON.stringify(fields)),
        cipher.final(),
    ]);
    const tag = cipher.getAuthTag();
    const encryptedKey = publicEncrypt({
        key: publicKeyPem,
        padding: constants.RSA_PKCS1_OAEP_PADDING,
        oaepHash: 'sha256',
    }, key);
    return {
        version: 2,
        algorithm: 'AES-256-GCM + RSA-OAEP-SHA256',
        encrypted_key: encryptedKey.toString('base64'),
        iv: iv.toString('base64'),
        tag: tag.toString('base64'),
        ciphertext: ciphertext.toString('base64'),
    };
}

async function jsonFailure(resp, expectedStatus) {
    assert.equal(resp.status, expectedStatus);
    assert.match(resp.headers.get('content-type') || '', /^application\/json/i);
    assert.equal(resp.headers.get('location'), null);
    const body = await resp.text();
    assert.ok(body.length < 600, 'Erro não deve expor corpo extenso');
    const parsed = JSON.parse(body);
    assert.equal(parsed.ok, false);
    assert.equal(typeof parsed.message, 'string');
    assert.ok(!body.includes('SenhaFicticia'));
    assert.ok(!body.includes('usuario@example.test'));
}

test('contrato HTTP real do login PHP (runner isolado, sem banco)', {timeout: 25000}, async t => {
    const port = await freePort();
    const base = 'http://127.0.0.1:' + port;
    // Chave efemera de teste, nunca integrada ao repositório nem ao runtime.
    const tempKeyDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ce-login-http-'));
    const {publicKey, privateKey} = generateKeyPairSync('rsa', {
        modulusLength: 2048,
        publicKeyEncoding: {type:'spki', format:'pem'},
        privateKeyEncoding: {type:'pkcs8', format:'pem'},
    });
    const testPrivateKeyPath = path.join(tempKeyDir, 'private.pem');
    fs.writeFileSync(testPrivateKeyPath, privateKey, {mode:0o600});
    // Roteador efemero: injetamos um store que nega tentativas apenas
    // quando o header sintético do ensaio está presente neste runner.
    // Nunca é instalado em public/, PHP de produção ou nas VMs.
    const routerPath = path.join(tempKeyDir, 'router.php');
    fs.writeFileSync(routerPath, [
        '<?php',
        'declare(strict_types=1);',
        'require_once ' + JSON.stringify(path.join(ROOT, 'vendor/autoload.php')) + ';',
        "if (($_SERVER['HTTP_X_CE_TEST_FORCE_RATE_LIMIT'] ?? '') === '1') {",
        '  \\ConectaEduca\\Security\\RateLimiter::setStore(new class implements \\ConectaEduca\\Repository\\RateLimitStore {',
        '    public function consume(string $acao, string $identificadorHash, int $limite, int $janelaSegundos): bool { return false; }',
        '    public function reset(string $acao, string $identificadorHash): void {}',
        '  });',
        '}',
        'return false;',
    ].join('\n'), {mode:0o600});
    let stderr = '';
    const server = spawn('php', ['-S', '127.0.0.1:' + port, '-t', 'public', routerPath], {
        cwd: ROOT,
        env: {...process.env, APP_DEBUG: '0', PRIVATE_KEY_PATH: testPrivateKeyPath},
        stdio: ['ignore', 'ignore', 'pipe'],
    });
    server.stderr.setEncoding('utf8');
    server.stderr.on('data', chunk => {stderr = (stderr + chunk).slice(-2200);});

    try {
        await waitReady(server, base);
        await t.test('GET renderiza o formulário com proteções e sem credenciais habilitadas', async () => {
            const resp = await fetch(base + '/login.php', {redirect: 'manual'});
            assert.equal(resp.status, 200);
            const html = await resp.text();
            assert.match(html, /name="email"\s+disabled/);
            assert.match(html, /name="senha"\s+disabled/);
            assert.match(html, /type="submit"\s+disabled/);
            assert.match(html, /name="csrf_token"/);
            assert.match(resp.headers.get('content-security-policy') || '', /script-src 'self'/);
        });

        await t.test('form POST não criptografado é recusado antes do banco', async () => {
            const resp = await post(base, 'application/x-www-form-urlencoded',
                new URLSearchParams({email:'usuario@example.test', senha:'SenhaFicticia!'}));
            await jsonFailure(resp, 415);
        });

        await t.test('JSON com credenciais em claro é recusado', async () => {
            const resp = await post(base, 'application/json',
                JSON.stringify({email:'usuario@example.test', senha:'SenhaFicticia!'}));
            await jsonFailure(resp, 415);
        });

        await t.test('envelope v1 é recusado, preservando outras rotas legadas', async () => {
            const resp = await post(base, 'application/json', JSON.stringify({
                version:1, algorithm:'AES-256-GCM + RSA-OAEP',
                encrypted_key:'AAA=', iv:'AAA=', tag:'AAA=', ciphertext:'AAA=',
            }));
            await jsonFailure(resp, 415);
        });

        await t.test('envelope v2 estruturalmente válido porém inválido retorna 400 genérico', async () => {
            const resp = await post(base, 'application/json', JSON.stringify({
                version:2, algorithm:'AES-256-GCM + RSA-OAEP-SHA256',
                encrypted_key:'!!!BAD!!!', iv:'AAA=', tag:'AAA=', ciphertext:'AAA=',
            }));
            await jsonFailure(resp, 400);
        });

        await t.test('JSON malformado não passa pelo endpoint de autenticação', async () => {
            const resp = await post(base, 'application/json', '{"version":2');
            await jsonFailure(resp, 415);
        });

        await t.test('envelope v2 REAL é decriptado pelo PHP, mas CSRF fictício falha com 419', async () => {
            const ciphertext = JSON.stringify(envelopeV2(publicKey));
            const resp = await post(base, 'application/json', ciphertext,
                {'X-CSRF-Token':'csrf-invalido-teste'});
            await jsonFailure(resp, 419);
            // A falha só acontece após a decriptação do envelope v2:
            // o mesmo payload com tag adulterada deve retornar 400.
        });

        await t.test('rate limit do login preserva JSON 429 sem banco nem credenciais reais', async () => {
            const getResp = await fetch(base + '/login.php', {redirect: 'manual'});
            assert.equal(getResp.status, 200);
            const html = await getResp.text();
            const csrf = html.match(/name="csrf_token"\s+value="([^"]+)"/)?.[1];
            const cookie = getResp.headers.get('set-cookie')?.split(';')[0];
            assert.ok(csrf, 'GET deve fornecer token CSRF');
            assert.match(cookie || '', /^CONECTAEDUCASESSID=/);
            const resp = await post(base, 'application/json',
                JSON.stringify(envelopeV2(publicKey)), {
                    'X-CSRF-Token': csrf,
                    'Cookie': cookie,
                    'X-CE-Test-Force-Rate-Limit': '1',
                });
            await jsonFailure(resp, 429);
        });

        await t.test('JSON descriptografado com tipos invalidos recebe 401 JSON antes do banco', async () => {
            const getResp = await fetch(base + '/login.php', {redirect:'manual'});
            assert.equal(getResp.status, 200);
            const html = await getResp.text();
            const csrf = html.match(/name="csrf_token"\s+value="([^"]+)"/)?.[1];
            const cookie = getResp.headers.get('set-cookie')?.split(';')[0];
            assert.ok(csrf);
            assert.match(cookie || '', /^CONECTAEDUCASESSID=/);
            for (const fields of [
                {email:['usuario@example.test'], senha:'SenhaFicticia!'},
                {email:'usuario@example.test', senha:{test:true}},
                {email:42, senha:'SenhaFicticia!'},
            ]) {
                const resp = await post(base, 'application/json',
                    JSON.stringify(envelopeV2(publicKey, fields)),
                    {'X-CSRF-Token':csrf, 'Cookie':cookie});
                await jsonFailure(resp, 401);
            }
        });

        await t.test('alteração do tag AES-GCM falha antes do CSRF sem revelar conteúdo', async () => {
            const payload = envelopeV2(publicKey);
            payload.tag = Buffer.alloc(16, 0).toString('base64');
            const resp = await post(base, 'application/json', JSON.stringify(payload),
                {'X-CSRF-Token':'csrf-invalido-teste'});
            await jsonFailure(resp, 400);
        });

    } finally {
        await stopServer(server);
        fs.rmSync(tempKeyDir, {recursive:true, force:true});
    }
});
