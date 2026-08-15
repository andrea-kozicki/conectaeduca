<?php

declare(strict_types=1);

namespace ConectaEduca\Repository;

use PDO;
use RuntimeException;
use Throwable;

final class RateLimitRepository implements RateLimitStore
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function consume(
        string $acao,
        string $identificadorHash,
        int $limite,
        int $janelaSegundos
    ): bool {
        $this->pdo->beginTransaction();

        try {
            /*
             * Garante a existência do bucket.
             *
             * A UNIQUE KEY (acao, identificador_hash)
             * impede duplicidade inclusive sob concorrência.
             */
            $stmt = $this->pdo->prepare(
                'INSERT INTO rate_limits
                    (
                        acao,
                        identificador_hash,
                        janela_inicio,
                        tentativas
                    )
                 VALUES
                    (
                        :acao,
                        :identificador_hash,
                        NOW(),
                        0
                    )
                 ON DUPLICATE KEY UPDATE
                    id = id'
            );

            $stmt->execute([
                ':acao' => $acao,
                ':identificador_hash' => $identificadorHash,
            ]);

            /*
             * O lock garante que duas requisições simultâneas
             * não incrementem o mesmo bucket incorretamente.
             */
            $stmt = $this->pdo->prepare(
                'SELECT
                    id,
                    tentativas,
                    UNIX_TIMESTAMP(janela_inicio)
                        AS janela_inicio_ts,
                    UNIX_TIMESTAMP(bloqueado_ate)
                        AS bloqueado_ate_ts,
                    UNIX_TIMESTAMP(NOW())
                        AS agora_ts
                 FROM rate_limits
                 WHERE acao = :acao
                   AND identificador_hash = :identificador_hash
                 LIMIT 1
                 FOR UPDATE'
            );

            $stmt->execute([
                ':acao' => $acao,
                ':identificador_hash' => $identificadorHash,
            ]);

            $bucket = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!is_array($bucket)) {
                throw new RuntimeException(
                    'Bucket de rate limit não encontrado.'
                );
            }

            $id = (int) $bucket['id'];
            $tentativas = (int) $bucket['tentativas'];
            $inicio = (int) $bucket['janela_inicio_ts'];
            $agora = (int) $bucket['agora_ts'];

            $bloqueadoAte = $bucket['bloqueado_ate_ts'] !== null
                ? (int) $bucket['bloqueado_ate_ts']
                : null;

            /*
             * Bloqueio ainda vigente.
             */
            if (
                $bloqueadoAte !== null
                && $bloqueadoAte > $agora
            ) {
                $this->pdo->commit();

                return false;
            }

            /*
             * A janela anterior expirou.
             * Esta requisição passa a ser a primeira da nova janela.
             */
            if (($agora - $inicio) >= $janelaSegundos) {
                $stmt = $this->pdo->prepare(
                    'UPDATE rate_limits
                     SET
                        janela_inicio = NOW(),
                        tentativas = 1,
                        bloqueado_ate = NULL
                     WHERE id = :id'
                );

                $stmt->execute([
                    ':id' => $id,
                ]);

                $this->pdo->commit();

                return true;
            }

            /*
             * O limite já foi consumido.
             * Bloqueia até o fim da janela corrente.
             */
            if ($tentativas >= $limite) {
                $fimJanela = $inicio + $janelaSegundos;

                $stmt = $this->pdo->prepare(
                    'UPDATE rate_limits
                     SET bloqueado_ate = FROM_UNIXTIME(:bloqueado_ate)
                     WHERE id = :id'
                );

                $stmt->execute([
                    ':bloqueado_ate' => $fimJanela,
                    ':id' => $id,
                ]);

                $this->pdo->commit();

                return false;
            }

            /*
             * Requisição permitida.
             */
            $stmt = $this->pdo->prepare(
                'UPDATE rate_limits
                 SET
                    tentativas = tentativas + 1,
                    bloqueado_ate = NULL
                 WHERE id = :id'
            );

            $stmt->execute([
                ':id' => $id,
            ]);

            $this->pdo->commit();

            return true;

        } catch (Throwable $e) {
            if ($this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }

            throw $e;
        }
    }

    public function reset(
        string $acao,
        string $identificadorHash
    ): void {
        $stmt = $this->pdo->prepare(
            'DELETE FROM rate_limits
             WHERE acao = :acao
               AND identificador_hash = :identificador_hash'
        );

        $stmt->execute([
            ':acao' => $acao,
            ':identificador_hash' => $identificadorHash,
        ]);
    }
}
