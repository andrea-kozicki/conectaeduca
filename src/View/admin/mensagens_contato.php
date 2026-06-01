<?php
declare(strict_types=1);

use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';

function ce_admin_contato_categoria_label(string $categoria): string
{
    return match ($categoria) {
        'duvida' => 'Dúvida',
        'suporte' => 'Suporte',
        'privacidade' => 'Privacidade',
        'seguranca' => 'Segurança',
        'acessibilidade' => 'Acessibilidade',
        'outro' => 'Outro',
        default => $categoria,
    };
}
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Administração</span>
            <h1>Mensagens do Fale Conosco</h1>
            <p class="lead">
                Área restrita para visualizar mensagens recebidas. O conteúdo foi salvo cifrado no banco
                e é descriptografado apenas no backend autorizado.
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

        <?php if (empty($mensagens)): ?>
            <div class="empty-state">
                Nenhuma mensagem recebida até o momento.
            </div>
        <?php else: ?>
            <section class="management-grid">
                <?php foreach ($mensagens as $mensagem): ?>
                    <article class="management-card">
                        <div class="management-card-header">
                            <div>
                                <span class="eyebrow">
                                    <?= e::html(ce_admin_contato_categoria_label((string) ($mensagem['categoria'] ?? ''))) ?>
                                </span>
                                <h2><?= e::html($mensagem['assunto'] ?? '') ?></h2>
                            </div>

                            <span class="status-pill <?= e::attr('status-' . ($mensagem['status'] ?? '')) ?>">
                                <?= e::html($mensagem['status'] ?? '') ?>
                            </span>
                        </div>

                        <div class="meta-list">
                            <div>
                                <strong>Usuário:</strong>
                                <?= e::html($mensagem['usuario_nome'] ?? '') ?>
                            </div>

                            <div>
                                <strong>E-mail:</strong>
                                <?= e::html($mensagem['usuario_email'] ?? '') ?>
                            </div>

                            <div>
                                <strong>Enviada em:</strong>
                                <?= e::html($mensagem['criado_em'] ?? '') ?>
                            </div>

                            <div>
                                <strong>Algoritmo:</strong>
                                <?= e::html($mensagem['algoritmo'] ?? 'AES-256-GCM + RSA-OAEP') ?>
                            </div>
                        </div>

                        <?php if (!empty($mensagem['erro_descriptografia'])): ?>
                            <div class="feedback feedback-error">
                                Erro ao descriptografar:
                                <?= e::html($mensagem['erro_descriptografia']) ?>
                            </div>
                        <?php else: ?>
                            <div class="crypto-info-box">
                                <h3>Mensagem descriptografada</h3>
                                <p><?= nl2br(e::html($mensagem['mensagem_descriptografada'] ?? '')) ?></p>
                            </div>
                        <?php endif; ?>
                    </article>
                <?php endforeach; ?>
            </section>
        <?php endif; ?>
    </div>
</main>

<?php
require dirname(__DIR__) . '/layout/footer.php';