<?php
declare(strict_types=1);

namespace ConectaEduca\Repository;

use ConectaEduca\Security\CryptoHybrid;
use PDO;
use RuntimeException;

final class FaleConoscoRepository
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function criar(
        int $usuarioId,
        string $assunto,
        string $categoria,
        array $envelope
    ): int {
        $stmt = $this->pdo->prepare(
            'INSERT INTO mensagens_contato
                (usuario_id, assunto, categoria, status, algoritmo, encrypted_key, iv, tag, ciphertext, criado_em)
             VALUES
                (:usuario_id, :assunto, :categoria, :status, :algoritmo, :encrypted_key, :iv, :tag, :ciphertext, NOW())'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->bindValue(':assunto', $assunto);
        $stmt->bindValue(':categoria', $categoria);
        $algorithm = trim((string) ($envelope['algorithm'] ?? ''));

        if ($algorithm === '') {
            throw new RuntimeException(
                'Envelope criptográfico sem identificador de algoritmo.'
            );
        }

        $stmt->bindValue(':status', 'recebida');
        $stmt->bindValue(':algoritmo', $algorithm);
        $stmt->bindValue(':encrypted_key', $envelope['encrypted_key']);
        $stmt->bindValue(':iv', $envelope['iv']);
        $stmt->bindValue(':tag', $envelope['tag']);
        $stmt->bindValue(':ciphertext', $envelope['ciphertext']);
        $stmt->execute();

        return (int) $this->pdo->lastInsertId();
    }

    public function listarPorUsuario(int $usuarioId): array
    {
        $stmt = $this->pdo->prepare(
            'SELECT id,
                    usuario_id,
                    assunto,
                    categoria,
                    status,
                    algoritmo,
                    criado_em,
                    atualizado_em
             FROM mensagens_contato
             WHERE usuario_id = :usuario_id
             ORDER BY criado_em DESC, id DESC'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll();
    }

    public function listarTodasParaAdmin(): array
    {
        $stmt = $this->pdo->query(
            'SELECT m.id,
                    m.usuario_id,
                    u.nome AS usuario_nome,
                    u.email AS usuario_email,
                    m.assunto,
                    m.categoria,
                    m.status,
                    m.algoritmo,
                    m.encrypted_key,
                    m.iv,
                    m.tag,
                    m.ciphertext,
                    m.criado_em,
                    m.atualizado_em
             FROM mensagens_contato m
             INNER JOIN usuarios u ON u.id = m.usuario_id
             ORDER BY m.criado_em DESC, m.id DESC'
        );

        return $stmt->fetchAll();
    }
}