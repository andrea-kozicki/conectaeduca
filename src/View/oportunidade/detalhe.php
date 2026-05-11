<?php
declare(strict_types=1);

use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';
?>

<section>
    <h2><?= e::html($oportunidade['titulo'] ?? '') ?></h2>

    <p>
        <strong>Empresa:</strong>
        <?= e::html($oportunidade['empresa_nome'] ?? '') ?>
    </p>

    <p>
        <strong>Área:</strong>
        <?= e::html($oportunidade['area'] ?? '') ?>
    </p>

    <p>
        <strong>Status:</strong>
        <?= e::html($oportunidade['status'] ?? '') ?>
    </p>

    <article>
        <?= nl2br(e::html($oportunidade['descricao'] ?? '')) ?>
    </article>

    <form method="post" action="/api/inscricoes.php">
        <?= Csrf::inputField() ?>
        <input
            type="hidden"
            name="oportunidade_id"
            value="<?= e::attr((string) ($oportunidade['id'] ?? '')) ?>"
        >
        <button type="submit">Inscrever-se</button>
    </form>
</section>

<?php
require dirname(__DIR__) . '/layout/footer.php';