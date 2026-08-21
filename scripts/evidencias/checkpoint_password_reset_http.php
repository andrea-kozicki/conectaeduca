<?php

declare(strict_types=1);

use ConectaEduca\Config\Database;
use ConectaEduca\Config\Env;
use ConectaEduca\Service\PasswordResetService;

$root = dirname(__DIR__, 2);
require_once $root . '/vendor/autoload.php';

$ok = 0;
$fail = 0;
$pdo = null;
$fixtureUserId = null;
$fixtureEmail = null;
$rateSnapshots = [];

function aprovado(string $mensagem): void
{
    global $ok;
    ++$ok;
    printf("OK          %s\n", $mensagem);
}

function falha(string $mensagem): void
{
    global $fail;
    ++$fail;
    printf("FALHA       %s\n", $mensagem);
}

function senhaSintetica(): string
{
    return 'T!' . bin2hex(random_bytes(18)) . 'aA7';
}

/**
 * Cliente HTTP mínimo com cookie jar para exercitar sessão/CSRF pelo servidor real.
 */
final class HttpCheckpointClient
{
    /** @var array<string,string> */
    private array $cookies = [];

    public function __construct(
        private readonly string $baseUrl
    ) {}

    /**
     * @param array<string,string> $form
     * @return array{status:int,headers:list<string>,body:string,location:?string}
     */
    public function request(
        string $method,
        string $path,
        array $form = []
    ): array {
        $method = strtoupper($method);
        $url = rtrim($this->baseUrl, '/') . '/' . ltrim($path, '/');

        $headers = [
            'Connection: close',
            'User-Agent: ConectaEduca-Checkpoint-PasswordResetHTTP/1.0',
            'Accept: text/html,application/xhtml+xml',
        ];

        if ($this->cookies !== []) {
            $pairs = [];
            foreach ($this->cookies as $name => $value) {
                $pairs[] = $name . '=' . $value;
            }
            $headers[] = 'Cookie: ' . implode('; ', $pairs);
        }

        $content = '';
        if ($method === 'POST') {
            $content = http_build_query($form, '', '&', PHP_QUERY_RFC3986);
            $headers[] = 'Content-Type: application/x-www-form-urlencoded';
            $headers[] = 'Content-Length: ' . strlen($content);
        }

        $context = stream_context_create([
            'http' => [
                'method' => $method,
                'timeout' => 8,
                'ignore_errors' => true,
                'follow_location' => 0,
                'max_redirects' => 0,
                'protocol_version' => 1.1,
                'header' => implode("\r\n", $headers) . "\r\n",
                'content' => $content,
            ],
            /*
             * O checkpoint só aceita host local/teste e pode encontrar o
             * certificado autoassinado do VirtualHost acadêmico.
             */
            'ssl' => [
                'verify_peer' => false,
                'verify_peer_name' => false,
                'allow_self_signed' => true,
            ],
        ]);

        $body = @file_get_contents($url, false, $context);
        $responseHeaders = $http_response_header ?? [];
        $status = 0;
        $location = null;

        if (
            isset($responseHeaders[0])
            && preg_match('/\s(\d{3})\s/', $responseHeaders[0], $m) === 1
        ) {
            $status = (int) $m[1];
        }

        foreach ($responseHeaders as $header) {
            if (preg_match('/^Set-Cookie:\s*([^=;\s]+)=([^;]*)/i', $header, $m) === 1) {
                $name = $m[1];
                $value = $m[2];

                if ($value === '') {
                    unset($this->cookies[$name]);
                } else {
                    $this->cookies[$name] = $value;
                }
            }

            if (stripos($header, 'Location:') === 0) {
                $location = trim(substr($header, strlen('Location:')));
            }
        }

        return [
            'status' => $status,
            'headers' => array_values($responseHeaders),
            'body' => $body === false ? '' : $body,
            'location' => $location,
        ];
    }
}

