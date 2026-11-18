<?php
declare(strict_types=1);

/**
 * PA-05: teste diagnostico em banco MariaDB DESCARTAVEL de GitHub Actions.
 * Nao depende das VMs nem de dados de usuarios reais.
 *
 * Execucao deliberadamente bloqueada fora de GITHUB_ACTIONS e localhost.
 */

use ConectaEduca\Repository\InscricaoRepository;

require dirname(__DIR__, 3) . '/src/Repository/InscricaoRepository.php';

if (
    getenv('GITHUB_ACTIONS') !== 'true'
    || getenv('PA05_TEST_DSN') !== 'mysql:host=127.0.0.1;port=3306;charset=utf8mb4'
) {
    fwrite(STDERR, "ABORT: este teste exige o MariaDB descartavel e localhost do runner CI.\n");
    exit(3);
}

$password = getenv('PA05_TEST_DB_PASSWORD');
if (!is_string($password) || $password === '') {
    fwrite(STDERR, "ABORT: credencial de teste ausente.\n");
    exit(3);
}

$pdo = new PDO(
    (string) getenv('PA05_TEST_DSN'),
    'root',
    $password,
    [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]
);

// Nome gerado nesta unica execucao; nao ha importacao de schema real.
$schema = 'ce_pa05_ci_' . bin2hex(random_bytes(5));
$pdo->exec("CREATE DATABASE `$schema` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
$pdo->exec("USE `$schema`");

$pdo->exec(<<<'SQL'
CREATE TABLE oportunidades (
  id BIGINT UNSIGNED PRIMARY KEY,
  empresa_id BIGINT UNSIGNED NOT NULL,
  status VARCHAR(32) NOT NULL
) ENGINE=InnoDB
SQL);

$pdo->exec(<<<'SQL'
CREATE TABLE inscricoes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id BIGINT UNSIGNED NOT NULL,
  oportunidade_id BIGINT UNSIGNED NOT NULL,
  status VARCHAR(40) NOT NULL,
  observacoes_empresa TEXT DEFAULT NULL,
  data_inscricao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_inscricao (usuario_id, oportunidade_id)
) ENGINE=InnoDB
SQL);

$pdo->exec(<<<'SQL'
INSERT INTO oportunidades (id, empresa_id, status) VALUES
  (101, 7, 'publicada'),
  (102, 8, 'suspensa'),
  (103, 7, 'rascunho'),
  (104, 7, 'encerrada')
SQL);

$repo = new InscricaoRepository($pdo);
$failures = [];
$checkedCount = 0;

/** @param mixed $actual */
function pa05Check(string $label, bool $condition, mixed $actual = null): void
{
    global $failures, $checkedCount;

    ++$checkedCount;

    printf("%s | %s", $condition ? 'PASS' : 'FAIL', $label);
    if (!$condition && $actual !== null) {
        printf(" | observado=%s", json_encode($actual));
    }
    echo "\n";

    if (!$condition) {
        $failures[] = $label;
    }
}

$id = $repo->criar(42, 101);
pa05Check('publicada aceita candidatura', $id > 0);

foreach ([102, 103, 104, 999] as $opportunityId) {
    try {
        $repo->criar(42, $opportunityId);
        pa05Check("oportunidade $opportunityId negada", false, 'gravacao permitida');
    } catch (DomainException) {
        pa05Check("oportunidade $opportunityId negada", true);
    }
}

try {
    $repo->criar(42, 101);
    pa05Check('candidatura duplicada negada', false, 'gravacao permitida');
} catch (PDOException) {
    pa05Check('candidatura duplicada negada', true);
}

$ok = $repo->atualizarStatusComObservacaoAutorizado($id, 'em_analise', 'Revisada', 7);
pa05Check('empresa proprietaria altera status', $ok, $ok);

$wrongCompany = $repo->atualizarStatusComObservacaoAutorizado($id, 'rejeitada', 'Indevida', 8);
pa05Check('empresa de outro ativo nao altera', $wrongCompany === false, $wrongCompany);

// REGRESSAO-ALVO: repetir os valores atuais NAO deve virar erro de autorizacao.
$sameValues = $repo->atualizarStatusComObservacaoAutorizado($id, 'em_analise', 'Revisada', 7);
pa05Check('atualizacao idempotente autorizada', $sameValues === true, $sameValues);

$admin = $repo->atualizarStatusComObservacaoAutorizado($id, 'aprovada', 'Aprovada', null);
pa05Check('admin altera sem empresa vinculada', $admin, $admin);

$pdo->exec("UPDATE inscricoes SET status = 'cancelada_pelo_usuario' WHERE id = " . (int) $id);
$afterCancellation = $repo->atualizarStatusComObservacaoAutorizado($id, 'aprovada', 'Indevida', 7);
pa05Check('cancelamento pelo usuario bloqueia edicao', !$afterCancellation, $afterCancellation);

$missingId = $repo->atualizarStatusComObservacaoAutorizado(9999, 'em_analise', '', 7);
pa05Check('inscricao inexistente nao atualiza', !$missingId, $missingId);

printf("PA05_MARIADB_RESULTS=pass:%d,fail:%d\n", $checkedCount - count($failures), count($failures));
if ($failures !== []) {
    fwrite(STDERR, "PA05_MARIADB_REGRESSION=FAIL — revisar o codigo da PR, sem corrigir automaticamente.\n");
    exit(1);
}

echo "PA05_MARIADB_REGRESSION=PASS\n";
