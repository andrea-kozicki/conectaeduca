-- Migração 005 - Rate limiting persistente
--
-- Substitui a limitação baseada exclusivamente em sessão por
-- buckets persistidos no MariaDB.
--
-- O identificador usado para o bucket não é armazenado em texto
-- claro. A aplicação persiste somente seu hash SHA-256.

CREATE TABLE rate_limits (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    acao VARCHAR(80) NOT NULL,
    identificador_hash CHAR(64) NOT NULL,

    janela_inicio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tentativas INT UNSIGNED NOT NULL DEFAULT 0,

    bloqueado_ate DATETIME NULL,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),

    UNIQUE KEY uq_rate_limits_acao_identificador
        (acao, identificador_hash),

    KEY idx_rate_limits_bloqueado_ate
        (bloqueado_ate),

    KEY idx_rate_limits_atualizado_em
        (atualizado_em),

    CONSTRAINT chk_rate_limits_identificador_hash
        CHECK (
            identificador_hash REGEXP '^[A-Fa-f0-9]{64}$'
        )
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;
