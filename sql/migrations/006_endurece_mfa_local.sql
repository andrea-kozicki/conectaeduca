-- Migração 006 - Endurecimento do MFA local
--
-- O MFA é obrigatório para todas as identidades autenticáveis.
--
-- Novos segredos começam inativos e só são ativados depois
-- que o primeiro código TOTP é confirmado.
--
-- ultimo_passo_totp permite rejeitar reutilização de um
-- código TOTP já aceito anteriormente.

ALTER TABLE segredos_mfa
    MODIFY COLUMN ativo TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN ultimo_passo_totp BIGINT UNSIGNED NULL
        AFTER ativo;

CREATE TABLE codigos_recuperacao_mfa (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    usuario_id BIGINT UNSIGNED NOT NULL,
    codigo_hash VARCHAR(255) NOT NULL,
    usado_em DATETIME NULL,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),

    KEY idx_mfa_recuperacao_usuario_uso
        (usuario_id, usado_em),

    CONSTRAINT fk_mfa_recuperacao_usuario
        FOREIGN KEY (usuario_id)
        REFERENCES usuarios(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    CONSTRAINT chk_mfa_recuperacao_hash
        CHECK (CHAR_LENGTH(codigo_hash) >= 60)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;
