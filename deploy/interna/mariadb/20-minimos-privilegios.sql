-- Reduz os privilégios do usuário da aplicação após a criação automática
-- feita pela imagem oficial MariaDB.
--
-- A origem foi validada operacionalmente em 07/09/2026: o MariaDB observou
-- conectaeduca_app vindo da EP125 (192.168.6.34). Em novos volumes, a conta
-- criada inicialmente com Host='%' é restringida ao IP da aplicação na DMZ.
-- Se a topologia/IP da EP125 mudar, esta allowlist deve ser revalidada antes
-- da recriação do banco.

RENAME USER 'conectaeduca_app'@'%'
TO 'conectaeduca_app'@'192.168.6.34';

REVOKE ALL PRIVILEGES, GRANT OPTION
FROM 'conectaeduca_app'@'192.168.6.34';

GRANT SELECT, INSERT, UPDATE, DELETE
ON `conectaeduca`.*
TO 'conectaeduca_app'@'192.168.6.34';
