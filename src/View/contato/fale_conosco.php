<?php
declare(strict_types=1);

use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';

function ce_contato_categoria_label(string $categoria): string
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
            <span class="eyebrow">Atendimento</span>
            <h1>Fale conosco</h1>
            <p class="lead">
                Envie uma mensagem para a equipe do ConectaEduca. O conteúdo da mensagem é armazenado
                com criptografia híbrida no banco de dados.
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

        <section class="management-card">
            <h2>Nova mensagem</h2>

            <form method="post" action="/fale_conosco.php" class="stack-form" data-encrypted-form="true">
                <?= Csrf::inputField() ?>

                <div class="form-grid">
                    <label>
                        Assunto
                        <input
                            type="text"
                            name="assunto"
                            maxlength="160"
                            required
                            placeholder="Ex.: Dúvida sobre inscrição"
                        >
                    </label>

                    <label>
                        Categoria
                        <select name="categoria" required>
                            <option value="duvida">Dúvida</option>
                            <option value="suporte">Suporte</option>
                            <option value="privacidade">Privacidade</option>
                            <option value="seguranca">Segurança</option>
                            <option value="acessibilidade">Acessibilidade</option>
                            <option value="outro">Outro</option>
                        </select>
                    </label>
                </div>

                <label>
                    Mensagem
                    <textarea
                        name="mensagem"
                        rows="8"
                        maxlength="4000"
                        required
                        placeholder="Descreva sua solicitação..."
                    ></textarea>
                </label>

                <p class="form-hint">
                    O assunto e a categoria ficam visíveis para triagem. O conteúdo da mensagem é cifrado
                    com AES-256-GCM, e a chave simétrica é protegida com RSA-OAEP/SHA-256.
                </p>

                <button class="button" type="submit">
                    Enviar mensagem protegida
                </button>
            </form>
        </section>

        <section class="management-section">
            <h2>Minhas mensagens enviadas</h2>

            <?php if (empty($mensagens)): ?>
                <div class="empty-state">
                    Você ainda não enviou mensagens pelo Fale Conosco.
                </div>
            <?php else: ?>
                <div class="table-wrapper">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Assunto</th>
                                <th>Categoria</th>
                                <th>Status</th>
                                <th>Enviada em</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($mensagens as $mensagem): ?>
                                <tr>
                                    <td><?= e::html($mensagem['assunto'] ?? '') ?></td>
                                    <td><?= e::html(ce_contato_categoria_label((string) ($mensagem['categoria'] ?? ''))) ?></td>
                                    <td>
                                        <span class="status-pill <?= e::attr('status-' . ($mensagem['status'] ?? '')) ?>">
                                            <?= e::html($mensagem['status'] ?? '') ?>
                                        </span>
                                    </td>
                                    <td><?= e::html($mensagem['criado_em'] ?? '') ?></td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            <?php endif; ?>
        </section>
    </div>
</main>

<script src="/assets/js/csrf.js"></script>
<script src="/assets/js/crypto-utils.js"></script>
<script src="/assets/js/encrypted-form.js"></script>

<?php
require dirname(__DIR__) . '/layout/footer.php';