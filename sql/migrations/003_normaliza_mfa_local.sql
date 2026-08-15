-- Migração 003 - Normalização do MFA para autenticação local
--
-- O MFA passa a utilizar diretamente usuarios.id como identidade
-- autenticável, independentemente do papel RBAC do usuário.

ALTER TABLE segredos_mfa
    DROP INDEX uq_segredo_mfa,
    DROP INDEX idx_mfa_tipo_conta,
    CHANGE COLUMN conta_id usuario_id BIGINT UNSIGNED NOT NULL,
    DROP COLUMN tipo_conta,
    CHANGE COLUMN segredo_totp_cifrado segredo_totp_envelope TEXT NOT NULL,
    ADD CONSTRAINT uq_segredos_mfa_usuario UNIQUE (usuario_id),
    ADD CONSTRAINT fk_segredos_mfa_usuario
        FOREIGN KEY (usuario_id)
        REFERENCES usuarios(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE;
