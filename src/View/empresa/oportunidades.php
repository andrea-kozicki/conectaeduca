<?php
declare(strict_types=1);

use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';

$user = Authorization::user();
$isAdmin = ($user['role'] ?? '') === 'admin';

function ce_status_label(string $status): string
{
    return match ($status) {
        'rascunho' => 'Rascunho',
        'publicada' => 'Publicada',
        'suspensa' => 'Suspensa',
        'encerrada' => 'Encerrada',
        default => $status,
    };
}

function ce_datetime_local(?string $valor): string
{
    $valor = trim((string) $valor);

    if ($valor === '') {
        return '';
    }

    try {
        return (new DateTimeImmutable($valor))->format('Y-m-d\TH:i');
    } catch (Throwable) {
        return '';
    }
}

$modalidades = [
    'presencial' => 'Presencial',
    'remoto' => 'Remoto',
    'hibrido' => 'Híbrido',
];

$tipos = [
    'estagio' => 'Estágio',
    'emprego' => 'Emprego',
    'trainee' => 'Trainee',
    'bolsa' => 'Bolsa',
    'voluntariado' => 'Voluntariado',
    'outro' => 'Outro',
];

$statusOptions = [
    'rascunho' => 'Rascunho',
    'publicada' => 'Publicada',
    'suspensa' => 'Suspensa',
    'encerrada' => 'Encerrada',
];
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Empresa / Administração</span>
            <h1>Gerenciar oportunidades</h1>
            <p class="lead">
                Cadastre, edite, publique, suspenda ou encerre oportunidades educacionais.
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
            <h2>Nova oportunidade</h2>

            <form method="post" action="/empresa/oportunidades.php" class="stack-form">
                <?= Csrf::inputField() ?>
                <input type="hidden" name="action" value="criar">

                <?php if ($isAdmin): ?>
                    <label>
                        Empresa
                        <select name="empresa_id" required>
                            <option value="">Selecione</option>
                            <?php foreach ($empresas as $empresa): ?>
                                <option value="<?= e::attr((string) $empresa['id']) ?>">
                                    <?= e::html($empresa['nome'] ?? $empresa['razao_social'] ?? '') ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </label>
                <?php endif; ?>

                <div class="form-grid">
                    <label>
                        Título
                        <input type="text" name="titulo" maxlength="180" required>
                    </label>

                    <label>
                        Área de conhecimento
                        <input type="text" name="area_conhecimento" maxlength="120" placeholder="Ex.: Tecnologia">
                    </label>

                    <label>
                        Modalidade
                        <select name="modalidade" required>
                            <?php foreach ($modalidades as $value => $label): ?>
                                <option value="<?= e::attr($value) ?>"><?= e::html($label) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </label>

                    <label>
                        Tipo
                        <select name="tipo_oportunidade" required>
                            <?php foreach ($tipos as $value => $label): ?>
                                <option value="<?= e::attr($value) ?>"><?= e::html($label) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </label>

                    <label>
                        Cidade
                        <input type="text" name="cidade" maxlength="120">
                    </label>

                    <label>
                        Estado
                        <input type="text" name="estado" maxlength="2" placeholder="PR">
                    </label>

                    <label>
                        Status inicial
                        <select name="status" required>
                            <option value="rascunho">Rascunho</option>
                            <option value="publicada">Publicada</option>
                        </select>
                    </label>

                    <label>
                        Encerramento
                        <input type="datetime-local" name="data_encerramento">
                    </label>
                </div>

                <label>
                    Descrição
                    <textarea name="descricao" rows="5" required minlength="10"></textarea>
                </label>

                <label>
                    Requisitos
                    <textarea name="requisitos" rows="4"></textarea>
                </label>

                <button class="button" type="submit">Criar oportunidade</button>
            </form>
        </section>

        <section class="management-section">
            <h2>Oportunidades cadastradas</h2>

            <?php if (empty($oportunidades)): ?>
                <div class="empty-state">
                    Nenhuma oportunidade cadastrada foi encontrada.
                </div>
            <?php else: ?>
                <div class="management-grid">
                    <?php foreach ($oportunidades as $oportunidade): ?>
                        <?php
                        $statusAtual = (string) ($oportunidade['status'] ?? '');
                        $totalInscricoes = (int) ($oportunidade['total_inscricoes'] ?? 0);
                        ?>

                        <article class="management-card">
                            <div class="management-card-header">
                                <div>
                                    <span class="status-pill <?= e::attr('status-' . $statusAtual) ?>">
                                        <?= e::html(ce_status_label($statusAtual)) ?>
                                    </span>
                                    <h3><?= e::html($oportunidade['titulo'] ?? '') ?></h3>
                                    <p class="muted">
                                        <?= e::html($oportunidade['empresa_nome'] ?? '') ?>
                                        · <?= e::html((string) $totalInscricoes) ?> inscrição(ões)
                                    </p>
                                </div>
                            </div>

                            <form method="post" action="/empresa/oportunidades.php" class="stack-form">
                                <?= Csrf::inputField() ?>
                                <input type="hidden" name="action" value="atualizar">
                                <input type="hidden" name="id" value="<?= e::attr((string) $oportunidade['id']) ?>">

                                <?php if ($isAdmin): ?>
                                    <label>
                                        Empresa
                                        <select name="empresa_id" required>
                                            <?php foreach ($empresas as $empresa): ?>
                                                <option
                                                    value="<?= e::attr((string) $empresa['id']) ?>"
                                                    <?= (int) $oportunidade['empresa_id'] === (int) $empresa['id'] ? 'selected' : '' ?>
                                                >
                                                    <?= e::html($empresa['nome'] ?? $empresa['razao_social'] ?? '') ?>
                                                </option>
                                            <?php endforeach; ?>
                                        </select>
                                    </label>
                                <?php endif; ?>

                                <div class="form-grid">
                                    <label>
                                        Título
                                        <input
                                            type="text"
                                            name="titulo"
                                            maxlength="180"
                                            required
                                            value="<?= e::attr($oportunidade['titulo'] ?? '') ?>"
                                        >
                                    </label>

                                    <label>
                                        Área
                                        <input
                                            type="text"
                                            name="area_conhecimento"
                                            maxlength="120"
                                            value="<?= e::attr($oportunidade['area_conhecimento'] ?? '') ?>"
                                        >
                                    </label>

                                    <label>
                                        Modalidade
                                        <select name="modalidade" required>
                                            <?php foreach ($modalidades as $value => $label): ?>
                                                <option
                                                    value="<?= e::attr($value) ?>"
                                                    <?= ($oportunidade['modalidade'] ?? '') === $value ? 'selected' : '' ?>
                                                >
                                                    <?= e::html($label) ?>
                                                </option>
                                            <?php endforeach; ?>
                                        </select>
                                    </label>

                                    <label>
                                        Tipo
                                        <select name="tipo_oportunidade" required>
                                            <?php foreach ($tipos as $value => $label): ?>
                                                <option
                                                    value="<?= e::attr($value) ?>"
                                                    <?= ($oportunidade['tipo_oportunidade'] ?? '') === $value ? 'selected' : '' ?>
                                                >
                                                    <?= e::html($label) ?>
                                                </option>
                                            <?php endforeach; ?>
                                        </select>
                                    </label>

                                    <label>
                                        Cidade
                                        <input
                                            type="text"
                                            name="cidade"
                                            maxlength="120"
                                            value="<?= e::attr($oportunidade['cidade'] ?? '') ?>"
                                        >
                                    </label>

                                    <label>
                                        Estado
                                        <input
                                            type="text"
                                            name="estado"
                                            maxlength="2"
                                            value="<?= e::attr($oportunidade['estado'] ?? '') ?>"
                                        >
                                    </label>

                                    <label>
                                        Status
                                        <select name="status" required>
                                            <?php foreach ($statusOptions as $value => $label): ?>
                                                <option
                                                    value="<?= e::attr($value) ?>"
                                                    <?= $statusAtual === $value ? 'selected' : '' ?>
                                                >
                                                    <?= e::html($label) ?>
                                                </option>
                                            <?php endforeach; ?>
                                        </select>
                                    </label>

                                    <label>
                                        Encerramento
                                        <input
                                            type="datetime-local"
                                            name="data_encerramento"
                                            value="<?= e::attr(ce_datetime_local($oportunidade['data_encerramento'] ?? null)) ?>"
                                        >
                                    </label>
                                </div>

                                <label>
                                    Descrição
                                    <textarea name="descricao" rows="5" required><?= e::html($oportunidade['descricao'] ?? '') ?></textarea>
                                </label>

                                <label>
                                    Requisitos
                                    <textarea name="requisitos" rows="4"><?= e::html($oportunidade['requisitos'] ?? '') ?></textarea>
                                </label>

                                <button class="button" type="submit">Salvar edição</button>
                            </form>

                            <div class="inline-actions">
                                <?php foreach (['publicada' => 'Publicar', 'suspensa' => 'Suspender', 'encerrada' => 'Encerrar'] as $status => $label): ?>
                                    <form method="post" action="/empresa/oportunidades.php">
                                        <?= Csrf::inputField() ?>
                                        <input type="hidden" name="action" value="status">
                                        <input type="hidden" name="id" value="<?= e::attr((string) $oportunidade['id']) ?>">
                                        <input type="hidden" name="status" value="<?= e::attr($status) ?>">
                                        <button class="button-outline" type="submit">
                                            <?= e::html($label) ?>
                                        </button>
                                    </form>
                                <?php endforeach; ?>

                                <?php if ($statusAtual === 'rascunho' && $totalInscricoes === 0): ?>
                                    <form method="post" action="/empresa/oportunidades.php" onsubmit="return confirm('Excluir esta oportunidade em rascunho?');">
                                        <?= Csrf::inputField() ?>
                                        <input type="hidden" name="action" value="excluir">
                                        <input type="hidden" name="id" value="<?= e::attr((string) $oportunidade['id']) ?>">
                                        <button class="button-outline danger-action" type="submit">Excluir</button>
                                    </form>
                                <?php endif; ?>
                            </div>
                        </article>
                    <?php endforeach; ?>
                </div>
            <?php endif; ?>
        </section>
    </div>
</main>

<?php
require dirname(__DIR__) . '/layout/footer.php';