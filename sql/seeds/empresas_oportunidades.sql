-- =========================================================
-- ConectaEduca - dados fictícios de demonstração
-- Empresas + oportunidades
-- Seguro para rodar mais de uma vez: atualiza empresas e recria oportunidades demo
-- =========================================================

START TRANSACTION;

SET @senha_demo = '$2y$12$YFwdhC3wScapmvuffY43JOTVx93CzkchxqrWE2EAZEk3XArTiMgBy';

-- =========================================================
-- 1) EMPRESAS FICTÍCIAS
-- Senha demo: Senha@123456
-- =========================================================

INSERT INTO empresas (
    razao_social,
    nome_fantasia,
    area_atuacao,
    email,
    senha_hash,
    cnpj,
    telefone,
    descricao,
    site_url,
    conta_ativada,
    mfa_ativo
) VALUES
(
    'Tech Para Todos Soluções Educacionais Ltda',
    'Tech Para Todos',
    'Tecnologia educacional',
    'contato@techparatodos.example',
    @senha_demo,
    '11222333000101',
    '41999990001',
    'Empresa fictícia voltada à criação de soluções educacionais inclusivas, plataformas web e formação em tecnologia.',
    'https://techparatodos.example',
    1,
    1
),
(
    'Instituto Futuro Digital',
    'Futuro Digital',
    'Formação profissional',
    'contato@futurodigital.example',
    @senha_demo,
    '11222333000102',
    '41999990002',
    'Instituto fictício de capacitação em tecnologia, segurança da informação, suporte técnico e cidadania digital.',
    'https://futurodigital.example',
    1,
    1
),
(
    'Dados e Inclusão Serviços de Tecnologia Ltda',
    'Dados & Inclusão',
    'Dados e inclusão digital',
    'contato@dadoseinclusao.example',
    @senha_demo,
    '11222333000103',
    '41999990003',
    'Organização fictícia que desenvolve projetos de análise de dados, impacto social e inclusão produtiva.',
    'https://dadoseinclusao.example',
    1,
    1
),
(
    'Escola Conecta Jovem',
    'Conecta Jovem',
    'Educação e voluntariado',
    'contato@conectajovem.example',
    @senha_demo,
    '11222333000104',
    '41999990004',
    'Escola fictícia dedicada a projetos sociais, reforço escolar, oficinas de informática e mentoria para jovens.',
    'https://conectajovem.example',
    1,
    1
),
(
    'Nuvem Social Tecnologia Ltda',
    'Nuvem Social',
    'Cloud computing e infraestrutura',
    'contato@nuvemsocial.example',
    @senha_demo,
    '11222333000105',
    '41999990005',
    'Empresa fictícia especializada em infraestrutura, Linux, cloud computing e automação para projetos sociais.',
    'https://nuvemsocial.example',
    1,
    1
),
(
    'Paraná Tech Lab Ltda',
    'Paraná Tech Lab',
    'Pesquisa aplicada e inovação',
    'contato@paratechlab.example',
    @senha_demo,
    '11222333000106',
    '41999990006',
    'Laboratório fictício de inovação com foco em acessibilidade digital, UX, segurança web e prototipação.',
    'https://paratechlab.example',
    1,
    1
)
ON DUPLICATE KEY UPDATE
    razao_social = VALUES(razao_social),
    nome_fantasia = VALUES(nome_fantasia),
    area_atuacao = VALUES(area_atuacao),
    telefone = VALUES(telefone),
    descricao = VALUES(descricao),
    site_url = VALUES(site_url),
    conta_ativada = VALUES(conta_ativada),
    mfa_ativo = VALUES(mfa_ativo),
    atualizado_em = CURRENT_TIMESTAMP;

-- =========================================================
-- 2) REMOVE OPORTUNIDADES DEMO ANTIGAS
-- Evita duplicar se você rodar o seed mais de uma vez.
-- =========================================================

