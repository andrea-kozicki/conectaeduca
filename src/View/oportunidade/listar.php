<?php
declare(strict_types=1);

use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';

$currentUser = $currentUser ?? null;
$favoritoIds = array_map('intval', $favoritoIds ?? []);
$redirectUrl = $_SERVER['REQUEST_URI'] ?? '/oportunidades.php';
$podeFavoritar = $currentUser !== null && (($currentUser['role'] ?? '') !== 'empresa');

function ce_listar_status_label(string $status): string
{
    return match ($status) {
        'rascunho' => 'Rascunho',
        'publicada' => 'Publicada',
        'suspensa' => 'Suspensa',
        'encerrada' => 'Encerrada',
        default => $status,
    };
}

function ce_listar_local(?string $cidade, ?string $estado): string
{
    $cidade = trim((string) $cidade);
    $estado = trim((string) $estado);

    if ($cidade === '' && $estado === '') {
        return 'Não informado';
    }

    if ($cidade !== '' && $estado !== '') {
        return $cidade . ' / ' . $estado;
    }

    return $cidade !== '' ? $cidade : $estado;
}

function ce_listar_data(?string $valor): string
{
    $valor = trim((string) $valor);

    if ($valor === '') {
        return 'Não informado';
    }

    try {
        return (new DateTimeImmutable($valor))->format('d/m/Y H:i');
    } catch (Throwable) {
        return $valor;
    }
}
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Oportunidades educacionais</span>
            <h1>Encontre uma oportunidade</h1>
            <p class="lead">
                Consulte cursos, bolsas, oficinas, estágios e projetos disponíveis no ConectaEduca.
            </p>
        </section>

        <?php if (!empty($_GET['ok'])): ?>
            <div class="feedback feedback-success">
                <?= e::html((string) $_GET['ok']) ?>
            </div>
        <?php endif; ?>

        <?php if (!empty($_GET['erro'])): ?>
            <div class="feedback feedback-error">
                <?= e::html((string) $_GET['erro']) ?>
            </div>
        <?php endif; ?>

        <section class="panel toolbar-card">
            <form method="get" action="/oportunidades.php" class="form-grid">
                <div class="form-group">
                    <label for="busca">Buscar</label>
                    <input
                        type="text"
                        id="busca"
                        name="busca"
                        maxlength="100"
                        placeholder="Ex.: Linux, segurança, estágio..."
                        value="<?= e::attr($_GET['busca'] ?? '') ?>"
                    >
                </div>

                <div class="form-group">
                    <label for="area">Área</label>
                    <input
                        type="text"
                        id="area"
                        name="area"
                        maxlength="80"
                        placeholder="Ex.: Cibersegurança"
                        value="<?= e::attr($_GET['area'] ?? '') ?>"
                    >
                </div>

                <div class="form-group">
                    <label for="modalidade">Modalidade</label>
                    <select id="modalidade" name="modalidade">
                        <option value="">Todas</option>
                        <option value="presencial" <?= ($_GET['modalidade'] ?? '') === 'presencial' ? 'selected' : '' ?>>Presencial</option>
                        <option value="remoto" <?= ($_GET['modalidade'] ?? '') === 'remoto' ? 'selected' : '' ?>>Remoto</option>
                        <option value="hibrido" <?= ($_GET['modalidade'] ?? '') === 'hibrido' ? 'selected' : '' ?>>Híbrido</option>
                    </select>
                </div>

                <div class="form-group">
                    <label for="tipo">Tipo</label>
                    <select id="tipo" name="tipo">
                        <option value="">Todos</option>
                        <option value="estagio" <?= ($_GET['tipo'] ?? '') === 'estagio' ? 'selected' : '' ?>>Estágio</option>
                        <option value="emprego" <?= ($_GET['tipo'] ?? '') === 'emprego' ? 'selected' : '' ?>>Emprego</option>
                        <option value="trainee" <?= ($_GET['tipo'] ?? '') === 'trainee' ? 'selected' : '' ?>>Trainee</option>
                        <option value="bolsa" <?= ($_GET['tipo'] ?? '') === 'bolsa' ? 'selected' : '' ?>>Bolsa</option>
                        <option value="voluntariado" <?= ($_GET['tipo'] ?? '') === 'voluntariado' ? 'selected' : '' ?>>Voluntariado</option>
                        <option value="outro" <?= ($_GET['tipo'] ?? '') === 'outro' ? 'selected' : '' ?>>Outro</option>
                    </select>
                </div>

                <div class="form-actions">
                    <button class="button" type="submit">Filtrar</button>
                    <a class="button-secondary" href="/oportunidades.php">Limpar filtros</a>
                </div>
            </form>
        </section>

        <?php if (empty($oportunidades)): ?>
            <div class="empty-state">
                Nenhuma oportunidade encontrada.
            </div>
        <?php else: ?>
            <section class="opportunity-grid" aria-label="Lista de oportunidades">
                <?php foreach ($oportunidades as $oportunidade): ?>
                    <?php
                    $oportunidadeId = (int) ($oportunidade['id'] ?? 0);
                    $status = (string) ($oportunidade['status'] ?? '');
                    $estaFavoritada = in_array($oportunidadeId, $favoritoIds, true);
                    ?>

                    <article class="opportunity-card">
                        <h2>
                            <a
                                class="opportunity-title-link"
                                href="/oportunidades.php?id=<?= e::url((string) $oportunidadeId) ?>"
                            >
                                <?= e::html($oportunidade['titulo'] ?? '') ?>
                            </a>
                        </h2>

                        <div class="meta-list">
                            <div>
                                <strong>Empresa:</strong>
                                <?= e::html($oportunidade['empresa_nome'] ?? 'Empresa não informada') ?>
                            </div>

                            <div>
                                <strong>Área:</strong>
                                <?= e::html($oportunidade['area'] ?? 'Área não informada') ?>
                            </div>
                        </div>

                        <p class="opportunity-description">
                            <?= e::html(mb_strimwidth($oportunidade['descricao'] ?? '', 0, 220, '...')) ?>
                        </p>

                        <div class="badge-row">
                            <?php if (!empty($oportunidade['area'])): ?>
                                <a
                                    class="badge"
                                    href="/oportunidades.php?area=<?= e::url((string) $oportunidade['area']) ?>"
                                    title="Filtrar por área"
                                >
                                    <?= e::html($oportunidade['area']) ?>
                                </a>
                            <?php endif; ?>

                            <?php if (!empty($oportunidade['modalidade'])): ?>
                                <a
                                    class="badge"
                                    href="/oportunidades.php?modalidade=<?= e::url((string) $oportunidade['modalidade']) ?>"
                                    title="Filtrar por modalidade"
                                >
                                    <?= e::html($oportunidade['modalidade']) ?>
                                </a>
                            <?php endif; ?>

                            <?php if (!empty($oportunidade['tipo_oportunidade'])): ?>
                                <a
                                    class="badge"
                                    href="/oportunidades.php?tipo=<?= e::url((string) $oportunidade['tipo_oportunidade']) ?>"
                                    title="Filtrar por tipo"
                                >
                                    <?= e::html($oportunidade['tipo_oportunidade']) ?>
                                </a>
                            <?php endif; ?>

                            <?php if ($status !== ''): ?>
                                <span class="badge"><?= e::html(ce_listar_status_label($status)) ?></span>
                            <?php endif; ?>
                        </div>

                        <div class="card-actions">
                            <?php if ($podeFavoritar): ?>
                                <form method="post" data-encrypted-form="true" action="/favoritos.php" class="inline-form">
                                    <?= Csrf::inputField() ?>
                                    <input type="hidden" name="action" value="alternar">
                                    <input
                                        type="hidden"
                                        name="oportunidade_id"
                                        value="<?= e::attr((string) $oportunidadeId) ?>"
                                    >
                                    <input
                                        type="hidden"
                                        name="redirect_url"
                                        value="<?= e::attr($redirectUrl) ?>"
                                    >
                                    <button
                                        class="<?= $estaFavoritada ? 'button favorite-active' : 'button-outline' ?>"
                                        type="submit"
                                    >
                                        <?= $estaFavoritada ? 'Remover dos favoritos' : 'Favoritar' ?>
                                    </button>
                                </form>
                            <?php elseif ($currentUser === null): ?>
                                <a class="button-outline" href="/login.php">
                                    Entrar para favoritar
                                </a>
                            <?php endif; ?>

                            <button
                                class="button-outline js-toggle-details"
                                type="button"
                                aria-expanded="false"
                                aria-controls="detalhes-op-<?= e::attr((string) $oportunidadeId) ?>"
                            >
                                Ver detalhes
                            </button>

                            <?php if ($status === 'publicada'): ?>
                                <?php if ($currentUser === null): ?>
                                    <a class="button" href="/login.php">
                                        Entrar para se inscrever
                                    </a>
                                <?php elseif (($currentUser['role'] ?? '') === 'usuario'): ?>
                                    <form method="post" data-encrypted-form="true" action="/api/inscricoes.php" class="inline-form">
                                        <?= Csrf::inputField() ?>
                                        <input
                                            type="hidden"
                                            name="oportunidade_id"
                                            value="<?= e::attr((string) $oportunidadeId) ?>"
                                        >
                                        <button class="button" type="submit">Inscrever-se</button>
                                    </form>
                                <?php endif; ?>
                            <?php endif; ?>
                        </div>

                        <div
                            id="detalhes-op-<?= e::attr((string) $oportunidadeId) ?>"
                            class="opportunity-details"
                            hidden
                        >
                            <h3>Detalhes da oportunidade</h3>

                            <p>
                                <strong>Requisitos:</strong>
                                <?= e::html($oportunidade['requisitos'] ?? 'Não informado') ?>
                            </p>

                            <p>
                                <strong>Modalidade:</strong>
                                <?= e::html($oportunidade['modalidade'] ?? 'Não informada') ?>
                            </p>

                            <p>
                                <strong>Tipo:</strong>
                                <?= e::html($oportunidade['tipo_oportunidade'] ?? 'Não informado') ?>
                            </p>

                            <p>
                                <strong>Local:</strong>
                                <?= e::html(ce_listar_local($oportunidade['cidade'] ?? null, $oportunidade['estado'] ?? null)) ?>
                            </p>

                            <p>
                                <strong>Encerramento:</strong>
                                <?= e::html(ce_listar_data($oportunidade['data_encerramento'] ?? null)) ?>
                            </p>
                        </div>
                    </article>
                <?php endforeach; ?>
            </section>
        <?php endif; ?>
    </div>
</main>

<script src="/assets/js/oportunidades.js" defer></script>
<script src="/assets/js/csrf.js"></script>
<script src="/assets/js/crypto-utils.js"></script>
<script src="/assets/js/encrypted-form.js"></script>
<?php
require dirname(__DIR__) . '/layout/footer.php';