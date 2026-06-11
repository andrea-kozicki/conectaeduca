<?php
declare(strict_types=1);

use ConectaEduca\Security\OutputEncoder as e;

require dirname(__DIR__) . "/layout/header.php";

/** @var array<int, array<string, string|int|null>> $eventos */
$eventos = $eventos ?? [];

function ce_auditoria_evento_label(string $evento): string
{
    return match ($evento) {
        "login_success" => "Login realizado",
        "logout" => "Logout",
        "unauthorized_access_attempt" => "Tentativa sem autenticação",
        "forbidden_access_attempt" => "Acesso negado por perfil",
        "usuario_cadastrado" => "Usuário cadastrado",
        "erro_cadastro_usuario" => "Erro no cadastro",
        "favorito_adicionado" => "Favorito adicionado",
        "favorito_removido" => "Favorito removido",
        "inscricao_criada" => "Inscrição criada",
        "inscricao_cancelada_pelo_usuario" => "Inscrição cancelada",
        "inscricao_status_atualizado_por_empresa" => "Status de inscrição atualizado",
        "oportunidade_criada" => "Oportunidade criada",
        "oportunidade_atualizada" => "Oportunidade atualizada",
        "oportunidade_status_alterado" => "Status de oportunidade alterado",
        "oportunidade_excluida" => "Oportunidade excluída",
        "mensagem_contato_criptografada_enviada" => "Mensagem criptografada enviada",
        "dado_sensivel_criptografado_salvo" => "Dado sensível criptografado",
        default => $evento,
    };
}

function ce_auditoria_data(?string $valor): string
{
    $valor = trim((string) $valor);

    if ($valor === "") {
        return "Não informado";
    }

    try {
        return (new DateTimeImmutable($valor))->format("d/m/Y H:i:s");
    } catch (Throwable) {
        return $valor;
    }
}
?>

<main class="page-main">
    <div class="container">
        <section class="page-heading">
            <span class="eyebrow">Administração</span>
            <h1>Logs e auditoria</h1>
            <p class="lead">
                Área restrita para consulta dos últimos eventos de segurança e operação registrados pela aplicação.
            </p>
        </section>

        <section class="panel">
            <div class="security-note">
                <strong>Somente leitura:</strong>
                esta tela exibe os eventos registrados em log pela aplicação. Campos sensíveis são redigidos pelo
                mecanismo de auditoria antes da gravação.
            </div>

            <div class="inline-actions">
                <a class="button" href="/admin/relatorio.php">Voltar ao relatório</a>
                <a class="button-secondary" href="/admin/mensagens_contato.php">Ver mensagens</a>
                <a class="button-outline" href="/dashboard.php">Dashboard</a>
            </div>
        </section>

        <?php if (empty($eventos)): ?>
            <div class="empty-state">
                Nenhum evento de auditoria encontrado.
            </div>
        <?php else: ?>
            <section class="table-card">
                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Data/hora</th>
                                <th>Evento</th>
                                <th>Usuário</th>
                                <th>IP</th>
                                <th>Contexto</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($eventos as $evento): ?>
                                <tr>
                                    <td class="nowrap">
                                        <?= e::html(ce_auditoria_data((string) ($evento["timestamp"] ?? ""))) ?>
                                    </td>
                                    <td>
                                        <strong>
                                            <?= e::html(ce_auditoria_evento_label((string) ($evento["event"] ?? ""))) ?>
                                        </strong>
                                        <br>
                                        <span class="muted">
                                            <?= e::html((string) ($evento["event"] ?? "")) ?>
                                        </span>
                                    </td>
                                    <td>
                                        <?= e::html((string) (($evento["user_id"] ?? "") !== "" ? $evento["user_id"] : "Não autenticado")) ?>
                                    </td>
                                    <td>
                                        <?= e::html((string) ($evento["ip"] ?? "")) ?>
                                    </td>
                                    <td>
                                        <code><?= e::html((string) ($evento["context"] ?? "")) ?></code>
                                        <br>
                                        <span class="muted">
                                            User-Agent:
                                            <?= e::html((string) ($evento["user_agent"] ?? "")) ?>
                                        </span>
                                    </td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </section>
        <?php endif; ?>

        <section class="panel">
            <span class="eyebrow">Evidência para a defesa</span>
            <p class="lead">
                Esta tela demonstra rastreabilidade de ações relevantes, como login, logout, acessos negados,
                inscrições, favoritos, mensagens criptografadas e alterações em oportunidades.
            </p>
        </section>
    </div>
</main>

<?php
require dirname(__DIR__) . "/layout/footer.php";