DELETE o
FROM oportunidades o
JOIN empresas e ON e.id = o.empresa_id
WHERE e.email IN (
    'contato@techparatodos.example',
    'contato@futurodigital.example',
    'contato@dadoseinclusao.example',
    'contato@conectajovem.example',
    'contato@nuvemsocial.example',
    'contato@paratechlab.example'
)
AND o.titulo IN (
    'Estágio em Desenvolvimento Web',
    'Programa Jovem DevSecOps',
    'Analista Júnior de Segurança da Informação',
    'Estágio em Suporte Técnico',
    'Bolsa de Introdução à Cibersegurança',
    'Turma Piloto de Segurança Web',
    'Estágio em Banco de Dados',
    'Trainee em Análise de Dados',
    'Voluntariado em Inclusão Digital',
    'Monitoria de Informática Básica',
    'Estágio em Cloud Computing',
    'Bolsa de Estudos em Linux e Servidores',
    'Estágio em UX para Plataformas Educacionais',
    'Projeto de Acessibilidade Digital'
);

-- =========================================================
-- 3) OPORTUNIDADES FICTÍCIAS
-- =========================================================

INSERT INTO oportunidades (
    empresa_id,
    titulo,
    descricao,
    requisitos,
    area_conhecimento,
    modalidade,
    tipo_oportunidade,
    cidade,
    estado,
    status,
    data_publicacao,
    data_encerramento
) VALUES
(
    (SELECT id FROM empresas WHERE email = 'contato@techparatodos.example'),
    'Estágio em Desenvolvimento Web',
    'Atuação em projeto educacional com PHP, HTML, CSS, JavaScript, banco de dados e boas práticas de segurança web.',
    'Conhecimentos básicos em lógica de programação, HTML, CSS, PHP e Git. Interesse em desenvolvimento seguro será diferencial.',
    'Desenvolvimento Web',
    'hibrido',
    'estagio',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 15 DAY,
    NOW() + INTERVAL 45 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@techparatodos.example'),
    'Programa Jovem DevSecOps',
    'Programa introdutório para estudantes interessados em integração contínua, testes automatizados, hardening e segurança no ciclo de desenvolvimento.',
    'Noções de Linux, Git, terminal e fundamentos de redes. Não é exigida experiência profissional anterior.',
    'DevSecOps',
    'remoto',
    'bolsa',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 10 DAY,
    NOW() + INTERVAL 60 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@techparatodos.example'),
    'Analista Júnior de Segurança da Informação',
    'Vaga fictícia para análise de alertas, revisão de logs, apoio em políticas de segurança e acompanhamento de vulnerabilidades.',
    'Conhecimentos em redes, Linux, OWASP Top 10, logs e boas práticas de segurança. Perfil investigativo e organizado.',
    'Segurança da Informação',
    'remoto',
    'emprego',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 8 DAY,
    NOW() + INTERVAL 35 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@futurodigital.example'),
    'Estágio em Suporte Técnico',
    'Atendimento a usuários, instalação de softwares, documentação de chamados, apoio em manutenção de computadores e redes locais.',
    'Conhecimentos básicos de Windows, Linux, Office, redes e atendimento ao usuário.',
    'Suporte Técnico',
    'presencial',
    'estagio',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 20 DAY,
    NOW() + INTERVAL 25 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@futurodigital.example'),
    'Bolsa de Introdução à Cibersegurança',
    'Bolsa de estudos com trilha introdutória em segurança da informação, senhas, autenticação multifator, phishing e proteção de dados.',
    'Interesse em tecnologia, disponibilidade para aulas online e vontade de aprender fundamentos de segurança.',
    'Cibersegurança',
    'remoto',
    'bolsa',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 5 DAY,
    NOW() + INTERVAL 50 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@futurodigital.example'),
    'Turma Piloto de Segurança Web',
    'Oportunidade encerrada usada para demonstrar histórico de vagas e relatórios administrativos.',
    'Conhecimentos básicos em aplicações web, HTTP e lógica de programação.',
    'Segurança Web',
    'remoto',
    'bolsa',
    'Curitiba',
    'PR',
    'encerrada',
    NOW() - INTERVAL 90 DAY,
    NOW() - INTERVAL 15 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@dadoseinclusao.example'),
    'Estágio em Banco de Dados',
    'Apoio na modelagem, consultas SQL, documentação de dados e organização de informações de projetos educacionais.',
    'Conhecimentos básicos em SQL, modelagem relacional e planilhas. Interesse em qualidade de dados será diferencial.',
    'Banco de Dados',
    'hibrido',
    'estagio',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 18 DAY,
    NOW() + INTERVAL 40 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@dadoseinclusao.example'),
    'Trainee em Análise de Dados',
    'Programa fictício para formação em análise de dados, dashboards, indicadores educacionais e visualização de informações.',
    'Noções de estatística, SQL, Excel ou ferramentas de visualização. Perfil analítico e atenção a detalhes.',
    'Análise de Dados',
    'remoto',
    'trainee',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 12 DAY,
    NOW() + INTERVAL 55 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@conectajovem.example'),
    'Voluntariado em Inclusão Digital',
    'Atuação voluntária em oficinas de informática básica, segurança digital e uso consciente da internet.',
    'Boa comunicação, paciência para ensinar e conhecimentos básicos de informática.',
    'Inclusão Digital',
    'presencial',
    'voluntariado',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 7 DAY,
    NOW() + INTERVAL 70 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@conectajovem.example'),
    'Monitoria de Informática Básica',
    'Monitoria para apoiar estudantes em atividades de digitação, navegação segura, e-mail, armazenamento em nuvem e ferramentas de escritório.',
    'Conhecimentos em informática básica, pacote office ou LibreOffice e boas práticas de segurança.',
    'Informática Básica',
    'presencial',
    'voluntariado',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 4 DAY,
    NOW() + INTERVAL 30 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@nuvemsocial.example'),
    'Estágio em Cloud Computing',
    'Apoio em laboratório de infraestrutura, servidores Linux, automação, containers e documentação de ambientes em nuvem.',
    'Noções de Linux, terminal, redes, Git e interesse em cloud computing.',
    'Infraestrutura e Cloud',
    'hibrido',
    'estagio',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 6 DAY,
    NOW() + INTERVAL 45 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@nuvemsocial.example'),
    'Bolsa de Estudos em Linux e Servidores',
    'Trilha prática de administração Linux, permissões, serviços, logs, hardening básico e documentação técnica.',
    'Interesse em infraestrutura, disponibilidade para estudo prático e familiaridade básica com terminal.',
    'Linux e Servidores',
    'remoto',
    'bolsa',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 2 DAY,
    NOW() + INTERVAL 65 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@paratechlab.example'),
    'Estágio em UX para Plataformas Educacionais',
    'Apoio em prototipação, testes de usabilidade, acessibilidade e melhoria de telas para plataforma educacional.',
    'Conhecimentos básicos de design, acessibilidade, escrita clara e interesse em experiência do usuário.',
    'UX e Acessibilidade',
    'hibrido',
    'estagio',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 14 DAY,
    NOW() + INTERVAL 38 DAY
),
(
    (SELECT id FROM empresas WHERE email = 'contato@paratechlab.example'),
    'Projeto de Acessibilidade Digital',
    'Projeto fictício para revisão de interfaces, contraste, navegação por teclado, textos alternativos e boas práticas de inclusão digital.',
    'Interesse em acessibilidade, HTML semântico e testes manuais de interface.',
    'Acessibilidade Digital',
    'remoto',
    'outro',
    'Curitiba',
    'PR',
    'publicada',
    NOW() - INTERVAL 3 DAY,
    NOW() + INTERVAL 80 DAY
);

