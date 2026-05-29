<?php
declare(strict_types=1);

use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . '/layout/header.php';

$cpf = (string) ($usuario['cpf'] ?? '');
$telefone = (string) ($usuario['telefone'] ?? '');
$dataNascimento = (string) ($usuario['data_nascimento'] ?? '');
$cognitoAtivo = !empty($usuario['cognito_sub']);
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Dados de usuário</span>
            <h1>Meu perfil</h1>
            <p class="lead">
                Consulte e atualize seus dados complementares. E-mail, senha e MFA são gerenciados pelo Amazon Cognito.
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

        <section class="panel">
            <form method="post" action="/perfil.php" class="form-grid">
                <?= Csrf::inputField() ?>

                <div class="form-group">
                    <label for="nome">Nome</label>
                    <input
                        type="text"
                        id="nome"
                        name="nome"
                        maxlength="150"
                        required
                        value="<?= e::attr($usuario['nome'] ?? '') ?>"
                    >
                </div>

                <div class="form-group">
                    <label for="email">E-mail</label>
                    <input
                        type="email"
                        id="email"
                        value="<?= e::attr($usuario['email'] ?? '') ?>"
                        readonly
                    >
                    <p class="help-text">O e-mail vem do Cognito e não é alterado nesta tela.</p>
                </div>

                <div class="form-group">
                    <label for="cpf">CPF</label>
                    <input
                        type="text"
                        id="cpf"
                        name="cpf"
                        maxlength="14"
                        placeholder="Somente números ou formato 000.000.000-00"
                        value="<?= e::attr($cpf) ?>"
                    >
                </div>

                <div class="form-group">
                    <label for="telefone">Telefone</label>
                    <input
                        type="text"
                        id="telefone"
                        name="telefone"
                        maxlength="20"
                        placeholder="Ex.: (41) 99999-0000"
                        value="<?= e::attr($telefone) ?>"
                    >
                </div>

                <div class="form-group">
                    <label for="data_nascimento">Data de nascimento</label>
                    <input
                        type="date"
                        id="data_nascimento"
                        name="data_nascimento"
                        value="<?= e::attr($dataNascimento) ?>"
                    >
                </div>

                <div class="form-group">
                    <label>Perfil de acesso</label>
                    <input
                        type="text"
                        value="<?= e::attr($usuario['role'] ?? 'usuario') ?>"
                        readonly
                    >
                    <p class="help-text">O perfil define permissões internas da aplicação.</p>
                </div>

                <div class="form-group">
                    <label>Conta ativada</label>
                    <input
                        type="text"
                        value="<?= ((int) ($usuario['conta_ativada'] ?? 0)) === 1 ? 'Sim' : 'Não' ?>"
                        readonly
                    >
                </div>

                <div class="form-group">
                    <label>Último login</label>
                    <input
                        type="text"
                        value="<?= e::attr($usuario['ultimo_login_em'] ?? 'Não registrado') ?>"
                        readonly
                    >
                </div>

                <div class="form-group full">
                    <div class="security-note">
                        <strong>Autenticação:</strong>
                        <?= $cognitoAtivo
                            ? 'Conta vinculada ao Amazon Cognito. MFA, senha e recuperação de conta ficam centralizados no provedor de identidade.'
                            : 'Conta local. Para o fluxo principal do projeto, recomenda-se autenticação via Cognito.' ?>
                    </div>
                </div>

                <div class="form-group full">
                    <div class="inline-actions">
                        <button class="button" type="submit">Salvar perfil</button>
                        <a class="button-secondary" href="/dashboard.php">Voltar ao dashboard</a>
                    </div>
                </div>
            </form>
        </section>
    </div>
</main>

<?php
require dirname(__DIR__) . '/layout/footer.php';