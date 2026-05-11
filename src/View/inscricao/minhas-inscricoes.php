<?php
declare(strict_types=1);

use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';
?>

<section>
    <h2>Minhas inscrições</h2>

    <?php if (empty($inscricoes)): ?>
        <p>Você ainda não possui inscrições.</p>
    <?php else: ?>
        <table>
            <thead>
                <tr>
                    <th>Oportunidade</th>
                    <th>Empresa</th>
                    <th>Status</th>
                    <th>Data</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($inscricoes as $inscricao): ?>
                    <tr>
                        <td><?= e::html($inscricao['oportunidade_titulo'] ?? '') ?></td>
                        <td><?= e::html($inscricao['empresa_nome'] ?? '') ?></td>
                        <td><?= e::html($inscricao['status'] ?? '') ?></td>
                        <td><?= e::html($inscricao['criado_em'] ?? '') ?></td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    <?php endif; ?>
</section>

<?php
require dirname(__DIR__) . '/layout/footer.php';