<?php
declare(strict_types=1);

use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';
?>

<section>
    <h2>Relatório administrativo</h2>

    <p>
        Área restrita a administradores.
    </p>

    <table>
        <thead>
            <tr>
                <th>Indicador</th>
                <th>Total</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Usuários</td>
                <td><?= e::html((string) ($resumo['usuarios'] ?? 0)) ?></td>
            </tr>
            <tr>
                <td>Empresas</td>
                <td><?= e::html((string) ($resumo['empresas'] ?? 0)) ?></td>
            </tr>
            <tr>
                <td>Oportunidades</td>
                <td><?= e::html((string) ($resumo['oportunidades'] ?? 0)) ?></td>
            </tr>
            <tr>
                <td>Inscrições</td>
                <td><?= e::html((string) ($resumo['inscricoes'] ?? 0)) ?></td>
            </tr>
        </tbody>
    </table>
</section>

<?php
require dirname(__DIR__) . '/layout/footer.php';