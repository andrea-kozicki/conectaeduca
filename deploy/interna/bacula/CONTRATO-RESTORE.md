# Contrato de restauração

O Bacula só será considerado operacional após restore automatizado.

## Teste 1 — arquivo sintético

1. gerar arquivo aleatório/sintético;
2. calcular SHA-256;
3. executar backup;
4. remover a cópia de teste;
5. restaurar para diretório isolado;
6. recalcular SHA-256;
7. exigir igualdade;
8. limpar o artefato.

Nenhum dado real do usuário é usado.

## Teste 2 — MariaDB sintético

1. criar banco/tabela de teste isolada;
2. inserir registros sintéticos;
3. gerar dump pelo mesmo mecanismo usado pelo job;
4. enviar ao Bacula;
5. restaurar o dump em schema temporário;
6. consultar contagem/hash esperado;
7. destruir o schema de teste.

O teste nunca sobrescreve o banco real.

## Teste 3 — Catalog

Periodicamente, provar que o dump do Catalog é legível e estruturalmente válido.
Restauração completa do Catalog será documentada, mas não precisa destruir o
Catalog ativo em cada checkpoint.

## Teste 4 — OpenBao

A validação de restore do OpenBao deve usar ambiente/snapshot **sintético ou
isolado**. Nunca restaurar por cima do OpenBao operacional apenas para produzir
evidência.

## Fail-closed

Se:
- backup falhar;
- hash divergir;
- restore não produzir o artefato;
- staging estiver com permissões abertas;
- segredo aparecer no relatório;

o checkpoint falha.
