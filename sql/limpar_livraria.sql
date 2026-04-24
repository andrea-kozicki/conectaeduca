USE livraria;

DELIMITER $$

DROP PROCEDURE IF EXISTS limpar_tabelas $$
CREATE PROCEDURE limpar_tabelas()
BEGIN
  DECLARE done INT DEFAULT FALSE;
  DECLARE tabela VARCHAR(255);
  DECLARE cur CURSOR FOR
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'livraria'
      AND table_name NOT IN ('livros');
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  SET FOREIGN_KEY_CHECKS = 0;

  OPEN cur;
  read_loop: LOOP
    FETCH cur INTO tabela;
    IF done THEN
      LEAVE read_loop;
    END IF;

    SET @sql = CONCAT('TRUNCATE TABLE `', tabela, '`');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END LOOP;
  CLOSE cur;

  SET FOREIGN_KEY_CHECKS = 1;
END $$

DELIMITER ;

-- Executa e remove a procedure temporária
CALL limpar_tabelas();
DROP PROCEDURE limpar_tabelas;
