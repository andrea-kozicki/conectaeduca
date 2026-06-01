CREATE TABLE IF NOT EXISTS mensagens_contato (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    usuario_id BIGINT UNSIGNED NOT NULL,
    assunto VARCHAR(160) NOT NULL,
    categoria VARCHAR(40) NOT NULL DEFAULT 'outro',
    status VARCHAR(40) NOT NULL DEFAULT 'recebida',
    algoritmo VARCHAR(80) NOT NULL DEFAULT 'AES-256-GCM + RSA-OAEP',
    encrypted_key LONGTEXT NOT NULL,
    iv VARCHAR(255) NOT NULL,
    tag VARCHAR(255) NOT NULL,
    ciphertext LONGTEXT NOT NULL,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_mensagens_contato_usuario (usuario_id),
    KEY idx_mensagens_contato_status (status),
    KEY idx_mensagens_contato_categoria (categoria),
    CONSTRAINT fk_mensagens_contato_usuario
        FOREIGN KEY (usuario_id)
        REFERENCES usuarios(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
