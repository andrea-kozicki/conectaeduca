# Decisões pré-implementação do Bacula

Status: arquitetura aprovada para virar implementação após checkpoint.

## Decisões fechadas

1. DMZ: Ubuntu 8 GiB RAM / 180 GiB.
2. Interna: Ubuntu 16 GiB RAM / 180 GiB.
3. Director, Storage e Catalog ficam na VM interna.
4. Catalog será PostgreSQL dedicado, não o MariaDB da aplicação.
5. File Daemon será nativo em cada Ubuntu.
6. Storage principal não fica na DMZ.
7. Storage local do laboratório começa com orçamento ~30 GiB.
8. Backup usa allowlist; não existe backup cego de `/`.
9. MariaDB entra por dump consistente.
10. OpenBao entra por Raft snapshot; root token/unseal shares nunca entram.
11. Wazuh Indexer bruto e Ferret `inbox/reports/raw` ficam fora do baseline.
12. TLS entre daemons é obrigatório na topologia final.
13. 9101/9102/9103 não são expostas à Internet.
14. Restore sintético é critério obrigatório de aceite.
15. Observabilidade no Wazuh usa somente eventos minimizados.
16. Perda total do disco da VM interna é risco residual conhecido enquanto o
    Storage permanecer no mesmo disco virtual.
17. A arquitetura deve permitir mover o Storage para destino externo depois.

## Decisões para a fase de implementação

- versão/tag/digest exatos do Bacula Community;
- imagem oficial, de distribuição ou build próprio;
- nomes finais dos serviços;
- parâmetros de memória;
- horários dos jobs;
- FQDN/IP finais;
- certificados/CA;
- mecanismo final de criptografia de volume e custódia da chave;
- limite/tamanho real dos volumes após medição dos primeiros Fulls.

Esses itens não são omissões: dependem de validação de imagem e do ambiente das
VMs e serão documentados no próximo tijolo.
