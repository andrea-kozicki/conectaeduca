<?php
declare(strict_types=1);

require_once __DIR__ . '/../../bootstrap/app.php';

use ConectaEduca\Config\Database;
use ConectaEduca\Config\Env;
use ConectaEduca\Repository\FaleConoscoRepository;
use ConectaEduca\Security\CryptoHybrid;
use ConectaEduca\Service\MfaService;
use phpseclib3\Crypt\PublicKeyLoader;
use phpseclib3\Crypt\RSA;
use phpseclib3\Crypt\RSA\PublicKey;

$okCount = 0;
$failCount = 0;
$infoCount = 0;

function aprovado(string $mensagem): void
{
    global $okCount;
    $okCount++;
    printf("OK          %s\n", $mensagem);
}

function falha(string $mensagem): void
{
    global $failCount;
    $failCount++;
    printf("FALHA       %s\n", $mensagem);
}

function info(string $mensagem): void
{
    global $infoCount;
    $infoCount++;
    printf("INFO        %s\n", $mensagem);
}

function legacyEnvelope(
    string $plaintext,
    string $publicKeyPem
): array {
    $aesKey = random_bytes(32);
    $iv = random_bytes(12);
    $tag = '';

    $ciphertext = openssl_encrypt(
        $plaintext,
        'aes-256-gcm',
        $aesKey,
        OPENSSL_RAW_DATA,
        $iv,
        $tag
    );

    if (
        !is_string($ciphertext)
        || strlen($tag) !== 16
    ) {
        throw new RuntimeException(
            'Falha ao construir fixture criptográfica legada.'
        );
    }

    $publicKey =
        PublicKeyLoader::load($publicKeyPem);

    if (!$publicKey instanceof PublicKey) {
        throw new RuntimeException(
            'Chave pública inválida para fixture legada.'
        );
    }

    $publicKey = $publicKey
        ->withPadding(RSA::ENCRYPTION_OAEP)
        ->withHash('sha1')
        ->withMGFHash('sha1');

    $encryptedKey =
        $publicKey->encrypt($aesKey);

    return [
        'algorithm' =>
            CryptoHybrid::LEGACY_ALGORITHM,
        'encrypted_key' =>
            base64_encode($encryptedKey),
        'iv' => base64_encode($iv),
        'tag' => base64_encode($tag),
        'ciphertext' =>
            base64_encode($ciphertext),
    ];
}

function webCryptoEnvelope(
    string $publicKeyPem,
    string $plaintext
): array {
    $script =
        __DIR__
        . '/gerar_envelope_webcrypto_v2.js';

    if (!is_file($script)) {
        throw new RuntimeException(
            'Gerador Web Crypto v2 ausente.'
        );
    }

    $descriptors = [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];

    $process = proc_open(
        ['node', $script],
        $descriptors,
        $pipes
    );

    if (!is_resource($process)) {
        throw new RuntimeException(
            'Node.js não pôde ser iniciado.'
        );
    }

    fwrite(
        $pipes[0],
        json_encode(
            [
                'public_key_pem' =>
                    $publicKeyPem,
                'plaintext' =>
                    $plaintext,
            ],
            JSON_UNESCAPED_SLASHES
            | JSON_THROW_ON_ERROR
        )
    );
    fclose($pipes[0]);

    $stdout =
        stream_get_contents($pipes[1]);
    fclose($pipes[1]);

    $stderr =
        stream_get_contents($pipes[2]);
    fclose($pipes[2]);

    $rc = proc_close($process);

    if (
        $rc !== 0
        || !is_string($stdout)
        || trim($stdout) === ''
    ) {
        throw new RuntimeException(
            'Gerador Web Crypto sintético reprovou.'
        );
    }

    $decoded = json_decode(
        $stdout,
        true,
        512,
        JSON_THROW_ON_ERROR
    );

    if (!is_array($decoded)) {
        throw new RuntimeException(
            'Envelope Web Crypto sintético inválido.'
        );
    }

    return $decoded;
}

function validateExistingMessages(PDO $pdo): int
{
    $rows = $pdo->query(
        'SELECT id,
                algoritmo,
                encrypted_key,
                iv,
                tag,
                ciphertext
           FROM mensagens_contato
          ORDER BY id'
    )->fetchAll();

    foreach ($rows as $row) {
        CryptoHybrid::decryptString([
            'algorithm' =>
                $row['algoritmo'] ?? null,
            'encrypted_key' =>
                $row['encrypted_key'] ?? null,
            'iv' => $row['iv'] ?? null,
            'tag' => $row['tag'] ?? null,
            'ciphertext' =>
                $row['ciphertext'] ?? null,
        ]);
    }

    return count($rows);
}

