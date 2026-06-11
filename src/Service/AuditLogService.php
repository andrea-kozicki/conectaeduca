<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Config\Env;
use PDO;
use Throwable;

final class AuditLogService
{
    /**
     * @return array<int, array<string, string>>
     */
    public function ultimosEventos(int $limite = 80): array
    {
        $limite = max(1, min($limite, 200));
        $arquivo = Env::rootPath('storage/logs/audit.log');

        if (!is_file($arquivo) || !is_readable($arquivo)) {
            return [];
        }

        $linhas = file($arquivo, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

        if ($linhas === false) {
            return [];
        }

        $linhas = array_slice($linhas, -$limite);
        $eventos = [];
        $userIds = [];

        foreach (array_reverse($linhas) as $linha) {
            $registro = json_decode($linha, true);

            if (!is_array($registro)) {
                continue;
            }

            $userId = '';

            if (array_key_exists('user_id', $registro) && $registro['user_id'] !== null) {
                $userId = (string) $registro['user_id'];
            }

            if ($userId !== '' && ctype_digit($userId)) {
                $userIds[] = (int) $userId;
            }

            $eventos[] = [
                'timestamp' => (string) ($registro['timestamp'] ?? ''),
                'event' => (string) ($registro['event'] ?? ''),
                'ip' => (string) ($registro['ip'] ?? ''),
                'user_agent' => $this->limitarTexto((string) ($registro['user_agent'] ?? ''), 140),
                'user_id' => $userId,
                'user_nome' => '',
                'user_email' => '',
                'context' => $this->contextoParaTexto($registro['context'] ?? []),
            ];
        }

        $usuarios = $this->carregarUsuariosPorId($userIds);

        foreach ($eventos as $indice => $evento) {
            $id = $evento['user_id'];

            if ($id !== '' && ctype_digit($id)) {
                $idInt = (int) $id;

                if (isset($usuarios[$idInt])) {
                    $eventos[$indice]['user_nome'] = $usuarios[$idInt]['nome'];
                    $eventos[$indice]['user_email'] = $usuarios[$idInt]['email'];
                }
            }
        }

        return $eventos;
    }

    /**
     * @param array<int, int> $ids
     * @return array<int, array{nome: string, email: string}>
     */
    private function carregarUsuariosPorId(array $ids): array
    {
        $idsUnicos = [];

        foreach ($ids as $id) {
            $id = (int) $id;

            if ($id > 0) {
                $idsUnicos[$id] = $id;
            }
        }

        $ids = array_values($idsUnicos);

        if ($ids === []) {
            return [];
        }

        try {
            $placeholders = implode(',', array_fill(0, count($ids), '?'));

            $pdo = Database::connect();
            $stmt = $pdo->prepare(
                'SELECT id, nome, email FROM usuarios WHERE id IN (' . $placeholders . ')'
            );

            foreach ($ids as $index => $id) {
                $stmt->bindValue($index + 1, $id, PDO::PARAM_INT);
            }

            $stmt->execute();

            $usuarios = [];

            while ($linha = $stmt->fetch(PDO::FETCH_ASSOC)) {
                $usuarios[(int) $linha['id']] = [
                    'nome' => (string) ($linha['nome'] ?? ''),
                    'email' => (string) ($linha['email'] ?? ''),
                ];
            }

            return $usuarios;
        } catch (Throwable) {
            return [];
        }
    }

    private function contextoParaTexto(mixed $contexto): string
    {
        if ($contexto === [] || $contexto === null || $contexto === '') {
            return 'Sem contexto adicional.';
        }

        $json = json_encode(
            $contexto,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PARTIAL_OUTPUT_ON_ERROR
        );

        if ($json === false || $json === '[]') {
            return 'Sem contexto adicional.';
        }

        return $this->limitarTexto($json, 700);
    }

    private function limitarTexto(string $texto, int $limite): string
    {
        $texto = trim($texto);

        if (mb_strlen($texto) <= $limite) {
            return $texto;
        }

        return mb_substr($texto, 0, $limite - 3) . '...';
    }
}