COMMIT;

-- =========================================================
-- Conferência rápida
-- =========================================================

SELECT 
    e.id,
    e.nome_fantasia,
    e.area_atuacao,
    e.email,
    COUNT(o.id) AS total_oportunidades
FROM empresas e
LEFT JOIN oportunidades o ON o.empresa_id = e.id
WHERE e.email IN (
    'contato@techparatodos.example',
    'contato@futurodigital.example',
    'contato@dadoseinclusao.example',
    'contato@conectajovem.example',
    'contato@nuvemsocial.example',
    'contato@paratechlab.example'
)
GROUP BY e.id, e.nome_fantasia, e.area_atuacao, e.email
ORDER BY e.nome_fantasia;

SELECT 
    o.id,
    e.nome_fantasia AS empresa,
    o.titulo,
    o.area_conhecimento,
    o.modalidade,
    o.tipo_oportunidade,
    o.status,
    o.data_publicacao,
    o.data_encerramento
FROM oportunidades o
JOIN empresas e ON e.id = o.empresa_id
WHERE e.email IN (
    'contato@techparatodos.example',
    'contato@futurodigital.example',
    'contato@dadoseinclusao.example',
    'contato@conectajovem.example',
    'contato@nuvemsocial.example',
    'contato@paratechlab.example'
)
ORDER BY o.status DESC, o.data_publicacao DESC;