<?php

declare(strict_types=1);

use ConectaEduca\Config\Database;
use ConectaEduca\Config\Env;
use ConectaEduca\Service\PasswordResetNotificationService;
use ConectaEduca\Service\PasswordResetRequestService;
use ConectaEduca\Service\PasswordResetService;

$root = dirname(__DIR__, 2);
require_once $root . '/vendor/autoload.php';

$ok = 0;
$fail = 0;
$pdo = null;
$fixtureUserId = null;
$fixtureEmail = null;
$rateBuckets = [];

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

/** @return array{status:int,body:string} */
function httpGet(string $url, int $timeoutSeconds = 3): array
{
    $context = stream_context_create([
        'http' => [
            'method' => 'GET',
            'timeout' => $timeoutSeconds,
            'ignore_errors' => true,
            'header' => "Connection: close\r\n",
        ],
    ]);

    $body = @file_get_contents($url, false, $context);
    $headers = $http_response_header ?? [];
    $status = 0;

    if (
        isset($headers[0])
        && preg_match('/\s(\d{3})\s/', $headers[0], $matches) === 1
    ) {
        $status = (int) $matches[1];
    }

    return [
        'status' => $status,
        'body' => $body === false ? '' : $body,
    ];
}

function setEnv(string $key, string $value): void
{
    $_ENV[$key] = $value;
    $_SERVER[$key] = $value;
    putenv($key . '=' . $value);
}

/**
 * @param list<array{action:string,identifier_hash:string}> $buckets
 */
function cleanupFixture(PDO $pdo, ?int $usuarioId, array $buckets): void
{
    if ($usuarioId !== null && $usuarioId > 0) {
        $stmt = $pdo->prepare('DELETE FROM usuarios WHERE id = :id');
        $stmt->execute([':id' => $usuarioId]);
    }

    if ($buckets !== []) {
        $stmt = $pdo->prepare(
            'DELETE FROM rate_limits
             WHERE acao = :acao
               AND identificador_hash = :identificador_hash'
        );

        foreach ($buckets as $bucket) {
            $stmt->execute([
                ':acao' => $bucket['action'],
                ':identificador_hash' => $bucket['identifier_hash'],
            ]);
        }
    }
}

/**
 * @return list<array{action:string,identifier_hash:string}>
 */
function rateBucketsFor(string $email, string $ip): array
{
    $emailNormalizado = strtolower(trim($email));
    $emailHash = hash('sha256', $emailNormalizado);
    $ipIdentifier = 'ip:' . trim($ip);
    $accountIdentifier = 'email_hash:' . $emailHash . '|' . $ipIdentifier;

    return [
        [
            'action' => 'password_reset_ip',
            'identifier_hash' => hash('sha256', $ipIdentifier),
        ],
        [
            'action' => 'password_reset_conta_ip',
            'identifier_hash' => hash('sha256', $accountIdentifier),
        ],
    ];
}

function searchMailpitByRecipient(string $email): array
{
    $query = rawurlencode('to:"' . $email . '"');
    $url = 'http://127.0.0.1:18025/api/v1/search?query=' . $query . '&limit=10';
    $last = ['status' => 0, 'body' => ''];

    for ($attempt = 0; $attempt < 30; ++$attempt) {
        $last = httpGet($url);

        if ($last['status'] === 200) {
            $decoded = json_decode($last['body'], true);
            $messages = is_array($decoded) ? ($decoded['messages'] ?? []) : [];

            if (is_array($messages) && count($messages) > 0) {
                break;
            }
        }

        usleep(100_000);
    }

    return $last;
}

printf("======================================================================\n");
printf(" CONECTAEDUCA - CHECKPOINT PASSWORD RESET E2E / MARIADB + MAILPIT\n");
printf(" Fixture sintética; nenhum usuário, e-mail ou segredo real é utilizado\n");
printf("======================================================================\n\n");

$declaredEnv = Env::get('APP_ENV');
$localEnvironments = ['development', 'dev', 'test', 'testing', 'local'];

if ($declaredEnv !== null && trim($declaredEnv) !== '') {
    $normalizedEnv = strtolower(trim($declaredEnv));

    if (!in_array($normalizedEnv, $localEnvironments, true)) {
        falha("checkpoint recusado fora de ambiente local/teste: {$normalizedEnv}");
        printf("\nRESULTADO: REPROVADO.\n");
        exit(1);
    }

    aprovado("ambiente local/teste explicitamente confirmado: {$normalizedEnv}");
} else {
    aprovado('APP_ENV não declarado; checkpoint usará APP_ENV=test somente neste processo sintético');
}

