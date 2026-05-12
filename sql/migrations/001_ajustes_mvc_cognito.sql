-- =========================================================
-- Migração 001 - Ajustes para MVC, Cognito e compatibilidade
-- =========================================================

USE conectaeduca;

-- Usuários: suporte ao Cognito e perfil lógico
ALTER TABLE usuarios
    ADD COLUMN IF NOT EXISTS cognito_sub VARCHAR(80) NULL AFTER id,
    ADD COLUMN IF NOT EXISTS role ENUM('usuario', 'empresa', 'admin') NOT NULL DEFAULT 'usuario' AFTER email;

CREATE UNIQUE INDEX IF NOT EXISTS uq_usuarios_cognito_sub
    ON usuarios(cognito_sub);

-- Empresas: área de atuação usada pelo repository
ALTER TABLE empresas
    ADD COLUMN IF NOT EXISTS area_atuacao VARCHAR(120) NULL AFTER nome_fantasia;

-- Oportunidades: o código deve usar os nomes reais do SQL:
-- area_conhecimento em vez de area
-- status publicada em vez de ativa
-- Então aqui não alteramos a tabela de oportunidades.

-- Inscrições: o código deve usar data_inscricao em vez de criado_em.
-- Então aqui também não alteramos a tabela de inscrições.
