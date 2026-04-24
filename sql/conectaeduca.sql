-- =========================================================
-- ConectaEduca - esquema endurecido (hardening básico)
-- Compatível com MariaDB/MySQL modernos
-- =========================================================

CREATE DATABASE IF NOT EXISTS conectaeduca
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE conectaeduca;

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS logs_auditoria;
DROP TABLE IF EXISTS tokens_conta;
DROP TABLE IF EXISTS segredos_mfa;
DROP TABLE IF EXISTS favoritos;
DROP TABLE IF EXISTS inscricoes;
DROP TABLE IF EXISTS oportunidades;
DROP TABLE IF EXISTS administradores;
DROP TABLE IF EXISTS empresas;
DROP TABLE IF EXISTS usuarios;

SET FOREIGN_KEY_CHECKS = 1;

-- =========================================================
-- 1) USUÁRIOS
-- =========================================================
CREATE TABLE usuarios (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    email VARCHAR(190) NOT NULL,
    senha_hash VARCHAR(255) NOT NULL,

    cpf CHAR(11) NULL,
    telefone VARCHAR(20) NULL,
    data_nascimento DATE NULL,

    conta_ativada TINYINT(1) NOT NULL DEFAULT 0,
    token_ativacao_hash CHAR(64) NULL,
    token_ativacao_expira_em DATETIME NULL,

    mfa_ativo TINYINT(1) NOT NULL DEFAULT 0,
    ultimo_login_em DATETIME NULL,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uq_usuarios_email UNIQUE (email),
    CONSTRAINT uq_usuarios_cpf UNIQUE (cpf),

    CONSTRAINT chk_usuarios_nome
        CHECK (CHAR_LENGTH(TRIM(nome)) >= 3),

    CONSTRAINT chk_usuarios_email
        CHECK (email LIKE '%@%._%'),

    CONSTRAINT chk_usuarios_senha_hash
        CHECK (CHAR_LENGTH(senha_hash) >= 60),

    CONSTRAINT chk_usuarios_cpf
        CHECK (cpf IS NULL OR cpf REGEXP '^[0-9]{11}$'),

    CONSTRAINT chk_usuarios_telefone
        CHECK (telefone IS NULL OR CHAR_LENGTH(TRIM(telefone)) >= 8),

    CONSTRAINT chk_usuarios_token_ativacao_hash
        CHECK (token_ativacao_hash IS NULL OR token_ativacao_hash REGEXP '^[A-Fa-f0-9]{64}$'),

    CONSTRAINT chk_usuarios_token_ativacao_exp
        CHECK (
            token_ativacao_hash IS NULL
            OR token_ativacao_expira_em IS NOT NULL
        )
) ENGINE=InnoDB;

CREATE INDEX idx_usuarios_conta_ativada ON usuarios(conta_ativada);
CREATE INDEX idx_usuarios_mfa_ativo ON usuarios(mfa_ativo);

-- =========================================================
-- 2) EMPRESAS
-- =========================================================
CREATE TABLE empresas (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    razao_social VARCHAR(180) NOT NULL,
    nome_fantasia VARCHAR(180) NULL,
    email VARCHAR(190) NOT NULL,
    senha_hash VARCHAR(255) NOT NULL,

    cnpj CHAR(14) NOT NULL,
    telefone VARCHAR(20) NULL,
    descricao TEXT NULL,
    site_url VARCHAR(255) NULL,

    conta_ativada TINYINT(1) NOT NULL DEFAULT 0,
    token_ativacao_hash CHAR(64) NULL,
    token_ativacao_expira_em DATETIME NULL,

    mfa_ativo TINYINT(1) NOT NULL DEFAULT 0,
    ultimo_login_em DATETIME NULL,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uq_empresas_email UNIQUE (email),
    CONSTRAINT uq_empresas_cnpj UNIQUE (cnpj),

    CONSTRAINT chk_empresas_razao_social
        CHECK (CHAR_LENGTH(TRIM(razao_social)) >= 3),

    CONSTRAINT chk_empresas_email
        CHECK (email LIKE '%@%._%'),

    CONSTRAINT chk_empresas_senha_hash
        CHECK (CHAR_LENGTH(senha_hash) >= 60),

    CONSTRAINT chk_empresas_cnpj
        CHECK (cnpj REGEXP '^[0-9]{14}$'),

    CONSTRAINT chk_empresas_telefone
        CHECK (telefone IS NULL OR CHAR_LENGTH(TRIM(telefone)) >= 8),

    CONSTRAINT chk_empresas_token_ativacao_hash
        CHECK (token_ativacao_hash IS NULL OR token_ativacao_hash REGEXP '^[A-Fa-f0-9]{64}$'),

    CONSTRAINT chk_empresas_token_ativacao_exp
        CHECK (
            token_ativacao_hash IS NULL
            OR token_ativacao_expira_em IS NOT NULL
        )
) ENGINE=InnoDB;

