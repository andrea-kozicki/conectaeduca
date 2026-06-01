<?php
declare(strict_types=1);

use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';

function ce_fav_status_label(string $status): string
{
    return match ($status) {
        'rascunho' => 'Rascunho',
        'publicada' => 'Publicada',
        'suspensa' => 'Suspensa',
        'encerrada' => 'Encerrada',
        default => $status,
    };
}
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Área do usuário</span>
            <h1>Minhas oportunidades favoritas</h1>
            <p class="lead">
                Acompanhe oportunidades que você salvou para consultar depois.
            </p>
        </section>

        <?php if (!empty($success)): ?>
            <div class="feedback feedback-success">
                <?= e::html($success) ?>
            </div>
        <?php endif; ?>

        <?php if (!empty($error)): ?>
            <div class="feedback feedback-error">
                <?= e::html($error) ?>
            </div>
        <?php endif; ?>

        <?php if (empty($favoritos)): ?>
            <div class="empty-state">
                Você ainda não salvou nenhuma oportunidade como favorita.
            </div>
        <?php else: ?>
            <section class="opportunity-grid" aria-label="Lista de favoritos">
                <?php foreach ($favoritos as $favorito): ?>
                    <article class="opportunity-card">
                        <div class="favorite-card-header">
                            <h2><?= e::html($favorito['titulo'] ?? '') ?></h2>

                            <span class="status-pill <?= e::attr('status-' . ($favorito['status'] ?? '')) ?>">
                                <?= e::html(ce_fav_status_label((string) ($favorito['status'] ?? ''))) ?>
                            </span>
                        </div>

                        <div class="meta-list">
                            <div>
                                <strong>Empresa:</strong>
                                <?= e::html($favorito['empresa_nome'] ?? 'Empresa não informada') ?>
                            </div>

                            <div>
                                <strong>Área:</strong>
                                <?= e::html($favorito['area'] ?? 'Área não informada') ?>
                            </div>

                            <div>
                                <strong>Modalidade:</strong>
                                <?= e::html($favorito['modalidade'] ?? 'Não informada') ?>
                            </div>
                        </div>

                        <p class="opportunity-description">
                            <?= e::html(mb_strimwidth($favorito['descricao'] ?? '', 0, 240, '...')) ?>
                        </p>

                        <div class="card-actions">
                            <a
                                class="button-outline"
                                href="/api/oportunidades.php?id=<?= e::url((string) $favorito['oportunidade_id']) ?>"
                            >
                                Ver oportunidade
                            </a>

                            <?php if (($favorito['status'] ?? '') === 'publicada'): ?>
                                <form method="post" action="/api/inscricoes.php" class="inline-form">
                                    <?= Csrf::inputField() ?>
                                    <input
                                        type="hidden"
                                        name="oportunidade_id"
                                        value="<?= e::attr((string) $favorito['oportunidade_id']) ?>"
                                    >
                                    <button class="button" type="submit">Inscrever-se</button>
                                </form>
                            <?php endif; ?>

                            <form method="post" action="/favoritos.php" class="inline-form">
                                <?= Csrf::inputField() ?>
                                <input type="hidden" name="action" value="remover">
                                <input
                                    type="hidden"
                                    name="oportunidade_id"
                                    value="<?= e::attr((string) $favorito['oportunidade_id']) ?>"
                                >
                                <input type="hidden" name="redirect_url" value="/favoritos.php">
                                <button class="button-outline danger-action" type="submit">
                                    Remover favorito
                                </button>
                            </form>
                        </div>
                    </article>
                <?php endforeach; ?>
            </section>
        <?php endif; ?>
    </div>
</main>

<?php
require dirname(__DIR__) . '/layout/footer.php';