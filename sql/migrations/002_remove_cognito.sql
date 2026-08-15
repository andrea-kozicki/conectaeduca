-- Migração 002 - Remoção da integração legada com Amazon Cognito
--
-- A autenticação passou a ser realizada localmente pelo ConectaEduca.
-- Esta migration remove do modelo de usuários a identificação externa
-- anteriormente utilizada pela integração com Amazon Cognito.

ALTER TABLE usuarios
    DROP INDEX uq_usuarios_cognito_sub,
    DROP COLUMN cognito_sub;