CREATE INDEX idx_empresas_conta_ativada ON empresas(conta_ativada);
CREATE INDEX idx_empresas_mfa_ativo ON empresas(mfa_ativo);

-- =========================================================
-- 3) ADMINISTRADORES
-- =========================================================
CREATE TABLE administradores (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    email VARCHAR(190) NOT NULL,
    senha_hash VARCHAR(255) NOT NULL,

    mfa_ativo TINYINT(1) NOT NULL DEFAULT 1,
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    ultimo_login_em DATETIME NULL,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uq_administradores_email UNIQUE (email),

    CONSTRAINT chk_admin_nome
        CHECK (CHAR_LENGTH(TRIM(nome)) >= 3),

    CONSTRAINT chk_admin_email
        CHECK (email LIKE '%@%._%'),

    CONSTRAINT chk_admin_senha_hash
        CHECK (CHAR_LENGTH(senha_hash) >= 60)
) ENGINE=InnoDB;

CREATE INDEX idx_admin_ativo ON administradores(ativo);
CREATE INDEX idx_admin_mfa_ativo ON administradores(mfa_ativo);

-- =========================================================
-- 4) OPORTUNIDADES
-- =========================================================
CREATE TABLE oportunidades (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    empresa_id BIGINT UNSIGNED NOT NULL,

    titulo VARCHAR(180) NOT NULL,
    descricao TEXT NOT NULL,
    requisitos TEXT NULL,

    area_conhecimento VARCHAR(120) NULL,
    modalidade ENUM('presencial', 'remoto', 'hibrido') NOT NULL DEFAULT 'presencial',
    tipo_oportunidade ENUM('estagio', 'emprego', 'trainee', 'bolsa', 'voluntariado', 'outro') NOT NULL DEFAULT 'estagio',

    cidade VARCHAR(120) NULL,
    estado CHAR(2) NULL,

    status ENUM('rascunho', 'publicada', 'encerrada', 'suspensa') NOT NULL DEFAULT 'rascunho',
    data_publicacao DATETIME NULL,
    data_encerramento DATETIME NULL,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_oportunidades_empresa
        FOREIGN KEY (empresa_id) REFERENCES empresas(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    CONSTRAINT chk_oportunidades_titulo
        CHECK (CHAR_LENGTH(TRIM(titulo)) >= 3),

    CONSTRAINT chk_oportunidades_descricao
        CHECK (CHAR_LENGTH(TRIM(descricao)) >= 10),

    CONSTRAINT chk_oportunidades_estado
        CHECK (estado IS NULL OR estado REGEXP '^[A-Z]{2}$'),

    CONSTRAINT chk_oportunidades_datas
        CHECK (
            data_encerramento IS NULL
            OR data_publicacao IS NULL
            OR data_encerramento >= data_publicacao
        )
) ENGINE=InnoDB;

CREATE INDEX idx_oportunidades_empresa ON oportunidades(empresa_id);
CREATE INDEX idx_oportunidades_status ON oportunidades(status);
CREATE INDEX idx_oportunidades_area ON oportunidades(area_conhecimento);
CREATE INDEX idx_oportunidades_local ON oportunidades(estado, cidade);
CREATE INDEX idx_oportunidades_tipo ON oportunidades(tipo_oportunidade);

-- =========================================================
-- 5) INSCRIÇÕES
-- =========================================================
CREATE TABLE inscricoes (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    usuario_id BIGINT UNSIGNED NOT NULL,
    oportunidade_id BIGINT UNSIGNED NOT NULL,

    status ENUM(
        'enviada',
        'em_analise',
        'aprovada',
        'rejeitada',
        'cancelada_pelo_usuario',
        'encerrada'
    ) NOT NULL DEFAULT 'enviada',

    observacoes_empresa TEXT NULL,
    data_inscricao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uq_inscricao_usuario_oportunidade UNIQUE (usuario_id, oportunidade_id),

    CONSTRAINT fk_inscricoes_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    CONSTRAINT fk_inscricoes_oportunidade
        FOREIGN KEY (oportunidade_id) REFERENCES oportunidades(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_inscricoes_usuario ON inscricoes(usuario_id);
CREATE INDEX idx_inscricoes_oportunidade ON inscricoes(oportunidade_id);
CREATE INDEX idx_inscricoes_status ON inscricoes(status);

-- =========================================================
-- 6) FAVORITOS
-- =========================================================
CREATE TABLE favoritos (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    usuario_id BIGINT UNSIGNED NOT NULL,
    oportunidade_id BIGINT UNSIGNED NOT NULL,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_favorito_usuario_oportunidade UNIQUE (usuario_id, oportunidade_id),

    CONSTRAINT fk_favoritos_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    CONSTRAINT fk_favoritos_oportunidade
        FOREIGN KEY (oportunidade_id) REFERENCES oportunidades(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_favoritos_usuario ON favoritos(usuario_id);
CREATE INDEX idx_favoritos_oportunidade ON favoritos(oportunidade_id);

-- =========================================================
-- 7) SEGREDOS MFA / TOTP
-- Observação:
-- Aqui o ideal é guardar valor cifrado pela aplicação.
-- Por isso o nome do campo já sugere armazenamento cifrado.
-- =========================================================
CREATE TABLE segredos_mfa (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    tipo_conta ENUM('usuario', 'empresa', 'administrador') NOT NULL,
    conta_id BIGINT UNSIGNED NOT NULL,

    segredo_totp_cifrado VARBINARY(255) NOT NULL,
    qr_confirmado TINYINT(1) NOT NULL DEFAULT 0,
    ativo TINYINT(1) NOT NULL DEFAULT 1,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT uq_segredo_mfa UNIQUE (tipo_conta, conta_id)
) ENGINE=InnoDB;

CREATE INDEX idx_mfa_tipo_conta ON segredos_mfa(tipo_conta, conta_id);
CREATE INDEX idx_mfa_ativo ON segredos_mfa(ativo);

-- =========================================================
-- 8) TOKENS DE CONTA
-- Armazenar apenas HASH do token
-- Ex.: SHA-256 em hexadecimal => CHAR(64)
-- =========================================================
CREATE TABLE tokens_conta (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    tipo_conta ENUM('usuario', 'empresa', 'administrador') NOT NULL,
    conta_id BIGINT UNSIGNED NOT NULL,

    tipo_token ENUM('ativacao', 'recuperacao_senha', 'sessao_temporaria', 'confirmacao_email') NOT NULL,
    token_hash CHAR(64) NOT NULL,

    expira_em DATETIME NOT NULL,
    usado_em DATETIME NULL,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_tokens_hash
        CHECK (token_hash REGEXP '^[A-Fa-f0-9]{64}$'),

    CONSTRAINT chk_tokens_expira
        CHECK (expira_em > criado_em)
) ENGINE=InnoDB;

CREATE INDEX idx_tokens_tipo_conta ON tokens_conta(tipo_conta, conta_id);
CREATE INDEX idx_tokens_tipo_token ON tokens_conta(tipo_token);
CREATE INDEX idx_tokens_expira ON tokens_conta(expira_em);
CREATE INDEX idx_tokens_usado_em ON tokens_conta(usado_em);

-- =========================================================
-- 9) LOGS / AUDITORIA
-- =========================================================
CREATE TABLE logs_auditoria (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    tipo_conta ENUM('visitante', 'usuario', 'empresa', 'administrador', 'sistema') NOT NULL DEFAULT 'sistema',
    conta_id BIGINT UNSIGNED NULL,

    acao VARCHAR(100) NOT NULL,
    recurso VARCHAR(100) NOT NULL,
    descricao TEXT NULL,

    ip_origem VARCHAR(45) NULL,
    user_agent VARCHAR(255) NULL,
    sucesso TINYINT(1) NOT NULL DEFAULT 1,

    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_logs_acao
        CHECK (CHAR_LENGTH(TRIM(acao)) >= 2),

    CONSTRAINT chk_logs_recurso
        CHECK (CHAR_LENGTH(TRIM(recurso)) >= 2)
) ENGINE=InnoDB;

CREATE INDEX idx_logs_tipo_conta ON logs_auditoria(tipo_conta, conta_id);
CREATE INDEX idx_logs_acao ON logs_auditoria(acao);
CREATE INDEX idx_logs_recurso ON logs_auditoria(recurso);
CREATE INDEX idx_logs_sucesso ON logs_auditoria(sucesso);
CREATE INDEX idx_logs_data ON logs_auditoria(criado_em);

-- =========================================================
-- 10) USUÁRIO DO BANCO COM PRIVILÉGIO MÍNIMO
-- Execute este bloco como administrador do MariaDB/MySQL.
-- Ajuste a senha antes de rodar em ambiente real.
-- =========================================================
CREATE USER IF NOT EXISTS 'conectaeduca_app'@'localhost'
IDENTIFIED BY 'Troque_Essa_Senha_Forte_123!';

GRANT SELECT, INSERT, UPDATE, DELETE
ON conectaeduca.* TO 'conectaeduca_app'@'localhost';

FLUSH PRIVILEGES;