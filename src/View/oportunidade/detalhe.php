<?php
declare(strict_types=1);

use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';

$currentUser = $currentUser ?? null;
$favoritoIds = array_map('intval', $favoritoIds ?? []);
$redirectUrl = $_SERVER['REQUEST_URI'] ?? '/api/oportunidades.php';
$oportunidadeId = (int) ($oportunidade['id'] ?? 0);
$estaFavoritada = in_array($oportunidadeId, $favoritoIds, true);
$podeFavoritar = $currentUser !== null && (($currentUser['role'] ?? '') !== 'empresa');
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Detalhes da oportunidade</span>
            <h1><?= e::html($oportunidade['titulo'] ?? '') ?></h1>
            <p class="lead">
                <?= e::html($oportunidade['empresa_nome'] ?? 'Empresa não informada') ?>
            </p>
        </section>

        <section class="panel">
            <div class="meta-list">
                <div>
                    <strong>Área:</strong>
                    <?= e::html($oportunidade['area'] ?? 'Não informada') ?>
                </div>

                <div>
                    <strong>Status:</strong>
                    <?= e::html($oportunidade['status'] ?? 'Não informado') ?>
                </div>

                <div>
                    <strong>Modalidade:</strong>
                    <?= e::html($oportunidade['modalidade'] ?? 'Não informada') ?>
                </div>

                <div>
                    <strong>Tipo:</strong>
                    <?= e::html($oportunidade['tipo_oportunidade'] ?? 'Não informado') ?>
                </div>

                <div>
                    <strong>Local:</strong>
                    <?= e::html(trim(($oportunidade['cidade'] ?? '') . ' / ' . ($oportunidade['estado'] ?? ''))) ?>
                </div>

                <div>
                    <strong>Encerramento:</strong>
                    <?= e::html($oportunidade['data_encerramento'] ?? 'Não informado') ?>
                </div>
            </div>

            <article class="opportunity-detail-body">
                <h2>Descrição</h2>
                <p><?= nl2br(e::html($oportunidade['descricao'] ?? '')) ?></p>

                <h2>Requisitos</h2>
                <p><?= nl2br(e::html($oportunidade['requisitos'] ?? 'Não informado')) ?></p>
            </article>

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
                    <a class="button-outline" href="/login.php?acao=cognito">
                        Entrar para favoritar
                    </a>
                <?php endif; ?>

                <?php if (($oportunidade['status'] ?? '') === 'publicada'): ?>
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

                <a class="button-outline" href="/api/oportunidades.php">Voltar</a>
            </div>
        </section>
    </div>
</main>

<script src="/assets/js/csrf.js"></script>
<script src="/assets/js/crypto-utils.js"></script>
<script src="/assets/js/encrypted-form.js"></script>
<?php
require dirname(__DIR__) . '/layout/footer.php';