function validateExistingMfa(PDO $pdo): int
{
    $rows = $pdo->query(
        'SELECT usuario_id,
                segredo_totp_envelope
           FROM segredos_mfa
          ORDER BY usuario_id'
    )->fetchAll();

    foreach ($rows as $row) {
        $envelope = json_decode(
            (string) (
                $row['segredo_totp_envelope']
                ?? ''
            ),
            true,
            512,
            JSON_THROW_ON_ERROR
        );

        if (!is_array($envelope)) {
            throw new RuntimeException(
                'Envelope MFA persistido inválido.'
            );
        }

        $secret =
            CryptoHybrid::decryptString(
                $envelope
            );

        if ($secret === '') {
            throw new RuntimeException(
                'Envelope MFA produziu segredo vazio.'
            );
        }
    }

    return count($rows);
}

echo "======================================================================\n";
echo " CONECTAEDUCA - CHECKPOINT CRIPTOGRAFIA HIBRIDA V2\n";
echo " Novas escritas SHA-256; leitura retrocompativel SHA-1\n";
echo "======================================================================\n\n";

$fixtureUserId = null;
$fixtureEmail =
    'checkpoint-crypto-v2-'
    . bin2hex(random_bytes(6))
    . '@example.test';

try {
    $env = strtolower(
        trim(
            (string) (
                Env::get('APP_ENV', '')
                ?? ''
            )
        )
    );

    if ($env === 'production') {
        throw new RuntimeException(
            'Checkpoint recusado em APP_ENV=production.'
        );
    }

    if ($env === '') {
        info(
            'APP_ENV ausente; execução aceita apenas como checkpoint local sintético'
        );
    } else {
        aprovado(
            "ambiente não-produtivo confirmado: {$env}"
        );
    }

    if (!class_exists(
        \phpseclib3\Crypt\RSA::class
    )) {
        throw new RuntimeException(
            'phpseclib3 não está disponível.'
        );
    }

    aprovado(
        'phpseclib3 disponível para OAEP configurável'
    );

    $publicKeyPem =
        CryptoHybrid::publicKey();
    $privateKeyPem =
        CryptoHybrid::privateKey();

    if (
        !str_contains(
            $publicKeyPem,
            'BEGIN PUBLIC KEY'
        )
        || !str_contains(
            $privateKeyPem,
            'PRIVATE KEY'
        )
    ) {
        throw new RuntimeException(
            'Par RSA configurado não pôde ser validado.'
        );
    }

    aprovado(
        'par RSA configurado está disponível sem expor material no relatório'
    );

    $markerV2 =
        'checkpoint-v2-'
        . bin2hex(random_bytes(12));

    $v2 = CryptoHybrid::encryptString(
        $markerV2
    );

    if (
        ($v2['version'] ?? null)
            !== CryptoHybrid::CURRENT_VERSION
        || ($v2['algorithm'] ?? null)
            !== CryptoHybrid::CURRENT_ALGORITHM
    ) {
        throw new RuntimeException(
            'Nova escrita não gerou envelope v2.'
        );
    }

    aprovado(
        'CryptoHybrid gera novas escritas com envelope v2'
    );

    if (
        CryptoHybrid::decryptString($v2)
        !== $markerV2
    ) {
        throw new RuntimeException(
            'Roundtrip PHP v2 falhou.'
        );
    }

    aprovado(
        'roundtrip PHP RSA-OAEP SHA-256 + AES-256-GCM aprovado'
    );

    $legacyMarker =
        'checkpoint-v1-'
        . bin2hex(random_bytes(12));

    $legacy = legacyEnvelope(
        $legacyMarker,
        $publicKeyPem
    );

    if (
        CryptoHybrid::decryptString(
            $legacy
        ) !== $legacyMarker
    ) {
        throw new RuntimeException(
            'Leitura do envelope legado falhou.'
        );
    }

    aprovado(
        'novo backend continua lendo envelope legado RSA-OAEP SHA-1'
    );

    $webMarker =
        'checkpoint-webcrypto-'
        . bin2hex(random_bytes(12));

    $webEnvelope =
        webCryptoEnvelope(
            $publicKeyPem,
            $webMarker
        );

    if (
        ($webEnvelope['version'] ?? null)
            !== CryptoHybrid::CURRENT_VERSION
        || ($webEnvelope['algorithm'] ?? null)
            !== CryptoHybrid::CURRENT_ALGORITHM
    ) {
        throw new RuntimeException(
            'Web Crypto não produziu envelope v2.'
        );
    }

    aprovado(
        'Node Web Crypto produziu envelope v2 SHA-256'
    );

    if (
        CryptoHybrid::decryptString(
            $webEnvelope
        ) !== $webMarker
    ) {
        throw new RuntimeException(
            'Interoperabilidade Web Crypto -> PHP falhou.'
        );
    }

    aprovado(
        'interoperabilidade Web Crypto SHA-256 -> PHP aprovada'
    );

    $pdo = Database::connect();

    if (
        strtolower(
            (string) $pdo->query(
                'SELECT DATABASE()'
            )->fetchColumn()
        ) !== 'conectaeduca'
    ) {
        throw new RuntimeException(
            'Banco alvo diferente de conectaeduca.'
        );
    }

    aprovado(
        'conexão com banco conectaeduca confirmada'
    );

    $messageCount =
        validateExistingMessages($pdo);

    aprovado(
        "mensagens_contato existentes continuam descriptografáveis: {$messageCount}"
    );

    $mfaCount =
        validateExistingMfa($pdo);

    aprovado(
        "envelopes MFA existentes continuam descriptografáveis: {$mfaCount}"
    );

    $stmt = $pdo->prepare(
        'INSERT INTO usuarios
            (nome, email, role, senha_hash, conta_ativada, mfa_ativo)
         VALUES
            (:nome, :email, :role, :senha_hash, 1, 0)'
    );

    $stmt->execute([
        ':nome' =>
            'Checkpoint Cripto V2',
        ':email' =>
            $fixtureEmail,
        ':role' =>
            'usuario',
        ':senha_hash' =>
            password_hash(
                bin2hex(random_bytes(18)),
                PASSWORD_DEFAULT
            ),
    ]);

    $fixtureUserId =
        (int) $pdo->lastInsertId();

    if ($fixtureUserId < 1) {
        throw new RuntimeException(
            'Fixture sintética não foi criada.'
        );
    }

    aprovado(
        'usuário sintético criado para persistência v2'
    );

    $messageMarker =
        'mensagem-v2-'
        . bin2hex(random_bytes(10));

    $messageEnvelope =
        CryptoHybrid::encryptString(
            $messageMarker
        );

    $contactRepository =
        new FaleConoscoRepository($pdo);

    $messageId =
        $contactRepository->criar(
            $fixtureUserId,
            'Checkpoint criptografia v2',
            'seguranca',
            $messageEnvelope
        );

    $stmt = $pdo->prepare(
        'SELECT algoritmo,
                encrypted_key,
                iv,
                tag,
                ciphertext
           FROM mensagens_contato
          WHERE id = :id'
    );

    $stmt->execute([
        ':id' => $messageId,
    ]);

    $storedMessage = $stmt->fetch();

    if (!is_array($storedMessage)) {
        throw new RuntimeException(
            'Mensagem sintética v2 não foi localizada.'
        );
    }

    if (
        ($storedMessage['algoritmo'] ?? null)
            !== CryptoHybrid::CURRENT_ALGORITHM
    ) {
        throw new RuntimeException(
            'mensagens_contato não persistiu algoritmo v2.'
        );
    }

    aprovado(
        'mensagens_contato persiste explicitamente o algoritmo v2'
    );

    if (
        CryptoHybrid::decryptString([
            'algorithm' =>
                $storedMessage['algoritmo'],
            'encrypted_key' =>
                $storedMessage['encrypted_key'],
            'iv' =>
                $storedMessage['iv'],
            'tag' =>
                $storedMessage['tag'],
            'ciphertext' =>
                $storedMessage['ciphertext'],
        ]) !== $messageMarker
    ) {
        throw new RuntimeException(
            'Mensagem v2 persistida não pôde ser lida.'
        );
    }

    aprovado(
        'mensagem v2 persistida no MariaDB é descriptografável'
    );

    $mfaService = new MfaService();

    $mfaData =
        $mfaService->prepararConfiguracao(
            $fixtureUserId,
            $fixtureEmail
        );

    $expectedTotp =
        (string) (
            $mfaData['segredo']
            ?? ''
        );

    if ($expectedTotp === '') {
        throw new RuntimeException(
            'MFA sintético não retornou segredo.'
        );
    }

    $stmt = $pdo->prepare(
        'SELECT segredo_totp_envelope
           FROM segredos_mfa
          WHERE usuario_id = :usuario_id'
    );

    $stmt->execute([
        ':usuario_id' =>
            $fixtureUserId,
    ]);

    $mfaEnvelope = json_decode(
        (string) $stmt->fetchColumn(),
        true,
        512,
        JSON_THROW_ON_ERROR
    );

    if (
        !is_array($mfaEnvelope)
        || ($mfaEnvelope['version'] ?? null)
            !== CryptoHybrid::CURRENT_VERSION
        || ($mfaEnvelope['algorithm'] ?? null)
            !== CryptoHybrid::CURRENT_ALGORITHM
    ) {
        throw new RuntimeException(
            'MFA não persistiu envelope v2.'
        );
    }

    aprovado(
        'novo segredo MFA é persistido em envelope v2'
    );

    if (
        CryptoHybrid::decryptString(
            $mfaEnvelope
        ) !== $expectedTotp
    ) {
        throw new RuntimeException(
            'Envelope MFA v2 não recuperou o segredo esperado.'
        );
    }

    aprovado(
        'envelope MFA v2 é descriptografável pelo backend'
    );

    /*
     * Metadados contraditórios devem ser recusados em vez
     * de provocar downgrade silencioso para SHA-1.
     */
    $tampered = $v2;
    $tampered['algorithm'] =
        CryptoHybrid::LEGACY_ALGORITHM;

    try {
        CryptoHybrid::decryptString(
            $tampered
        );

        throw new RuntimeException(
            'Metadados contraditórios foram aceitos.'
        );
    } catch (RuntimeException $e) {
        if (
            $e->getMessage()
            === 'Metadados contraditórios foram aceitos.'
        ) {
            throw $e;
        }
    }

    aprovado(
        'metadados v2 contraditórios são rejeitados sem downgrade'
    );

} catch (Throwable $e) {
    falha(
        'checkpoint encontrou uma exceção durante a validação criptográfica'
    );
    info(
        'tipo=' . $e::class
    );
    /*
     * A mensagem pode conter contexto operacional, mas nunca
     * imprimimos plaintext, TOTP, chave ou envelope.
     */
    info(
        'mensagem='
        . preg_replace(
            '/[\r\n]+/',
            ' ',
            $e->getMessage()
        )
    );
} finally {
    if (
        isset($pdo)
        && $pdo instanceof PDO
        && is_int($fixtureUserId)
        && $fixtureUserId > 0
    ) {
        try {
            $stmt = $pdo->prepare(
                'DELETE FROM usuarios
                  WHERE id = :id'
            );

            $stmt->execute([
                ':id' =>
                    $fixtureUserId,
            ]);

            $remainingMessages =
                (int) $pdo->query(
                    'SELECT COUNT(*)
                       FROM mensagens_contato
                      WHERE usuario_id = '
                    . $fixtureUserId
                )->fetchColumn();

            $remainingMfa =
                (int) $pdo->query(
                    'SELECT COUNT(*)
                       FROM segredos_mfa
                      WHERE usuario_id = '
                    . $fixtureUserId
                )->fetchColumn();

            if (
                $remainingMessages === 0
                && $remainingMfa === 0
            ) {
                aprovado(
                    'fixture v2 removida e cascades de mensagem/MFA confirmados'
                );
            } else {
                falha(
                    'fixture criptográfica deixou resíduos no MariaDB'
                );
            }
        } catch (Throwable) {
            falha(
                'não foi possível limpar completamente a fixture criptográfica'
            );
        }
    }
}

echo "\n======================================================================\n";
echo " RESULTADO\n";
echo "======================================================================\n";
echo "Aprovacoes:   {$okCount}\n";
echo "Advertencias: 0\n";
echo "Falhas:       {$failCount}\n";
echo "Informacoes:  {$infoCount}\n";

if ($failCount > 0) {
    echo "CHECKPOINT CRIPTOGRAFIA HIBRIDA V2: REPROVADO.\n";
    exit(1);
}

echo "CHECKPOINT CRIPTOGRAFIA HIBRIDA V2: APROVADO.\n";
echo "Novas escritas usam RSA-OAEP SHA-256 e dados legados SHA-1 continuam legiveis.\n";
exit(0);