/** @return string|null */
function headerValue(array $headers, string $name): ?string
{
    foreach ($headers as $header) {
        if (stripos($header, $name . ':') === 0) {
            return trim(substr($header, strlen($name) + 1));
        }
    }

    return null;
}

function csrfFromHtml(string $html): ?string
{
    if (
        preg_match(
            '/<input[^>]+name=["\']csrf_token["\'][^>]+value=["\']([^"\']+)["\']/i',
            $html,
            $m
        ) !== 1
    ) {
        return null;
    }

    return html_entity_decode($m[1], ENT_QUOTES | ENT_HTML5, 'UTF-8');
}

function localBaseUrl(): string
{
    $override = trim((string) getenv('CHECKPOINT_HTTP_BASE_URL'));
    $base = $override !== ''
        ? $override
        : trim((string) Env::get('APP_URL', ''));

    if ($base === '' || filter_var($base, FILTER_VALIDATE_URL) === false) {
        throw new RuntimeException(
            'APP_URL/CHECKPOINT_HTTP_BASE_URL ausente ou inválida.'
        );
    }

    $scheme = strtolower((string) parse_url($base, PHP_URL_SCHEME));
    $host = strtolower((string) parse_url($base, PHP_URL_HOST));

    if (!in_array($scheme, ['http', 'https'], true) || $host === '') {
        throw new RuntimeException('URL HTTP de checkpoint inválida.');
    }

    $allowedByName = $host === 'localhost'
        || $host === '127.0.0.1'
        || $host === '::1'
        || str_ends_with($host, '.local')
        || str_ends_with($host, '.test');

    $resolved = gethostbyname($host);
    $allowedByIp = filter_var(
        $resolved,
        FILTER_VALIDATE_IP,
        FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE
    ) === false;

    if (!$allowedByName && !$allowedByIp) {
        throw new RuntimeException(
            'Checkpoint recusado: APP_URL não parece apontar para ambiente local/teste.'
        );
    }

    return rtrim($base, '/');
}

function discoverSourceIp(string $baseUrl): ?string
{
    $host = (string) parse_url($baseUrl, PHP_URL_HOST);
    $scheme = strtolower((string) parse_url($baseUrl, PHP_URL_SCHEME));
    $port = parse_url($baseUrl, PHP_URL_PORT);
    $port = is_int($port) ? $port : ($scheme === 'https' ? 443 : 80);

    $targetHost = str_contains($host, ':') ? '[' . $host . ']' : $host;
    $socket = @stream_socket_client(
        'tcp://' . $targetHost . ':' . $port,
        $errno,
        $errstr,
        3
    );

    if (!is_resource($socket)) {
        return null;
    }

    $local = stream_socket_get_name($socket, false);
    fclose($socket);

    if (!is_string($local) || $local === '') {
        return null;
    }

    if ($local[0] === '[' && preg_match('/^\[([^]]+)\]:\d+$/', $local, $m) === 1) {
        return $m[1];
    }

    $pos = strrpos($local, ':');
    if ($pos === false) {
        return $local;
    }

    return substr($local, 0, $pos);
}

/** @return array{action:string,hash:string} */
function rateKey(string $action, string $identifier): array
{
    return [
        'action' => $action,
        'hash' => hash('sha256', $identifier),
    ];
}

/**
 * @param list<array{action:string,hash:string}> $keys
 * @return array<string,array|null>
 */
