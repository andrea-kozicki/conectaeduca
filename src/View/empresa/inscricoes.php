<?php
declare(strict_types=1);

use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';

function status_class_empresa(string $status): string
{
    return 'status-' . preg_replace('/[^a-z0-9_]/', '', strtolower($status));
}

function status_label_empresa(string $status): string
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

function formatar_data_empresa(?string $valor): string
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

$statusOptions = [
    'em_analise' => 'Em análise',
    'aprovada' => 'Aprovada',
    'rejeitada' => 'Rejeitada',
    'encerrada' => 'Encerrada',
];
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Empresa / Administração</span>
            <h1>Inscrições recebidas</h1>
            <p class="lead">
                Acompanhe candidaturas recebidas nas oportunidades vinculadas à empresa e atualize o status de cada inscrição.
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
                Nenhuma inscrição recebida foi encontrada.
            </div>
        <?php else: ?>
            <section class="table-card">
                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Candidato</th>
                                <th>Oportunidade</th>
                                <th>Empresa</th>
                                <th>Status atual</th>
                                <th>Data</th>
                                <th>Atualizar</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($inscricoes as $inscricao): ?>
                                <?php
                                $statusAtual = (string) ($inscricao['status'] ?? '');
                                $podeAtualizar = !in_array($statusAtual, ['cancelada_pelo_usuario', 'encerrada'], true);
                                ?>

                                <tr>
                                    <td>
                                        <strong><?= e::html($inscricao['usuario_nome'] ?? '') ?></strong><br>
                                        <span class="muted"><?= e::html($inscricao['usuario_email'] ?? '') ?></span>
                                    </td>

                                    <td><?= e::html($inscricao['oportunidade_titulo'] ?? '') ?></td>

                                    <td><?= e::html($inscricao['empresa_nome'] ?? '') ?></td>

                                    <td>
                                        <span class="status-pill <?= e::attr(status_class_empresa($statusAtual)) ?>">
                                            <?= e::html(status_label_empresa($statusAtual)) ?>
                                        </span>
                                    </td>

                                    <td class="nowrap">
                                        <?= e::html(formatar_data_empresa($inscricao['criado_em'] ?? null)) ?>
                                    </td>

                                    <td>
                                        <?php if ($podeAtualizar): ?>
                                            <form method="post" data-encrypted-form="true" action="/empresa/inscricoes.php" class="table-form">
                                                <?= Csrf::inputField() ?>

                                                <input
                                                    type="hidden"
                                                    name="id"
                                                    value="<?= e::attr((string) ($inscricao['id'] ?? '')) ?>"
                                                >

                                                <label for="status-<?= e::attr((string) ($inscricao['id'] ?? '')) ?>">
                                                    Novo status
                                                </label>

                                                <select
                                                    id="status-<?= e::attr((string) ($inscricao['id'] ?? '')) ?>"
                                                    name="status"
                                                    required
                                                >
                                                    <?php foreach ($statusOptions as $value => $label): ?>
                                                        <option
                                                            value="<?= e::attr($value) ?>"
                                                            <?= $statusAtual === $value ? 'selected' : '' ?>
                                                        >
                                                            <?= e::html($label) ?>
                                                        </option>
                                                    <?php endforeach; ?>
                                                </select>

                                                <label for="obs-<?= e::attr((string) ($inscricao['id'] ?? '')) ?>">
                                                    Observação
                                                </label>

                                                <textarea
                                                    id="obs-<?= e::attr((string) ($inscricao['id'] ?? '')) ?>"
                                                    name="observacoes_empresa"
                                                    maxlength="1000"
                                                    rows="4"
                                                    required
                                                    placeholder="Ex.: candidatura aprovada para a próxima etapa."
                                                ><?= e::html($inscricao['observacoes_empresa'] ?? '') ?></textarea>

                                                <small class="form-hint">
                                                    A observação é obrigatória para registrar a justificativa da alteração.
                                                </small>

                                                <button class="button" type="submit">
                                                    Salvar status
                                                </button>
                                            </form>
                                        <?php else: ?>
                                            <span class="muted">
                                                Sem ação disponível.
                                            </span>
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

<script src="/assets/js/csrf.js"></script>
<script src="/assets/js/crypto-utils.js"></script>
<script src="/assets/js/encrypted-form.js"></script>
<?php
require dirname(__DIR__) . '/layout/footer.php';