setEnv('APP_ENV', 'test');
setEnv('APP_URL', 'http://conectaeduca.example.test');
setEnv('MAIL_HOST', '127.0.0.1');
setEnv('MAIL_PORT', '11025');
setEnv('MAIL_SMTP_AUTH', 'false');
setEnv('MAIL_ENCRYPTION', 'none');
setEnv('MAIL_TIMEOUT', '5');
setEnv('MAIL_FROM_ADDRESS', 'nao-responda@exemplo.test');
setEnv('MAIL_FROM_NAME', 'ConectaEduca Lab');

$health = httpGet('http://127.0.0.1:18025/readyz');

if ($health['status'] !== 200) {
    falha('Mailpit não respondeu ao healthcheck local');
    printf("INFO        suba deploy/lab/mailpit/compose.yml antes do checkpoint\n");
    printf("\nRESULTADO: REPROVADO.\n");
    exit(1);
}

aprovado('Mailpit respondeu ao healthcheck HTTP local');

try {
    $pdo = Database::connect();
    aprovado('conexão PDO com o MariaDB estabelecida');

    $dbName = (string) $pdo->query('SELECT DATABASE()')->fetchColumn();

    if ($dbName !== 'conectaeduca') {
        throw new RuntimeException('Banco alvo inesperado.');
    }

    aprovado('banco alvo confirmado: conectaeduca');

    $marker = 'ce-reset-e2e-' . bin2hex(random_bytes(8));
    $fixtureEmail = $marker . '@example.test';
    $nonexistentEmail = $marker . '-ausente@example.test';
    $fixtureName = 'Fixture Reset E2E ' . substr($marker, -8);
    $fixtureIp = '198.51.100.' . random_int(10, 200);
    $nonexistentIp = '203.0.113.' . random_int(10, 200);
    $initialPassword = senhaSintetica();
    $newPassword = senhaSintetica();

    $passwordHash = password_hash($initialPassword, PASSWORD_DEFAULT);

    if (!is_string($passwordHash) || strlen($passwordHash) < 60) {
        throw new RuntimeException('Não foi possível gerar hash da fixture.');
    }

    $stmt = $pdo->prepare(
        "INSERT INTO usuarios
            (nome, email, role, senha_hash, conta_ativada, mfa_ativo, criado_em)
         VALUES
            (:nome, :email, 'usuario', :senha_hash, 1, 0, NOW())"
    );
    $stmt->execute([
        ':nome' => $fixtureName,
        ':email' => $fixtureEmail,
        ':senha_hash' => $passwordHash,
    ]);

    $fixtureUserId = (int) $pdo->lastInsertId();

    if ($fixtureUserId < 1) {
        throw new RuntimeException('Fixture não pôde ser criada.');
    }

    aprovado('usuário sintético ativo criado para o fluxo E2E');

    $rateBuckets = array_merge(
        rateBucketsFor($fixtureEmail, $fixtureIp),
        rateBucketsFor($nonexistentEmail, $nonexistentIp)
    );

    cleanupFixture($pdo, null, $rateBuckets);

    /** @var list<array{event:string,context:array}> $auditEvents */
    $auditEvents = [];

    $audit = static function (string $event, array $context) use (&$auditEvents): void {
        $auditEvents[] = [
            'event' => $event,
            'context' => $context,
        ];
    };

    $requestService = new PasswordResetRequestService(
        audit: $audit
    );

    $notification = new PasswordResetNotificationService(
        requests: $requestService,
        audit: $audit
    );

    $publicExisting = $notification->solicitarEEnviar(
        $fixtureEmail,
        $fixtureIp
    );

    if (($publicExisting['status'] ?? null) === 'accepted') {
        aprovado('solicitação de conta existente foi aceita');
    } else {
        falha('solicitação de conta existente não retornou accepted');
    }

    if (!array_key_exists('delivery', $publicExisting)) {
        aprovado('resposta pública não expõe o objeto interno delivery');
    } else {
        falha('resposta pública expôs o objeto interno delivery');
    }

    $publicNonexistent = $notification->solicitarEEnviar(
        $nonexistentEmail,
        $nonexistentIp
    );

    if (
        ($publicNonexistent['status'] ?? null) === 'accepted'
        && ($publicExisting['public_message'] ?? null) === ($publicNonexistent['public_message'] ?? null)
    ) {
        aprovado('conta existente e inexistente recebem a mesma resposta pública');
    } else {
        falha('respostas públicas permitem distinguir existência da conta');
    }

    $stmt = $pdo->prepare(
        'SELECT acao, identificador_hash
         FROM rate_limits
         WHERE (acao = :ip_action AND identificador_hash = :ip_hash)
            OR (acao = :account_action AND identificador_hash = :account_hash)'
    );

    $existingBuckets = rateBucketsFor($fixtureEmail, $fixtureIp);
    $stmt->execute([
        ':ip_action' => $existingBuckets[0]['action'],
        ':ip_hash' => $existingBuckets[0]['identifier_hash'],
        ':account_action' => $existingBuckets[1]['action'],
        ':account_hash' => $existingBuckets[1]['identifier_hash'],
    ]);

    $bucketRows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (is_array($bucketRows) && count($bucketRows) === 2) {
        aprovado('rate limiting real persistiu os dois buckets esperados no MariaDB');
    } else {
        falha('rate limiting real não persistiu os buckets esperados');
    }

    $search = searchMailpitByRecipient($fixtureEmail);
    $decodedSearch = json_decode($search['body'], true);
    $messages = is_array($decodedSearch) ? ($decodedSearch['messages'] ?? []) : [];

    if ($search['status'] === 200 && is_array($messages) && count($messages) > 0) {
        aprovado('Mailpit recebeu o e-mail real de recuperação da conta sintética');
    } else {
        throw new RuntimeException('Mensagem de recuperação não encontrada no Mailpit.');
    }

    $query = rawurlencode('to:"' . $fixtureEmail . '"');
    $textMail = httpGet(
        'http://127.0.0.1:18025/view/latest.txt?query=' . $query
    );
    $htmlMail = httpGet(
        'http://127.0.0.1:18025/view/latest.html?query=' . $query
    );

    $mailCombined = $textMail['body'] . "\n" . $htmlMail['body'];

    if (
        preg_match(
            '~redefinir-senha\.php\#token=([A-Za-z0-9_-]{43})~',
            html_entity_decode($mailCombined, ENT_QUOTES | ENT_HTML5, 'UTF-8'),
            $tokenMatch
        ) !== 1
    ) {
        throw new RuntimeException('Token não pôde ser extraído do e-mail sintético.');
    }

    $mailToken = $tokenMatch[1];
    aprovado('link de recuperação contém token Base64URL de 43 caracteres');

    $decodedMailCombined = html_entity_decode(
        $mailCombined,
        ENT_QUOTES | ENT_HTML5,
        'UTF-8'
    );

    if (
        str_contains($decodedMailCombined, 'redefinir-senha.php#token=')
        && !str_contains($decodedMailCombined, 'redefinir-senha.php?token=')
    ) {
        aprovado('token é transportado no fragmento da URL e não na query string');
    } else {
        falha('link de recuperação não respeita a política de fragmento sem query string');
    }

    $tokenHash = hash('sha256', $mailToken);
    $stmt = $pdo->prepare(
        "SELECT token_hash, usado_em, expira_em > NOW() AS ainda_valido
         FROM tokens_conta
         WHERE usuario_id = :usuario_id
           AND tipo_token = 'recuperacao_senha'
         ORDER BY id DESC
         LIMIT 1"
    );
    $stmt->execute([':usuario_id' => $fixtureUserId]);
    $tokenRow = $stmt->fetch(PDO::FETCH_ASSOC);

    if (
        is_array($tokenRow)
        && hash_equals((string) $tokenRow['token_hash'], $tokenHash)
        && $tokenRow['usado_em'] === null
        && (int) $tokenRow['ainda_valido'] === 1
    ) {
        aprovado('token recebido por e-mail corresponde exatamente ao SHA-256 ativo no MariaDB');
    } else {
        falha('token do e-mail não corresponde ao token ativo persistido');
    }

    if (!str_contains((string) ($tokenRow['token_hash'] ?? ''), $mailToken)) {
        aprovado('token puro não foi persistido em tokens_conta');
    } else {
        falha('token puro apareceu no armazenamento de tokens');
    }

    $publicSerialized = json_encode(
        [$publicExisting, $publicNonexistent],
        JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
    );

    if (is_string($publicSerialized) && !str_contains($publicSerialized, $mailToken)) {
        aprovado('token de recuperação não aparece nas respostas públicas');
    } else {
        falha('token de recuperação vazou para a resposta pública');
    }

    $auditSerialized = json_encode(
        $auditEvents,
        JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
    );

    if (
        is_string($auditSerialized)
        && !str_contains($auditSerialized, $mailToken)
        && !str_contains($auditSerialized, $fixtureEmail)
        && !str_contains($auditSerialized, 'redefinir-senha.php#token=')
    ) {
        aprovado('auditoria coletada não contém token, e-mail puro nem link de recuperação');
    } else {
        falha('auditoria coletada contém material sensível de recuperação');
    }

    $eventNames = array_map(
        static fn (array $entry): string => (string) ($entry['event'] ?? ''),
        $auditEvents
    );

    if (
        in_array('password_reset_requested', $eventNames, true)
        && in_array('password_reset_mail_sent', $eventNames, true)
    ) {
        aprovado('eventos operacionais esperados foram gerados sem material secreto');
    } else {
        falha('eventos operacionais esperados não foram observados');
    }

    $resetService = new PasswordResetService();
    $resetUserId = $resetService->redefinirSenha(
        $mailToken,
        $newPassword,
        $newPassword
    );

    if ($resetUserId === $fixtureUserId) {
        aprovado('token extraído do e-mail redefiniu a senha do usuário sintético');
    } else {
        falha('token extraído do e-mail não concluiu a redefinição');
    }

    $stmt = $pdo->prepare(
        'SELECT senha_hash FROM usuarios WHERE id = :id'
    );
    $stmt->execute([':id' => $fixtureUserId]);
    $storedPassword = (string) $stmt->fetchColumn();

    if (
        password_verify($newPassword, $storedPassword)
        && !password_verify($initialPassword, $storedPassword)
    ) {
        aprovado('MariaDB contém somente o novo password_hash após a redefinição');
    } else {
        falha('password_hash final não corresponde ao estado esperado');
    }

    if ($resetService->redefinirSenha($mailToken, $newPassword . 'X', $newPassword . 'X') === null) {
        aprovado('replay do token recebido por e-mail é rejeitado');
    } else {
        falha('token recebido por e-mail pôde ser reutilizado');
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
        aprovado('nenhum token de recuperação permanece ativo após a troca de senha');
    } else {
        falha('há token de recuperação ainda ativo após a redefinição');
    }

    $nonexistentSearch = searchMailpitByRecipient($nonexistentEmail);
    $nonexistentDecoded = json_decode($nonexistentSearch['body'], true);
    $nonexistentMessages = is_array($nonexistentDecoded)
        ? ($nonexistentDecoded['messages'] ?? [])
        : [];

    if (
        $nonexistentSearch['status'] === 200
        && is_array($nonexistentMessages)
        && count($nonexistentMessages) === 0
    ) {
        aprovado('conta inexistente não produz e-mail apesar da resposta pública idêntica');
    } else {
        falha('conta inexistente produziu mensagem SMTP inesperada');
    }

    $deletedUserId = $fixtureUserId;
    cleanupFixture($pdo, $fixtureUserId, $rateBuckets);
    $fixtureUserId = null;

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

    $rateResidue = 0;
    foreach ($rateBuckets as $bucket) {
        $stmt = $pdo->prepare(
            'SELECT COUNT(*) FROM rate_limits
             WHERE acao = :acao
               AND identificador_hash = :identificador_hash'
        );
        $stmt->execute([
            ':acao' => $bucket['action'],
            ':identificador_hash' => $bucket['identifier_hash'],
        ]);
        $rateResidue += (int) $stmt->fetchColumn();
    }

    if ($userResidue === 0 && $tokenResidue === 0 && $rateResidue === 0) {
        aprovado('fixture, tokens por cascade e buckets sintéticos foram removidos');
    } else {
        falha('checkpoint deixou resíduos sintéticos no MariaDB');
    }
} catch (Throwable $e) {
    falha('fluxo E2E encontrou uma exceção inesperada');
    printf("INFO        excecao=%s\n", $e::class);
} finally {
    if ($pdo instanceof PDO) {
        try {
            cleanupFixture($pdo, $fixtureUserId, $rateBuckets);
        } catch (Throwable) {
            falha('cleanup de emergência não pôde ser concluído');
        }
    }
}

printf("\n======================================================================\n");
printf(" RESULTADO\n");
printf("======================================================================\n");
printf("Aprovacoes: %d\n", $ok);
printf("Falhas:     %d\n", $fail);

if ($fail > 0) {
    printf("\nCHECKPOINT PASSWORD RESET E2E: REPROVADO.\n");
    exit(1);
}

printf("\nCHECKPOINT PASSWORD RESET E2E: APROVADO.\n");
printf("MariaDB, rate limiting, MailService e Mailpit validados no mesmo fluxo sintético.\n");
printf("O token puro existiu somente no link entregue ao destinatário de laboratório.\n");
exit(0);
