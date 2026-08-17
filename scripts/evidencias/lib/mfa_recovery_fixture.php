<?php

declare(strict_types=1);

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\MfaRecoveryRepository;
use ConectaEduca\Repository\MfaRepository;
use ConectaEduca\Repository\UsuarioRepository;
use ConectaEduca\Security\CryptoHybrid;
use ConectaEduca\Service\MfaService;
use PragmaRX\Google2FA\Google2FA;

require dirname(__DIR__, 3) . '/vendor/autoload.php';

/**
 * Helper local dos testes HTTP de recuperação do MFA.
 *
 * Entrada sensível é recebida por STDIN para não expor senha/segredo
 * em argumentos de processo. A saída de prepare contém o segredo TOTP
 * atual e deve ser redirecionada para arquivo temporário protegido.
 */

function inputLines(): array
{
    $conteudo = stream_get_contents(STDIN);

    if (!is_string($conteudo)) {
        return [];
    }

    return preg_split('/\R/', rtrim($conteudo, "\r\n")) ?: [];
}

function normalizarRecoveryCode(string $codigo): string
{
    return strtoupper(
        preg_replace('/[\s-]+/', '', trim($codigo)) ?? ''
    );
}

function criarHashRecovery(string $codigo): string
{
    $normalizado = normalizarRecoveryCode($codigo);

    if (!preg_match('/^[A-F0-9]{20}$/', $normalizado)) {
        throw new RuntimeException('Código de recuperação de fixture inválido.');
    }

    $hash = password_hash($normalizado, PASSWORD_DEFAULT);

    if (!is_string($hash) || strlen($hash) < 60) {
        throw new RuntimeException('Não foi possível gerar hash da fixture.');
    }

    return $hash;
}

function descriptografarSegredo(string $envelopeJson): string
{
    $payload = json_decode(
        $envelopeJson,
        true,
        512,
        JSON_THROW_ON_ERROR
    );

    if (!is_array($payload)) {
        throw new RuntimeException('Envelope MFA inválido na fixture.');
    }

    return CryptoHybrid::decryptString($payload);
}

function removerCodigoTesteAnterior(PDO $pdo, int $usuarioId, string $codigo): void
{
    $stmt = $pdo->prepare(
        'SELECT id, codigo_hash
         FROM codigos_recuperacao_mfa
         WHERE usuario_id = :usuario_id'
    );
    $stmt->execute([':usuario_id' => $usuarioId]);

    $normalizado = normalizarRecoveryCode($codigo);

    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $registro) {
        $hash = (string) ($registro['codigo_hash'] ?? '');

        if ($hash === '' || !password_verify($normalizado, $hash)) {
            continue;
        }

        $delete = $pdo->prepare(
            'DELETE FROM codigos_recuperacao_mfa
             WHERE id = :id AND usuario_id = :usuario_id'
        );
        $delete->execute([
            ':id' => (int) $registro['id'],
            ':usuario_id' => $usuarioId,
        ]);
    }
}

