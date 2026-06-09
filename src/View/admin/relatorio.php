<?php
declare(strict_types=1);

use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . "/layout/header.php";

$indicadores = [
    [
        "titulo" => "Usuários",
        "valor" => (int) ($resumo["usuarios"] ?? 0),
        "descricao" => "Contas cadastradas na base local, incluindo usuários comuns, empresas e administradores.",
    ],
    [
        "titulo" => "Empresas",
        "valor" => (int) ($resumo["empresas"] ?? 0),
        "descricao" => "Registros de empresas vinculadas à publicação e gestão de oportunidades.",
    ],
    [
        "titulo" => "Oportunidades",
        "valor" => (int) ($resumo["oportunidades"] ?? 0),
        "descricao" => "Cursos, bolsas, oficinas, vagas e demais oportunidades registradas no sistema.",
    ],
    [
        "titulo" => "Inscrições",
        "valor" => (int) ($resumo["inscricoes"] ?? 0),
        "descricao" => "Candidaturas feitas por usuários em oportunidades disponíveis.",
    ],
];
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Administração</span>
            <h1>Relatório administrativo</h1>
            <p class="lead">
                Visão consolidada dos principais cadastros e movimentações do ConectaEduca.
                Esta área é restrita ao perfil administrador.
            </p>
        </section>

        <section class="panel">
            <div class="dashboard-grid">
                <?php foreach ($indicadores as $indicador): ?>
                    <article class="profile-card">
                        <strong><?= e::html($indicador["titulo"]) ?></strong>
                        <span><?= e::html((string) $indicador["valor"]) ?></span>
                        <p class="muted">
                            <?= e::html($indicador["descricao"]) ?>
                        </p>
                    </article>
                <?php endforeach; ?>
            </div>

            <div class="security-note">
                <strong>Controle administrativo:</strong>
                esta página é protegida por autorização de perfil e só pode ser acessada por contas com role
                <strong>admin</strong>.
            </div>

            <div class="inline-actions">
                <a class="button" href="/admin/mensagens_contato.php">Ver mensagens recebidas</a>
                <a class="button-secondary" href="/dashboard.php">Voltar ao dashboard</a>
                <a class="button-outline" href="/perfil.php">Editar perfil</a>
            </div>
        </section>

        <section class="table-card">
            <div class="table-responsive">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Indicador</th>
                            <th>Total</th>
                            <th>O que representa</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($indicadores as $indicador): ?>
                            <tr>
                                <td>
                                    <strong><?= e::html($indicador["titulo"]) ?></strong>
                                </td>
                                <td>
                                    <?= e::html((string) $indicador["valor"]) ?>
                                </td>
                                <td>
                                    <?= e::html($indicador["descricao"]) ?>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </section>

        <section class="panel">
            <span class="eyebrow">Observação de segurança</span>
            <p class="lead">
                Os números apresentados são agregados administrativos. Dados sensíveis, mensagens do Fale Conosco
                e fluxos autenticados permanecem protegidos por controle de acesso, CSRF, criptografia e auditoria.
            </p>
        </section>
    </div>
</main>

<?php
require dirname(__DIR__) . "/layout/footer.php";
