-- Reduz os privilégios do usuário da aplicação após a criação automática
-- feita pela imagem oficial MariaDB.

REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'conectaeduca_app'@'%';

GRANT SELECT, INSERT, UPDATE, DELETE
ON `conectaeduca`.*
TO 'conectaeduca_app'@'%';