function prepararFixture(): void
{
    [$email, $senha, $outroEmail, $codigoA, $codigoB, $codigoOutro] =
        array_pad(inputLines(), 6, '');

    $email = trim($email);
    $outroEmail = trim($outroEmail);

    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        throw new RuntimeException('E-mail da fixture de recovery inválido.');
    }

    if (!filter_var($outroEmail, FILTER_VALIDATE_EMAIL)) {
        throw new RuntimeException('E-mail do outro usuário inválido.');
    }

    if ($senha === '') {
        throw new RuntimeException('Senha da fixture de recovery ausente.');
    }

    $pdo = Database::connect();
    $usuarios = new UsuarioRepository($pdo);

    $usuario = $usuarios->buscarCredenciaisPorEmail($email);

    if ($usuario === null) {
        throw new RuntimeException(
            'Conta CE_TEST_RECOVERY_EMAIL não encontrada. Crie/configure a conta antes do teste.'
        );
    }

    if ((string) $usuario['role'] !== 'usuario') {
        throw new RuntimeException('A fixture de recovery deve usar papel usuario.');
    }

    if ((int) $usuario['conta_ativada'] !== 1) {
        throw new RuntimeException('A conta de recovery está inativa.');
    }

    if (!password_verify($senha, (string) $usuario['senha_hash'])) {
        throw new RuntimeException('Senha da fixture de recovery não confere.');
    }

    $usuarioId = (int) $usuario['id'];

    $outroUsuario = $usuarios->buscarCredenciaisPorEmail($outroEmail);

    if ($outroUsuario === null) {
        throw new RuntimeException('Usuário de comparação não encontrado.');
    }

    $outroUsuarioId = (int) $outroUsuario['id'];

    if ($outroUsuarioId === $usuarioId) {
        throw new RuntimeException('Fixture de recovery e usuário de comparação devem ser distintos.');
    }

    $mfa = new MfaService();

    if (!$mfa->configurado($usuarioId)) {
        $config = $mfa->prepararConfiguracao($usuarioId, $email);
        $segredo = (string) ($config['segredo'] ?? '');

        if ($segredo === '') {
            throw new RuntimeException('Não foi possível preparar MFA da fixture.');
        }

        $google2fa = new Google2FA();
        $otp = $google2fa->getCurrentOtp($segredo);

        if (!$mfa->confirmarConfiguracao($usuarioId, $otp)) {
            throw new RuntimeException('Não foi possível ativar MFA da fixture.');
        }
    }

    $mfaRepo = new MfaRepository($pdo);
    $registroMfa = $mfaRepo->buscarPorUsuarioId($usuarioId);

    if (
        $registroMfa === null
        || (int) $registroMfa['ativo'] !== 1
        || (int) $registroMfa['qr_confirmado'] !== 1
    ) {
        throw new RuntimeException('Fixture não possui MFA ativo após preparação.');
    }

    $segredoAntigo = descriptografarSegredo(
        (string) $registroMfa['segredo_totp_envelope']
    );

    $recovery = new MfaRecoveryRepository($pdo);
    $recovery->substituirCodigos(
        $usuarioId,
        [
            criarHashRecovery($codigoA),
            criarHashRecovery($codigoB),
        ]
    );

    removerCodigoTesteAnterior($pdo, $outroUsuarioId, $codigoOutro);

    $stmt = $pdo->prepare(
        'INSERT INTO codigos_recuperacao_mfa
            (usuario_id, codigo_hash, usado_em, criado_em)
         VALUES
            (:usuario_id, :codigo_hash, NULL, NOW())'
    );
    $stmt->execute([
        ':usuario_id' => $outroUsuarioId,
        ':codigo_hash' => criarHashRecovery($codigoOutro),
    ]);

    $codigoOutroId = (int) $pdo->lastInsertId();

    $pdo->exec(
        "DELETE FROM rate_limits
         WHERE acao IN (
            'login_ip',
            'login_conta_ip',
            'mfa_totp',
            'mfa_configuracao',
            'mfa_recovery_code'
         )"
    );

    echo json_encode(
        [
            'usuario_id' => $usuarioId,
            'outro_usuario_id' => $outroUsuarioId,
            'codigo_outro_id' => $codigoOutroId,
            'segredo_antigo' => $segredoAntigo,
        ],
        JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES
    );
}

function limparFixture(): void
{
    [$outroUsuarioId, $codigoOutroId] = array_pad(inputLines(), 2, '0');

    $outroUsuarioId = (int) $outroUsuarioId;
    $codigoOutroId = (int) $codigoOutroId;

    if ($outroUsuarioId < 1 || $codigoOutroId < 1) {
        return;
    }

    $pdo = Database::connect();
    $stmt = $pdo->prepare(
        'DELETE FROM codigos_recuperacao_mfa
         WHERE id = :id AND usuario_id = :usuario_id'
    );
    $stmt->execute([
        ':id' => $codigoOutroId,
        ':usuario_id' => $outroUsuarioId,
    ]);
}

function estadoFixture(): void
{
    [$email] = array_pad(inputLines(), 1, '');
    $email = trim($email);

    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        throw new RuntimeException('E-mail inválido para consulta da fixture.');
    }

    $pdo = Database::connect();

    $stmt = $pdo->prepare(
        'SELECT
            u.id,
            u.mfa_ativo,
            m.qr_confirmado,
            m.ativo,
            CASE WHEN m.ultimo_passo_totp IS NULL THEN 0 ELSE 1 END AS possui_passo_totp,
            (
                SELECT COUNT(*)
                FROM codigos_recuperacao_mfa c
                WHERE c.usuario_id = u.id
            ) AS total_codigos,
            (
                SELECT COUNT(*)
                FROM codigos_recuperacao_mfa c
                WHERE c.usuario_id = u.id
                  AND c.usado_em IS NULL
            ) AS codigos_disponiveis,
            (
                SELECT COUNT(*)
                FROM codigos_recuperacao_mfa c
                WHERE c.usuario_id = u.id
                  AND c.usado_em IS NOT NULL
            ) AS codigos_usados
         FROM usuarios u
         LEFT JOIN segredos_mfa m ON m.usuario_id = u.id
         WHERE u.email = :email
         LIMIT 1'
    );
    $stmt->execute([':email' => $email]);
    $estado = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!is_array($estado)) {
        throw new RuntimeException('Fixture não encontrada para consulta de estado.');
    }

    echo json_encode($estado, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
}

$acao = $argv[1] ?? '';

try {
    match ($acao) {
        'prepare' => prepararFixture(),
        'cleanup' => limparFixture(),
        'state' => estadoFixture(),
        default => throw new RuntimeException('Ação de fixture inválida.'),
    };
} catch (Throwable $e) {
    fwrite(STDERR, 'ERRO fixture MFA recovery: ' . $e->getMessage() . PHP_EOL);
    exit(2);
}
