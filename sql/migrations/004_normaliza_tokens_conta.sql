-- Migração 004 - Normalização dos tokens de conta
--
-- A autenticação local utiliza usuarios.id como identidade central
-- para usuário, empresa e administrador.
--
-- Os tokens deixam de utilizar o modelo legado tipo_conta + conta_id.
-- O token utilizável nunca é armazenado no banco: somente seu hash
-- SHA-256 é persistido.

ALTER TABLE tokens_conta
    DROP INDEX idx_tokens_tipo_conta,
    CHANGE COLUMN conta_id usuario_id BIGINT UNSIGNED NOT NULL,
    DROP COLUMN tipo_conta,
    MODIFY COLUMN tipo_token
        ENUM(
            'ativacao',
            'recuperacao_senha',
            'confirmacao_email'
        ) NOT NULL,
    ADD UNIQUE KEY uq_tokens_token_hash (token_hash),
    ADD KEY idx_tokens_usuario_tipo
        (usuario_id, tipo_token, usado_em),
    ADD CONSTRAINT fk_tokens_usuario
        FOREIGN KEY (usuario_id)
        REFERENCES usuarios(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE;

-- Os tokens de ativação passam a residir exclusivamente em
-- tokens_conta, evitando duas fontes distintas de verdade.

ALTER TABLE usuarios
    DROP CONSTRAINT chk_usuarios_token_ativacao_hash,
    DROP CONSTRAINT chk_usuarios_token_ativacao_exp,
    DROP COLUMN token_ativacao_hash,
    DROP COLUMN token_ativacao_expira_em;
