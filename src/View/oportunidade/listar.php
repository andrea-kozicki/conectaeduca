<?php
declare(strict_types=1);

use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Oportunidades educacionais</span>
            <h1>Encontre uma oportunidade</h1>
            <p class="lead">
                Consulte cursos, bolsas, oficinas, estágios e projetos disponíveis no ConectaEduca.
            </p>
        </section>

        <section class="panel toolbar-card">
            <form method="get" action="/api/oportunidades.php" class="form-grid">
                <div class="form-group">
                    <label for="busca">Buscar</label>
                    <input
                        type="text"
                        id="busca"
                        name="busca"
                        maxlength="100"
                        placeholder="Ex.: Linux, segurança, estágio..."
                        value="<?= e::attr($_GET['busca'] ?? '') ?>"
                    >
                </div>

                <div class="form-group">
                    <label for="area">Área</label>
                    <input
                        type="text"
                        id="area"
                        name="area"
                        maxlength="80"
                        placeholder="Ex.: Cibersegurança"
                        value="<?= e::attr($_GET['area'] ?? '') ?>"
                    >
                </div>

                <div class="form-group">
                    <label for="modalidade">Modalidade</label>
                    <select id="modalidade" name="modalidade">
                        <option value="">Todas</option>
                        <option value="presencial" <?= ($_GET['modalidade'] ?? '') === 'presencial' ? 'selected' : '' ?>>Presencial</option>
                        <option value="remoto" <?= ($_GET['modalidade'] ?? '') === 'remoto' ? 'selected' : '' ?>>Remoto</option>
                        <option value="hibrido" <?= ($_GET['modalidade'] ?? '') === 'hibrido' ? 'selected' : '' ?>>Híbrido</option>
                    </select>
                </div>

                <div class="form-group">
                    <label for="tipo">Tipo</label>
                    <select id="tipo" name="tipo">
                        <option value="">Todos</option>
                        <option value="estagio" <?= ($_GET['tipo'] ?? '') === 'estagio' ? 'selected' : '' ?>>Estágio</option>
                        <option value="emprego" <?= ($_GET['tipo'] ?? '') === 'emprego' ? 'selected' : '' ?>>Emprego</option>
                        <option value="trainee" <?= ($_GET['tipo'] ?? '') === 'trainee' ? 'selected' : '' ?>>Trainee</option>
                        <option value="bolsa" <?= ($_GET['tipo'] ?? '') === 'bolsa' ? 'selected' : '' ?>>Bolsa</option>
                        <option value="voluntariado" <?= ($_GET['tipo'] ?? '') === 'voluntariado' ? 'selected' : '' ?>>Voluntariado</option>
                        <option value="outro" <?= ($_GET['tipo'] ?? '') === 'outro' ? 'selected' : '' ?>>Outro</option>
                    </select>
                </div>

                <div class="form-actions">
                    <button class="button" type="submit">Filtrar</button>
                    <a class="button-secondary" href="/api/oportunidades.php">Limpar filtros</a>
                </div>
            </form>
        </section>

        <?php if (empty($oportunidades)): ?>
            <div class="empty-state">
                Nenhuma oportunidade encontrada.
            </div>
        <?php else: ?>
            <section class="opportunity-grid" aria-label="Lista de oportunidades">
                <?php foreach ($oportunidades as $oportunidade): ?>
                    <article class="opportunity-card">
                        <h2>
                            <a
                                class="opportunity-title-link"
                                href="/api/oportunidades.php?id=<?= e::url((string) $oportunidade['id']) ?>"
                            >
                                <?= e::html($oportunidade['titulo'] ?? '') ?>
                            </a>
                        </h2>

                        <div class="meta-list">
                            <div>
                                <strong>Empresa:</strong>
                                <?= e::html($oportunidade['empresa_nome'] ?? 'Empresa não informada') ?>
                            </div>

                            <div>
                                <strong>Área:</strong>
                                <?= e::html($oportunidade['area'] ?? 'Área não informada') ?>
                            </div>
                        </div>

                        <p class="opportunity-description">
                            <?= e::html(mb_strimwidth($oportunidade['descricao'] ?? '', 0, 220, '...')) ?>
                        </p>

                       <div class="badge-row">
                            <?php if (!empty($oportunidade['area'])): ?>
                                <a
                                    class="badge"
                                    href="/api/oportunidades.php?area=<?= e::url((string) $oportunidade['area']) ?>"
                                    title="Filtrar por área"
                                >
                                    <?= e::html($oportunidade['area']) ?>
                                </a>
                            <?php endif; ?>

                            <?php if (!empty($oportunidade['modalidade'])): ?>
                                <a
                                    class="badge"
                                    href="/api/oportunidades.php?modalidade=<?= e::url((string) $oportunidade['modalidade']) ?>"
                                    title="Filtrar por modalidade"
                                >
                                    <?= e::html($oportunidade['modalidade']) ?>
                                </a>
                            <?php endif; ?>

                            <?php if (!empty($oportunidade['tipo_oportunidade'])): ?>
                                <a
                                    class="badge"
                                    href="/api/oportunidades.php?tipo=<?= e::url((string) $oportunidade['tipo_oportunidade']) ?>"
                                    title="Filtrar por tipo"
                                >
                                    <?= e::html($oportunidade['tipo_oportunidade']) ?>
                                </a>
                            <?php endif; ?>

                            <?php if (!empty($oportunidade['status'])): ?>
                                <span class="badge"><?= e::html($oportunidade['status']) ?></span>
                            <?php endif; ?>
                        </div>

                        <div class="card-actions">
                            <button
                                class="button-outline js-toggle-details"
                                type="button"
                                aria-expanded="false"
                                aria-controls="detalhes-op-<?= e::attr((string) $oportunidade['id']) ?>"
                            >
                                Ver detalhes
                            </button>

                            <div
                                id="detalhes-op-<?= e::attr((string) $oportunidade['id']) ?>"
                                class="opportunity-details"
                                hidden
                            >
                                <h3>Detalhes da oportunidade</h3>

                                <p>
                                    <strong>Requisitos:</strong>
                                    <?= e::html($oportunidade['requisitos'] ?? 'Não informado') ?>
                                </p>

                                <p>
                                    <strong>Modalidade:</strong>
                                    <?= e::html($oportunidade['modalidade'] ?? 'Não informada') ?>
                                </p>

                                <p>
                                    <strong>Tipo:</strong>
                                    <?= e::html($oportunidade['tipo_oportunidade'] ?? 'Não informado') ?>
                                </p>

                                <p>
                                    <strong>Local:</strong>
                                    <?= e::html(trim(($oportunidade['cidade'] ?? '') . ' / ' . ($oportunidade['estado'] ?? ''))) ?>
                                </p>

                                <p>
                                    <strong>Encerramento:</strong>
                                    <?= e::html($oportunidade['data_encerramento'] ?? 'Não informado') ?>
                                </p>
                            </div>    

                            <form method="post" action="/api/inscricoes.php">
                                <?= Csrf::inputField() ?>
                                <input
                                    type="hidden"
                                    name="oportunidade_id"
                                    value="<?= e::attr((string) $oportunidade['id']) ?>"
                                >
                                <button class="button" type="submit">Inscrever-se</button>
                            </form>
                        </div>
                    </article>
                <?php endforeach; ?>
            </section>
        <?php endif; ?>
    </div>
</main>

<script src="/assets/js/oportunidades.js" defer></script>
<?php
require dirname(__DIR__) . '/layout/footer.php';