-- =========================================================
-- ConectaEduca - Vincular empresas a usuários autenticados
-- =========================================================

ALTER TABLE empresas
ADD COLUMN usuario_id BIGINT UNSIGNED NULL AFTER id;

CREATE UNIQUE INDEX uq_empresas_usuario
ON empresas(usuario_id);

ALTER TABLE empresas
ADD CONSTRAINT fk_empresas_usuario
FOREIGN KEY (usuario_id)
REFERENCES usuarios(id)
ON DELETE SET NULL
ON UPDATE CASCADE;
