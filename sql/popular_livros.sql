INSERT INTO livros (id, titulo, descricao, preco, imagem, categoria_id, estoque)
VALUES
  (1, 'A Culpa é das Estrelas', 'Dois adolescentes que se conhecem em um grupo de apoio para jovens com câncer.', 47.99, 'Rom1.jpg', 1, 10),
  (2, 'Amor Sob Encomenda', 'Encontros inesperados e como o destino pode mudar nossas vidas no momento certo.', 45.90, 'Rom2.jpg', 1, 10),
  (3, 'Luzes do Norte', 'Uma história envolvente de aventura e mistério sob a aurora boreal.', 50.90, 'Rom3.jpg', 1, 10),
  (4, 'P.S. Eu te amo', 'Uma história de amor e perda, onde Holly encontra cartas deixadas por seu falecido marido.', 20.50, 'Rom4.jpg', 1, 10),
  (5, 'Orgulho e Preconceito', 'A relação entre Elizabeth Bennet e Sr. Darcy, com ironia e críticas à sociedade da época.', 47.97, 'Rom5.jpg', 1, 10),
  (6, 'A Cabeça de Steve Jobs', 'Um mergulho na mente brilhante de Steve Jobs, explorando sua abordagem visionária.', 89.90, 'Bio1.jpg', 4, 10),
  (7, 'A Loja de Tudo', 'A trajetória da Amazon e de Jeff Bezos, e como ela revolucionou o comércio eletrônico.', 40.30, 'Bio2.jpg', 4, 10),
  (8, 'Minha Breve História', 'A autobiografia de Stephen Hawking, onde ele compartilha sua trajetória desde a infância.', 44.50, 'Bio3.jpg', 4, 10),
  (9, 'Eu Sou Malala', 'A história de Malala Yousafzai, a paquistanesa que desafiou o Talibã em defesa da educação.', 46.99, 'Bio4.jpg', 4, 10),
  (10, 'Bilionários por Acaso', 'A criação do Facebook, as disputas e ambições por trás da maior rede social do mundo.', 25.00, 'Bio5.jpg', 4, 10),
  (11, 'A Redoma de Vidro', 'A luta de uma jovem brilhante contra a depressão e a sociedade opressiva dos anos 1950.', 42.90, 'Poesia1.jpeg', 3, 10),
  (12, 'A Morte de Ivan Ilitch', 'Explorando a morte e a reflexão sobre uma vida desperdiçada em futilidades.', 26.50, 'Poesia2.jpeg', 3, 10),
  (13, 'Crime e Castigo', 'A jornada psicológica de Raskólnikov após cometer um assassinato.', 62.00, 'Poesia3.jpg', 3, 10),
  (14, 'Nos Cumes do Desespero', 'Uma reflexão sobre o sofrimento, a existência e a angústia humana.', 99.90, 'Poesia4.jpeg', 3, 10),
  (15, 'Lira dos Vinte Anos', 'Poesias de Álvares de Azevedo, repleta de melancolia e paixão.', 47.36, 'Poesia5.jpg', 3, 10),
  (16, 'Tripulação de Esqueletos', 'Uma coletânea de contos de Stephen King, trazendo histórias macabras e perturbadoras.', 79.90, 'Contos1.jpg', 2, 10),
  (17, 'O Telefone Preto e Outras Histórias', 'Uma coletânea de Joe Hill, com narrativas aterrorizantes e sobrenaturais.', 45.90, 'Contos2.jpg', 2, 10),
  (18, 'Doze Reis e a Moça do Labirinto do Vento', 'Um livro de contos de Marina Colasanti, misturando fábulas e lirismo.', 47.60, 'Contos3.jpg', 2, 10),
  (19, 'Olhos D''Água', 'Aborda a vida de mulheres negras em meio a desafios sociais e emocionais.', 35.90, 'Contos4.jpeg', 2, 10),
  (20, 'Alerta de Risco', 'Contos de Neil Gaiman que transitam entre o terror, a fantasia e Sci-Fi.', 27.30, 'Contos5.jpg', 2, 10)
ON DUPLICATE KEY UPDATE
  titulo = VALUES(titulo),
  descricao = VALUES(descricao),
  preco = VALUES(preco),
  imagem = VALUES(imagem),
  categoria_id = VALUES(categoria_id),
  estoque = VALUES(estoque);