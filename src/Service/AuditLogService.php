<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Env;

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

        foreach (array_reverse($linhas) as $linha) {
            $registro = json_decode($linha, true);

            if (!is_array($registro)) {
                continue;
            }

            $eventos[] = [
                'timestamp' => (string) ($registro['timestamp'] ?? ''),
                'event' => (string) ($registro['event'] ?? ''),
                'ip' => (string) ($registro['ip'] ?? ''),
                'user_agent' => $this->limitarTexto((string) ($registro['user_agent'] ?? ''), 140),
                'user_id' => isset($registro['user_id']) ? (string) $registro['user_id'] : '',
                'context' => $this->contextoParaTexto($registro['context'] ?? []),
            ];
        }

        return $eventos;
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
