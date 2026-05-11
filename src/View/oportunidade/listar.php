<?php
declare(strict_types=1);

use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';
?>

<section>
    <h2>Oportunidades</h2>

    <form method="get" action="/api/oportunidades.php">
        <div>
            <label for="busca">Buscar</label>
            <input
                type="text"
                id="busca"
                name="busca"
                maxlength="100"
                value="<?= e::attr($_GET['busca'] ?? '') ?>"
            >
        </div>

        <div>
            <label for="area">Área</label>
            <input
                type="text"
                id="area"
                name="area"
                maxlength="80"
                value="<?= e::attr($_GET['area'] ?? '') ?>"
            >
        </div>

        <button type="submit">Filtrar</button>
    </form>

    <?php if (empty($oportunidades)): ?>
        <p>Nenhuma oportunidade encontrada.</p>
    <?php else: ?>
        <ul>
            <?php foreach ($oportunidades as $oportunidade): ?>
                <li>
                    <h3>
                        <a href="/api/oportunidades.php?id=<?= e::url((string) $oportunidade['id']) ?>">
                            <?= e::html($oportunidade['titulo'] ?? '') ?>
                        </a>
                    </h3>

                    <p>
                        <strong>Empresa:</strong>
                        <?= e::html($oportunidade['empresa_nome'] ?? '') ?>
                    </p>

                    <p>
                        <strong>Área:</strong>
                        <?= e::html($oportunidade['area'] ?? '') ?>
                    </p>

                    <p>
                        <?= e::html(mb_strimwidth($oportunidade['descricao'] ?? '', 0, 180, '...')) ?>
                    </p>

                    <form method="post" action="/api/inscricoes.php">
                        <?= Csrf::inputField() ?>
                        <input
                            type="hidden"
                            name="oportunidade_id"
                            value="<?= e::attr((string) $oportunidade['id']) ?>"
                        >
                        <button type="submit">Inscrever-se</button>
                    </form>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>

<?php
require dirname(__DIR__) . '/layout/footer.php';