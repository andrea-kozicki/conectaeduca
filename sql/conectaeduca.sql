-- ConectaEduca - baseline estrutural consolidado
-- Gerado a partir do schema real validado da aplicação.
-- Somente estrutura: sem dados, contas de banco ou credenciais.
-- Importar somente em um banco NOVO/vazio já selecionado.
-- Charset/collation esperados: utf8mb4 / utf8mb4_unicode_ci.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;
CREATE TABLE `administradores` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `nome` varchar(150) NOT NULL,
  `email` varchar(190) NOT NULL,
  `senha_hash` varchar(255) NOT NULL,
  `mfa_ativo` tinyint(1) NOT NULL DEFAULT 1,
  `ativo` tinyint(1) NOT NULL DEFAULT 1,
  `ultimo_login_em` datetime DEFAULT NULL,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  `atualizado_em` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_administradores_email` (`email`),
  KEY `idx_admin_ativo` (`ativo`),
  KEY `idx_admin_mfa_ativo` (`mfa_ativo`),
  CONSTRAINT `chk_admin_nome` CHECK (char_length(trim(`nome`)) >= 3),
  CONSTRAINT `chk_admin_email` CHECK (`email` like '%@%._%'),
  CONSTRAINT `chk_admin_senha_hash` CHECK (char_length(`senha_hash`) >= 60)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `codigos_recuperacao_mfa` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `usuario_id` bigint(20) unsigned NOT NULL,
  `codigo_hash` varchar(255) NOT NULL,
  `usado_em` datetime DEFAULT NULL,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_mfa_recuperacao_usuario_uso` (`usuario_id`,`usado_em`),
  CONSTRAINT `fk_mfa_recuperacao_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `chk_mfa_recuperacao_hash` CHECK (char_length(`codigo_hash`) >= 60)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `dados_sensiveis_usuario` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `usuario_id` bigint(20) unsigned NOT NULL,
  `rotulo` varchar(120) NOT NULL DEFAULT 'anotacao_privada',
  `algoritmo` varchar(80) NOT NULL DEFAULT 'AES-256-GCM + RSA-OAEP',
  `encrypted_key` longtext NOT NULL,
  `iv` varchar(255) NOT NULL,
  `tag` varchar(255) NOT NULL,
  `ciphertext` longtext NOT NULL,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  `atualizado_em` datetime DEFAULT NULL ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_dados_sensiveis_usuario_rotulo` (`usuario_id`,`rotulo`),
  CONSTRAINT `fk_dados_sensiveis_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `empresas` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `usuario_id` bigint(20) unsigned DEFAULT NULL,
  `razao_social` varchar(180) NOT NULL,
  `nome_fantasia` varchar(180) DEFAULT NULL,
  `area_atuacao` varchar(120) DEFAULT NULL,
  `email` varchar(190) NOT NULL,
  `senha_hash` varchar(255) NOT NULL,
  `cnpj` char(14) NOT NULL,
  `telefone` varchar(20) DEFAULT NULL,
  `descricao` text DEFAULT NULL,
  `site_url` varchar(255) DEFAULT NULL,
  `conta_ativada` tinyint(1) NOT NULL DEFAULT 0,
  `token_ativacao_hash` char(64) DEFAULT NULL,
  `token_ativacao_expira_em` datetime DEFAULT NULL,
  `mfa_ativo` tinyint(1) NOT NULL DEFAULT 0,
  `ultimo_login_em` datetime DEFAULT NULL,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  `atualizado_em` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_empresas_email` (`email`),
  UNIQUE KEY `uq_empresas_cnpj` (`cnpj`),
  UNIQUE KEY `uq_empresas_usuario` (`usuario_id`),
  KEY `idx_empresas_conta_ativada` (`conta_ativada`),
  KEY `idx_empresas_mfa_ativo` (`mfa_ativo`),
  CONSTRAINT `fk_empresas_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `chk_empresas_razao_social` CHECK (char_length(trim(`razao_social`)) >= 3),
  CONSTRAINT `chk_empresas_email` CHECK (`email` like '%@%._%'),
  CONSTRAINT `chk_empresas_senha_hash` CHECK (char_length(`senha_hash`) >= 60),
  CONSTRAINT `chk_empresas_cnpj` CHECK (`cnpj` regexp '^[0-9]{14}$'),
  CONSTRAINT `chk_empresas_telefone` CHECK (`telefone` is null or char_length(trim(`telefone`)) >= 8),
  CONSTRAINT `chk_empresas_token_ativacao_hash` CHECK (`token_ativacao_hash` is null or `token_ativacao_hash` regexp '^[A-Fa-f0-9]{64}$'),
  CONSTRAINT `chk_empresas_token_ativacao_exp` CHECK (`token_ativacao_hash` is null or `token_ativacao_expira_em` is not null)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `favoritos` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `usuario_id` bigint(20) unsigned NOT NULL,
  `oportunidade_id` bigint(20) unsigned NOT NULL,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_favorito_usuario_oportunidade` (`usuario_id`,`oportunidade_id`),
  KEY `idx_favoritos_usuario` (`usuario_id`),
  KEY `idx_favoritos_oportunidade` (`oportunidade_id`),
  CONSTRAINT `fk_favoritos_oportunidade` FOREIGN KEY (`oportunidade_id`) REFERENCES `oportunidades` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_favoritos_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `inscricoes` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `usuario_id` bigint(20) unsigned NOT NULL,
  `oportunidade_id` bigint(20) unsigned NOT NULL,
  `status` enum('enviada','em_analise','aprovada','rejeitada','cancelada_pelo_usuario','encerrada') NOT NULL DEFAULT 'enviada',
  `observacoes_empresa` text DEFAULT NULL,
  `data_inscricao` datetime NOT NULL DEFAULT current_timestamp(),
  `atualizado_em` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_inscricao_usuario_oportunidade` (`usuario_id`,`oportunidade_id`),
  KEY `idx_inscricoes_usuario` (`usuario_id`),
  KEY `idx_inscricoes_oportunidade` (`oportunidade_id`),
  KEY `idx_inscricoes_status` (`status`),
  CONSTRAINT `fk_inscricoes_oportunidade` FOREIGN KEY (`oportunidade_id`) REFERENCES `oportunidades` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_inscricoes_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `logs_auditoria` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `tipo_conta` enum('visitante','usuario','empresa','administrador','sistema') NOT NULL DEFAULT 'sistema',
  `conta_id` bigint(20) unsigned DEFAULT NULL,
  `acao` varchar(100) NOT NULL,
  `recurso` varchar(100) NOT NULL,
  `descricao` text DEFAULT NULL,
  `ip_origem` varchar(45) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `sucesso` tinyint(1) NOT NULL DEFAULT 1,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_logs_tipo_conta` (`tipo_conta`,`conta_id`),
  KEY `idx_logs_acao` (`acao`),
  KEY `idx_logs_recurso` (`recurso`),
  KEY `idx_logs_sucesso` (`sucesso`),
  KEY `idx_logs_data` (`criado_em`),
  CONSTRAINT `chk_logs_acao` CHECK (char_length(trim(`acao`)) >= 2),
  CONSTRAINT `chk_logs_recurso` CHECK (char_length(trim(`recurso`)) >= 2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `mensagens_contato` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `usuario_id` bigint(20) unsigned NOT NULL,
  `assunto` varchar(160) NOT NULL,
  `categoria` varchar(40) NOT NULL DEFAULT 'outro',
  `status` varchar(40) NOT NULL DEFAULT 'recebida',
  `algoritmo` varchar(80) NOT NULL DEFAULT 'AES-256-GCM + RSA-OAEP',
  `encrypted_key` longtext NOT NULL,
  `iv` varchar(255) NOT NULL,
  `tag` varchar(255) NOT NULL,
  `ciphertext` longtext NOT NULL,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  `atualizado_em` datetime DEFAULT NULL ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_mensagens_contato_usuario` (`usuario_id`),
  KEY `idx_mensagens_contato_status` (`status`),
  KEY `idx_mensagens_contato_categoria` (`categoria`),
  CONSTRAINT `fk_mensagens_contato_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `oportunidades` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `empresa_id` bigint(20) unsigned NOT NULL,
  `titulo` varchar(180) NOT NULL,
  `descricao` text NOT NULL,
  `requisitos` text DEFAULT NULL,
  `area_conhecimento` varchar(120) DEFAULT NULL,
  `modalidade` enum('presencial','remoto','hibrido') NOT NULL DEFAULT 'presencial',
  `tipo_oportunidade` enum('estagio','emprego','trainee','bolsa','voluntariado','outro') NOT NULL DEFAULT 'estagio',
  `cidade` varchar(120) DEFAULT NULL,
  `estado` char(2) DEFAULT NULL,
  `status` enum('rascunho','publicada','encerrada','suspensa') NOT NULL DEFAULT 'rascunho',
  `data_publicacao` datetime DEFAULT NULL,
  `data_encerramento` datetime DEFAULT NULL,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  `atualizado_em` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_oportunidades_empresa` (`empresa_id`),
  KEY `idx_oportunidades_status` (`status`),
  KEY `idx_oportunidades_area` (`area_conhecimento`),
  KEY `idx_oportunidades_local` (`estado`,`cidade`),
  KEY `idx_oportunidades_tipo` (`tipo_oportunidade`),
  CONSTRAINT `fk_oportunidades_empresa` FOREIGN KEY (`empresa_id`) REFERENCES `empresas` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `chk_oportunidades_titulo` CHECK (char_length(trim(`titulo`)) >= 3),
  CONSTRAINT `chk_oportunidades_descricao` CHECK (char_length(trim(`descricao`)) >= 10),
  CONSTRAINT `chk_oportunidades_estado` CHECK (`estado` is null or `estado` regexp '^[A-Z]{2}$'),
  CONSTRAINT `chk_oportunidades_datas` CHECK (`data_encerramento` is null or `data_publicacao` is null or `data_encerramento` >= `data_publicacao`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `rate_limits` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `acao` varchar(80) NOT NULL,
  `identificador_hash` char(64) NOT NULL,
  `janela_inicio` datetime NOT NULL DEFAULT current_timestamp(),
  `tentativas` int(10) unsigned NOT NULL DEFAULT 0,
  `bloqueado_ate` datetime DEFAULT NULL,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  `atualizado_em` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_rate_limits_acao_identificador` (`acao`,`identificador_hash`),
  KEY `idx_rate_limits_bloqueado_ate` (`bloqueado_ate`),
  KEY `idx_rate_limits_atualizado_em` (`atualizado_em`),
  CONSTRAINT `chk_rate_limits_identificador_hash` CHECK (`identificador_hash` regexp '^[A-Fa-f0-9]{64}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `segredos_mfa` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `usuario_id` bigint(20) unsigned NOT NULL,
  `segredo_totp_envelope` text NOT NULL,
  `qr_confirmado` tinyint(1) NOT NULL DEFAULT 0,
  `ativo` tinyint(1) NOT NULL DEFAULT 0,
  `ultimo_passo_totp` bigint(20) unsigned DEFAULT NULL,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  `atualizado_em` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_segredos_mfa_usuario` (`usuario_id`),
  KEY `idx_mfa_ativo` (`ativo`),
  CONSTRAINT `fk_segredos_mfa_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `tokens_conta` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `usuario_id` bigint(20) unsigned NOT NULL,
  `tipo_token` enum('ativacao','recuperacao_senha','confirmacao_email') NOT NULL,
  `token_hash` char(64) NOT NULL,
  `expira_em` datetime NOT NULL,
  `usado_em` datetime DEFAULT NULL,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_tokens_token_hash` (`token_hash`),
  KEY `idx_tokens_tipo_token` (`tipo_token`),
  KEY `idx_tokens_expira` (`expira_em`),
  KEY `idx_tokens_usado_em` (`usado_em`),
  KEY `idx_tokens_usuario_tipo` (`usuario_id`,`tipo_token`,`usado_em`),
  CONSTRAINT `fk_tokens_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `chk_tokens_hash` CHECK (`token_hash` regexp '^[A-Fa-f0-9]{64}$'),
  CONSTRAINT `chk_tokens_expira` CHECK (`expira_em` > `criado_em`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `usuarios` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `nome` varchar(150) NOT NULL,
  `email` varchar(190) NOT NULL,
  `role` enum('usuario','empresa','admin') NOT NULL DEFAULT 'usuario',
  `senha_hash` varchar(255) NOT NULL,
  `cpf` char(11) DEFAULT NULL,
  `telefone` varchar(20) DEFAULT NULL,
  `data_nascimento` date DEFAULT NULL,
  `conta_ativada` tinyint(1) NOT NULL DEFAULT 0,
  `mfa_ativo` tinyint(1) NOT NULL DEFAULT 0,
  `ultimo_login_em` datetime DEFAULT NULL,
  `criado_em` datetime NOT NULL DEFAULT current_timestamp(),
  `atualizado_em` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_usuarios_email` (`email`),
  UNIQUE KEY `uq_usuarios_cpf` (`cpf`),
  KEY `idx_usuarios_conta_ativada` (`conta_ativada`),
  KEY `idx_usuarios_mfa_ativo` (`mfa_ativo`),
  CONSTRAINT `chk_usuarios_nome` CHECK (char_length(trim(`nome`)) >= 3),
  CONSTRAINT `chk_usuarios_email` CHECK (`email` like '%@%._%'),
  CONSTRAINT `chk_usuarios_senha_hash` CHECK (char_length(`senha_hash`) >= 60),
  CONSTRAINT `chk_usuarios_cpf` CHECK (`cpf` is null or `cpf` regexp '^[0-9]{11}$'),
  CONSTRAINT `chk_usuarios_telefone` CHECK (`telefone` is null or char_length(trim(`telefone`)) >= 8)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
