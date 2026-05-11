<?php
declare(strict_types=1);

use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';
?>

<section>
    <h2>Dashboard</h2>

    <p>Você está autenticada no ConectaEduca.</p>

    <table>
        <tbody>
            <tr>
                <th>ID</th>
                <td><?= e::html((string) ($user['id'] ?? '')) ?></td>
            </tr>
            <tr>
                <th>Nome</th>
                <td><?= e::html($user['nome'] ?? '') ?></td>
            </tr>
            <tr>
                <th>E-mail</th>
                <td><?= e::html($user['email'] ?? '') ?></td>
            </tr>
            <tr>
                <th>Perfil</th>
                <td><?= e::html($user['role'] ?? '') ?></td>
            </tr>
        </tbody>
    </table>

    <p>
        <a href="/api/inscricoes.php">Ver minhas inscrições</a>
    </p>
</section>

<?php
require dirname(__DIR__) . '/layout/footer.php';