function snapshotRateRows(PDO $pdo, array $keys): array
{
    $snapshot = [];
    $stmt = $pdo->prepare(
        'SELECT id, acao, identificador_hash, janela_inicio, tentativas,
                bloqueado_ate, criado_em, atualizado_em
         FROM rate_limits
         WHERE acao = :acao
           AND identificador_hash = :hash
         LIMIT 1'
    );

    foreach ($keys as $key) {
        $stmt->execute([
            ':acao' => $key['action'],
            ':hash' => $key['hash'],
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        $snapshot[$key['action'] . '|' . $key['hash']] = is_array($row) ? $row : null;
    }

    return $snapshot;
}

/**
 * @param list<array{action:string,hash:string}> $keys
 * @param array<string,array|null> $snapshot
 */
function restoreRateRows(PDO $pdo, array $keys, array $snapshot): void
{
    $delete = $pdo->prepare(
        'DELETE FROM rate_limits
         WHERE acao = :acao
           AND identificador_hash = :hash'
    );

    $insert = $pdo->prepare(
        'INSERT INTO rate_limits
            (id, acao, identificador_hash, janela_inicio, tentativas,
             bloqueado_ate, criado_em, atualizado_em)
         VALUES
            (:id, :acao, :hash, :janela_inicio, :tentativas,
             :bloqueado_ate, :criado_em, :atualizado_em)'
    );

    foreach ($keys as $key) {
        $index = $key['action'] . '|' . $key['hash'];
        $row = $snapshot[$index] ?? null;

        $delete->execute([
            ':acao' => $key['action'],
            ':hash' => $key['hash'],
        ]);

        if (!is_array($row)) {
            continue;
        }

        $insert->execute([
            ':id' => $row['id'],
            ':acao' => $row['acao'],
            ':hash' => $row['identificador_hash'],
            ':janela_inicio' => $row['janela_inicio'],
            ':tentativas' => $row['tentativas'],
            ':bloqueado_ate' => $row['bloqueado_ate'],
            ':criado_em' => $row['criado_em'],
            ':atualizado_em' => $row['atualizado_em'],
        ]);
    }
}

printf("======================================================================\n");
printf(" CONECTAEDUCA - CHECKPOINT PASSWORD RESET / HTTP REAL\n");
printf(" VirtualHost + sessão + CSRF + controller + MariaDB sintético\n");
printf("======================================================================\n\n");

$declaredEnv = strtolower(trim((string) Env::get('APP_ENV', '')));
$localEnvironments = ['', 'development', 'dev', 'test', 'testing', 'local'];

if (!in_array($declaredEnv, $localEnvironments, true)) {
    falha('checkpoint recusado fora de ambiente local/teste: ' . $declaredEnv);
    printf("\nRESULTADO: REPROVADO.\n");
    exit(1);
}

try {
    $baseUrl = localBaseUrl();
    aprovado('URL de laboratório aceita: ' . $baseUrl);

    $probe = new HttpCheckpointClient($baseUrl);
    $home = $probe->request('GET', '/login.php');

    if ($home['status'] !== 200) {
        throw new RuntimeException(
            'VirtualHost não respondeu GET /login.php com HTTP 200.'
        );
    }
    aprovado('VirtualHost respondeu GET /login.php com HTTP 200');

    if (
        str_contains($home['body'], '/esqueci-senha.php')
        && str_contains($home['body'], 'Esqueceu sua senha?')
    ) {
        aprovado('login expõe o link público de recuperação de senha');
    } else {
        falha('login não contém o link esperado de recuperação');
    }

    $sourceIp = discoverSourceIp($baseUrl);
    if ($sourceIp === null || filter_var($sourceIp, FILTER_VALIDATE_IP) === false) {
        throw new RuntimeException('Não foi possível determinar o IP local usado no checkpoint HTTP.');
    }
    aprovado('IP de origem local do checkpoint identificado sem cabeçalho forjado');

    $pdo = Database::connect();
    aprovado('conexão PDO com o MariaDB estabelecida');

    if ((string) $pdo->query('SELECT DATABASE()')->fetchColumn() !== 'conectaeduca') {
        throw new RuntimeException('Banco alvo inesperado.');
    }
    aprovado('banco alvo confirmado: conectaeduca');

    $marker = 'ce-reset-http-' . bin2hex(random_bytes(7));
    $fixtureEmail = $marker . '@example.test';
    $missingEmail = $marker . '-ausente@example.test';
    $fixtureName = 'Fixture HTTP Reset ' . substr($marker, -8);
    $oldPassword = senhaSintetica();
    $newPassword = senhaSintetica();

    $oldHash = password_hash($oldPassword, PASSWORD_DEFAULT);
    if (!is_string($oldHash) || $oldHash === '') {
        throw new RuntimeException('Não foi possível gerar a senha inicial da fixture.');
    }

    $stmt = $pdo->prepare(
        "INSERT INTO usuarios
            (nome, email, role, senha_hash, conta_ativada, mfa_ativo, criado_em)
         VALUES
            (:nome, :email, 'usuario', :senha_hash, 0, 0, NOW())"
    );
    $stmt->execute([
        ':nome' => $fixtureName,
        ':email' => $fixtureEmail,
        ':senha_hash' => $oldHash,
    ]);
    $fixtureUserId = (int) $pdo->lastInsertId();

    if ($fixtureUserId < 1) {
        throw new RuntimeException('Fixture HTTP não pôde ser criada.');
    }
    aprovado('conta sintética inicialmente inativa criada para o fluxo HTTP');

    $ipIdentifier = 'ip:' . $sourceIp;
    $fixtureEmailHash = hash('sha256', strtolower($fixtureEmail));
    $missingEmailHash = hash('sha256', strtolower($missingEmail));

    $rateKeys = [
        rateKey('password_reset_ip', $ipIdentifier),
        rateKey('password_reset_conta_ip', 'email_hash:' . $fixtureEmailHash . '|' . $ipIdentifier),
        rateKey('password_reset_conta_ip', 'email_hash:' . $missingEmailHash . '|' . $ipIdentifier),
        rateKey('login_ip', $ipIdentifier),
        rateKey('login_conta_ip', 'email_hash:' . $fixtureEmailHash . '|' . $ipIdentifier),
    ];

    $rateSnapshots = snapshotRateRows($pdo, $rateKeys);
    restoreRateRows($pdo, $rateKeys, array_fill_keys(array_keys($rateSnapshots), null));

    $client = new HttpCheckpointClient($baseUrl);

    $forgot = $client->request('GET', '/esqueci-senha.php');
    if ($forgot['status'] === 200 && csrfFromHtml($forgot['body']) !== null) {
        aprovado('GET /esqueci-senha.php entrega formulário com CSRF');
    } else {
        throw new RuntimeException('Formulário de recuperação não pôde ser aberto com CSRF.');
    }

    if (
        str_contains($forgot['body'], 'site-header')
        && str_contains($forgot['body'], 'ConectaEduca')
        && str_contains($forgot['body'], '/cadastro_usuario.php')
    ) {
        aprovado('página de solicitação preserva o cabeçalho público do layout de autenticação');
    } else {
        falha('página de solicitação não preserva o layout público esperado');
    }

    $withoutCsrf = (new HttpCheckpointClient($baseUrl))->request(
        'POST',
        '/esqueci-senha.php',
        ['email' => $fixtureEmail]
    );
    if ($withoutCsrf['status'] === 419) {
        aprovado('POST /esqueci-senha.php sem CSRF é bloqueado com HTTP 419');
    } else {
        falha('solicitação sem CSRF não retornou HTTP 419');
    }

    $invalidClient = new HttpCheckpointClient($baseUrl);
    $invalidGet = $invalidClient->request('GET', '/esqueci-senha.php');
    $invalidCsrf = csrfFromHtml($invalidGet['body']);
    $invalidPost = $invalidClient->request(
        'POST',
        '/esqueci-senha.php',
        [
            'csrf_token' => (string) $invalidCsrf,
            'email' => 'email-invalido',
        ]
    );
    if ($invalidPost['status'] === 422) {
        aprovado('e-mail sintaticamente inválido é rejeitado com HTTP 422');
    } else {
        falha('e-mail inválido não retornou HTTP 422');
    }

    $existingClient = new HttpCheckpointClient($baseUrl);
    $existingGet = $existingClient->request('GET', '/esqueci-senha.php');
    $existingCsrf = csrfFromHtml($existingGet['body']);
    $existingPost = $existingClient->request(
        'POST',
        '/esqueci-senha.php',
        [
            'csrf_token' => (string) $existingCsrf,
            'email' => $fixtureEmail,
        ]
    );

    $missingClient = new HttpCheckpointClient($baseUrl);
    $missingGet = $missingClient->request('GET', '/esqueci-senha.php');
    $missingCsrf = csrfFromHtml($missingGet['body']);
    $missingPost = $missingClient->request(
        'POST',
        '/esqueci-senha.php',
        [
            'csrf_token' => (string) $missingCsrf,
            'email' => $missingEmail,
        ]
    );

    if (
        $existingPost['status'] === 302
        && $missingPost['status'] === 302
        && $existingPost['location'] === '/esqueci-senha.php?status=enviado'
        && $missingPost['location'] === $existingPost['location']
    ) {
        aprovado('conta inativa existente e conta inexistente recebem redirecionamento público idêntico');
    } else {
        falha('camada HTTP permite diferenciar conta inativa de conta inexistente');
    }

    $pdo->prepare('UPDATE usuarios SET conta_ativada = 1 WHERE id = :id')
        ->execute([':id' => $fixtureUserId]);
    aprovado('fixture ativada somente após o teste anti-enumeração sem SMTP');

    $resetService = new PasswordResetService();
    $emitted = $resetService->emitirParaUsuario($fixtureUserId);
    $resetToken = (string) $emitted['token'];

    if (preg_match('/^[A-Za-z0-9_-]{43}$/', $resetToken) !== 1) {
        throw new RuntimeException('Token sintético de redefinição possui formato inesperado.');
    }
    aprovado('token sintético válido emitido internamente para o teste da camada HTTP');

    $resetClient = new HttpCheckpointClient($baseUrl);
    $resetGet = $resetClient->request('GET', '/redefinir-senha.php');
    $resetCsrf = csrfFromHtml($resetGet['body']);

    if ($resetGet['status'] === 200 && $resetCsrf !== null) {
        aprovado('GET /redefinir-senha.php entrega formulário protegido por CSRF');
    } else {
        throw new RuntimeException('Tela de redefinição não pôde ser aberta corretamente.');
    }

    $cacheControl = strtolower((string) headerValue($resetGet['headers'], 'Cache-Control'));
    $pragma = strtolower((string) headerValue($resetGet['headers'], 'Pragma'));
    $referrer = strtolower((string) headerValue($resetGet['headers'], 'Referrer-Policy'));

    if (
        str_contains($cacheControl, 'no-store')
        && str_contains($pragma, 'no-cache')
        && $referrer === 'no-referrer'
    ) {
        aprovado('tela de redefinição aplica no-store, no-cache e no-referrer');
    } else {
        falha('headers de proteção da tela de redefinição estão incompletos');
    }

    $csp = strtolower((string) headerValue($resetGet['headers'], 'Content-Security-Policy'));

    if (
        str_contains($csp, "script-src 'self'")
        && !str_contains($csp, "script-src 'self' 'unsafe-inline'")
    ) {
        aprovado('CSP da aplicação mantém scripts restritos a arquivos da própria origem');
    } else {
        falha('CSP da aplicação não apresenta a política de script esperada');
    }

    if (
        str_contains($resetGet['body'], '/assets/js/password-reset.js')
        && !str_contains($resetGet['body'], '<script>')
        && !str_contains($resetGet['body'], 'O token é transportado no fragmento')
    ) {
        aprovado('view usa JavaScript externo compatível com CSP e evita texto técnico ao usuário');
    } else {
        falha('view de redefinição não contém o hardening/UX esperado para a CSP');
    }

    $resetJs = (new HttpCheckpointClient($baseUrl))->request(
        'GET',
        '/assets/js/password-reset.js'
    );

    if (
        $resetJs['status'] === 200
        && str_contains($resetJs['body'], 'window.location.hash')
        && str_contains($resetJs['body'], 'history.replaceState')
        && str_contains($resetJs['body'], 'reset_token')
    ) {
        aprovado('JavaScript externo de recuperação está acessível e implementa captura/remoção do fragmento');
    } else {
        falha('JavaScript externo de recuperação não está acessível ou está incompleto');
    }

    $queryProbe = (new HttpCheckpointClient($baseUrl))->request(
        'GET',
        '/redefinir-senha.php?token=' . rawurlencode($resetToken)
    );
    if (
        $queryProbe['status'] === 200
        && !str_contains($queryProbe['body'], $resetToken)
    ) {
        aprovado('token enviado por query string é ignorado e não ecoado pela aplicação');
    } else {
        falha('endpoint aceitou ou refletiu token de recuperação vindo pela query string');
    }

    $resetWithoutCsrf = (new HttpCheckpointClient($baseUrl))->request(
        'POST',
        '/redefinir-senha.php',
        [
            'token' => $resetToken,
            'senha' => $newPassword,
            'confirmar_senha' => $newPassword,
        ]
    );
    if ($resetWithoutCsrf['status'] === 419) {
        aprovado('POST /redefinir-senha.php sem CSRF é bloqueado com HTTP 419');
    } else {
        falha('redefinição sem CSRF não retornou HTTP 419');
    }

    $resetPost = $resetClient->request(
        'POST',
        '/redefinir-senha.php',
        [
            'csrf_token' => (string) $resetCsrf,
            'token' => $resetToken,
            'senha' => $newPassword,
            'confirmar_senha' => $newPassword,
        ]
    );

    if (
        $resetPost['status'] === 302
        && $resetPost['location'] === '/login.php?senha_redefinida=1'
    ) {
        aprovado('POST válido redefine a senha e redireciona ao login');
    } else {
        falha('POST válido de redefinição não concluiu com o redirecionamento esperado');
    }

    $stmt = $pdo->prepare('SELECT senha_hash FROM usuarios WHERE id = :id');
    $stmt->execute([':id' => $fixtureUserId]);
    $storedHash = (string) $stmt->fetchColumn();

    if (
        password_verify($newPassword, $storedHash)
        && !password_verify($oldPassword, $storedHash)
    ) {
        aprovado('MariaDB confirma nova senha e rejeita a senha anterior após o POST HTTP');
    } else {
        falha('password_hash final não corresponde à redefinição realizada pelo HTTP');
    }

    $loginPage = $resetClient->request('GET', '/login.php?senha_redefinida=1');
    if (
        $loginPage['status'] === 200
        && str_contains($loginPage['body'], 'Senha redefinida com sucesso')
    ) {
        aprovado('login confirma ao usuário a redefinição concluída');
    } else {
        falha('mensagem de sucesso pós-redefinição não foi exibida');
    }

    $loginCsrf = csrfFromHtml($loginPage['body']);
    if ($loginCsrf === null) {
        throw new RuntimeException('CSRF do login pós-reset não pôde ser obtido.');
    }

    $loginPost = $resetClient->request(
        'POST',
        '/login.php',
        [
            'csrf_token' => $loginCsrf,
            'email' => $fixtureEmail,
            'senha' => $newPassword,
        ]
    );

    if (
        $loginPost['status'] === 302
        && $loginPost['location'] === '/mfa-configurar.php'
    ) {
        aprovado('nova senha é aceita pelo fluxo HTTP real de autenticação');
    } else {
        falha('nova senha não foi aceita pelo login HTTP real');
    }

    $logout = $resetClient->request('GET', '/logout.php');
    if ($logout['status'] === 302 && $logout['location'] === '/login.php?logout=1') {
        aprovado('sessão de pré-autenticação sintética foi encerrada ao final do teste');
    } else {
        falha('logout de limpeza da sessão sintética não respondeu como esperado');
    }

    $replayClient = new HttpCheckpointClient($baseUrl);
    $replayGet = $replayClient->request('GET', '/redefinir-senha.php');
    $replayCsrf = csrfFromHtml($replayGet['body']);
    $replay = $replayClient->request(
        'POST',
        '/redefinir-senha.php',
        [
            'csrf_token' => (string) $replayCsrf,
            'token' => $resetToken,
            'senha' => $newPassword . 'X',
            'confirmar_senha' => $newPassword . 'X',
        ]
    );

    if ($replay['status'] === 400) {
        aprovado('replay do token consumido é rejeitado pela camada HTTP com HTTP 400');
    } else {
        falha('camada HTTP não rejeitou replay do token consumido com HTTP 400');
    }

    $stmt = $pdo->prepare(
        "SELECT COUNT(*)
         FROM tokens_conta
         WHERE usuario_id = :usuario_id
           AND tipo_token = 'recuperacao_senha'
           AND usado_em IS NULL"
    );
    $stmt->execute([':usuario_id' => $fixtureUserId]);

    if ((int) $stmt->fetchColumn() === 0) {
        aprovado('nenhum token de recuperação permanece ativo após o fluxo HTTP');
    } else {
        falha('há token ativo residual após a redefinição HTTP');
    }

    $deletedUserId = $fixtureUserId;
    $pdo->prepare('DELETE FROM usuarios WHERE id = :id')->execute([':id' => $fixtureUserId]);
    $fixtureUserId = null;

    restoreRateRows($pdo, $rateKeys, $rateSnapshots);
    $rateSnapshots = [];

    $stmt = $pdo->prepare('SELECT COUNT(*) FROM usuarios WHERE email = :email');
    $stmt->execute([':email' => $fixtureEmail]);
    $userResidue = (int) $stmt->fetchColumn();

    $stmt = $pdo->prepare(
        "SELECT COUNT(*) FROM tokens_conta
         WHERE usuario_id = :usuario_id
           AND tipo_token = 'recuperacao_senha'"
    );
    $stmt->execute([':usuario_id' => $deletedUserId]);
    $tokenResidue = (int) $stmt->fetchColumn();

    if ($userResidue === 0 && $tokenResidue === 0) {
        aprovado('fixture e tokens sintéticos foram removidos ao final do checkpoint');
    } else {
        falha('checkpoint HTTP deixou fixture/tokens sintéticos no MariaDB');
    }
} catch (Throwable $e) {
    falha('checkpoint HTTP encontrou uma exceção inesperada');
    printf("INFO        excecao=%s\n", $e::class);
} finally {
    if ($pdo instanceof PDO) {
        try {
            if ($fixtureUserId !== null && $fixtureUserId > 0) {
                $pdo->prepare('DELETE FROM usuarios WHERE id = :id')
                    ->execute([':id' => $fixtureUserId]);
            }

            if ($rateSnapshots !== []) {
                restoreRateRows($pdo, $rateKeys ?? [], $rateSnapshots);
            }
        } catch (Throwable) {
            falha('cleanup de emergência do checkpoint HTTP não pôde ser concluído');
        }
    }
}

printf("\n======================================================================\n");
printf(" RESULTADO\n");
printf("======================================================================\n");
printf("Aprovacoes: %d\n", $ok);
printf("Falhas:     %d\n", $fail);

if ($fail > 0) {
    printf("\nCHECKPOINT PASSWORD RESET / HTTP REAL: REPROVADO.\n");
    exit(1);
}

printf("\nCHECKPOINT PASSWORD RESET / HTTP REAL: APROVADO.\n");
printf("VirtualHost, sessão, CSRF, controller, views e MariaDB validados no fluxo sintético.\n");
printf("SMTP permanece coberto pelos checkpoints Mailpit/E2E já independentes.\n");
exit(0);
