# Bacula — fase de arquitetura

Este diretório contém o contrato **pré-implementação**. Ainda não há Compose
Bacula versionado nesta fase.

Ordem de leitura:

1. `CAPACIDADE-180GB.md`
2. `MATRIZ-BACKUP.md`
3. `CONSISTENCIA.md`
4. `POLITICA-RPO-RTO-RETENCAO.md`
5. `ARQUITETURA-COMPONENTES.md`
6. `REDE-PFSENSE.md`
7. `IDENTIDADES-PRIVILEGIOS.md`
8. `CONTRATO-RESTORE.md`
9. `OBSERVABILIDADE-WAZUH.md`
10. `CONTRATO-CHECKPOINT.md`
11. `DECISOES-PRE-IMPLEMENTACAO.md`

O objetivo é impedir que o Bacula seja instalado antes de sabermos:
- o que proteger;
- o que excluir;
- onde armazenar;
- como atravessar DMZ/interna;
- como garantir consistência;
- como restaurar;
- como provar que restaura.
