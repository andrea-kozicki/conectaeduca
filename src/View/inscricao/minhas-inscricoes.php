<?php
declare(strict_types=1);

use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';

function status_class(string $status): string
{
    return 'status-' . preg_replace('/[^a-z0-9_]/', '', strtolower($status));
}

function status_label(string $status): string
{
    return match ($status) {
        'enviada' => 'Enviada',
        'em_analise' => 'Em análise',
        'aprovada' => 'Aprovada',
        'rejeitada' => 'Rejeitada',
        'cancelada_pelo_usuario' => 'Cancelada pelo usuário',
        'encerrada' => 'Encerrada',
        default => $status,
    };
}

function pode_cancelar(string $status): bool
{
    return in_array($status, ['enviada', 'em_analise'], true);
}

function formatar_data(?string $valor): string
{
    $valor = trim((string) $valor);

    if ($valor === '') {
        return 'Não informado';
    }

    try {
        return (new DateTimeImmutable($valor))->format('d/m/Y H:i');
    } catch (Throwable) {
        return $valor;
    }
}
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Acompanhamento</span>
            <h1>Minhas inscrições</h1>
            <p class="lead">
                Acompanhe as oportunidades em que você se inscreveu e o status de cada candidatura.
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

        <?php if (empty($inscricoes)): ?>
            <div class="empty-state">
                Você ainda não possui inscrições.
            </div>
        <?php else: ?>
            <section class="table-card">
                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Oportunidade</th>
                                <th>Empresa</th>
                                <th>Status</th>
                                <th>Data</th>
                                <th>Observação</th>
                                <th>Ações</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($inscricoes as $inscricao): ?>
                                <?php $status = (string) ($inscricao['status'] ?? ''); ?>
                                <tr>
                                    <td><?= e::html($inscricao['oportunidade_titulo'] ?? '') ?></td>

                                    <td><?= e::html($inscricao['empresa_nome'] ?? '') ?></td>

                                    <td>
                                        <span class="status-pill <?= e::attr(status_class($status)) ?>">
                                            <?= e::html(status_label($status)) ?>
                                        </span>
                                    </td>

                                    <td class="nowrap">
                                        <?= e::html(formatar_data($inscricao['criado_em'] ?? null)) ?>
                                    </td>

                                    <td>
                                        <?= e::html($inscricao['observacoes_empresa'] ?? 'Sem observações.') ?>
                                    </td>

                                    <td>
                                        <?php if (pode_cancelar($status)): ?>
                                            <form method="post" action="/api/inscricoes.php">
                                                <?= Csrf::inputField() ?>

                                                <input type="hidden" name="action" value="cancelar">

                                                <input
                                                    type="hidden"
                                                    name="id"
                                                    value="<?= e::attr((string) ($inscricao['id'] ?? '')) ?>"
                                                >

                                                <button
                                                    class="button-outline"
                                                    type="submit"
                                                    onclick="return confirm('Tem certeza que deseja cancelar esta candidatura?');"
                                                >
                                                    Cancelar candidatura
                                                </button>
                                            </form>
                                        <?php else: ?>
                                            <span class="muted">Sem ação disponível</span>
                                        <?php endif; ?>
                                    </td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </section>
        <?php endif; ?>
    </div>
</main>

<?php
require dirname(__DIR__) . '/layout/footer.php';