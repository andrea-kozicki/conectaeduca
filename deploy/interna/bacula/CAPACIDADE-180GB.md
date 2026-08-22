# Orçamento de capacidade — 180 GiB por Ubuntu

Os números abaixo são limites operacionais iniciais, não partições rígidas.
Servem para impedir crescimento silencioso de Wazuh e Bacula.

## Ubuntu DMZ — 8 GiB RAM / 180 GiB disco

| Uso | Orçamento inicial |
|---|---:|
| SO, pacotes e atualizações | 25 GiB |
| Docker: imagens/camadas/cache | 30 GiB |
| aplicação e runtime | 15 GiB |
| WAF/Nginx/PHP e logs locais | 20 GiB |
| staging temporário de backup | 10 GiB |
| margem operacional | 30 GiB |
| reserva/futuro | 50 GiB |

O staging de backup não é armazenamento permanente. Arquivos temporários devem
ser removidos somente após confirmação do job.

## Ubuntu Interna — 16 GiB RAM / 180 GiB disco

| Uso | Orçamento inicial |
|---|---:|
| SO, pacotes e atualizações | 25 GiB |
| Docker: imagens/camadas/cache | 25 GiB |
| Wazuh e retenção local | 50 GiB |
| MariaDB da aplicação | 15 GiB |
| OpenBao + Ferret | 10 GiB |
| Bacula Catalog + working/staging | 10 GiB |
| Bacula volumes de backup | 30 GiB |
| margem operacional | 15 GiB |

Total planejado: 180 GiB.

## Limites de segurança

- 75% de ocupação: advertência operacional.
- 85% de ocupação: nível crítico; novos Full backups devem ser revisados antes
  de continuar enchendo o volume.
- Nunca usar `docker image prune -a` como mecanismo normal de capacidade.
- Wazuh mantém política própria de retenção; Bacula não deve copiar
  indiscriminadamente os índices do Indexer.
- O Storage do Bacula começa com teto lógico de aproximadamente 30 GiB no
  laboratório. A retenção deve ser calibrada após os primeiros jobs reais.

## RAM

A arquitetura evita fixar limites finais antes de medir, mas parte destes
orçamentos:

- DMZ: reservar no mínimo ~2 GiB para o SO; os 6 GiB restantes atendem
  aplicação, WAF e File Daemon.
- Interna: Wazuh é o principal consumidor; Bacula Director/SD/Catalog devem
  permanecer modestos. O checkpoint deverá registrar memória real para
  recalibrar limites.
