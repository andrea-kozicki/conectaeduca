# PA-04 — Descoberta de segredos e credenciais

## Objetivo

Verificar se uma identidade interna de baixo privilégio consegue localizar material de autenticação reutilizável indevidamente legível na EP125/EP126.

## Estado atual — EP126, 07/10/2026

**NIST SP 800-115:** Discovery em andamento.

A primeira coleta da EP126 foi executada junto da Discovery do PA-03, sem imprimir valores secretos.

Evidência:

- host: `ep126-pucpr`;
- identidade: `teste`;
- SHA-256: `751fddebbf50b76d6b727925840f5e8ddcb81cef7a85e84f42b040465fdc3d32`.

## Resultados preliminares

- `/run/secrets`: ausente no host;
- nenhuma variável de ambiente com nome sugestivo de `PASSWORD`, `TOKEN`, `SECRET`, `KEY` ou `CREDENTIAL`;
- `~/.ssh`: ausente;
- `~/.my.cnf`: ausente;
- `~/.pgpass`: ausente;
- `~/.netrc`: ausente;
- `~/.env`: ausente;
- `~/.docker`: ausente;
- `~/.config`: presente, modo `0700`, propriedade `teste:teste`;
- nenhum valor secreto foi exibido.

## Interpretação

Até esta etapa não foi confirmado segredo reutilizável acessível à identidade `teste`. A ausência dos arquivos domésticos comuns e de variáveis sensíveis reduz superfícies triviais de descoberta, mas ainda não encerra o PA-04.

## Próximo passo

Executar triagem metadata-only de arquivos com nomes associados a credenciais/segredos em caminhos de runtime e configuração relevantes, sem ler ou imprimir conteúdo secreto.
