# GA-08 — proposta de isolamento WAF/Nginx/PHP (28/10/2026)

Status: **PROPOSTA, NÃO IMPLANTADA**. Não aplicar em produção sem validar a configuração efetiva do Compose e as dependências.

## Constatações

Na EP125, os três contêineres `conectaeduca-dmz-waf-1`, `conectaeduca-dmz-nginx-1` e `conectaeduca-dmz-php-1` estão na rede `conectaeduca-dmz_frontend`. O Nginx não publica 8080/8088 no host; o WAF publica 80 e 443 em 192.168.6.34. `compose.waf.yml` já usa `ports: !reset []` para o Nginx.

## Desenho candidato

- `waf_backend`: somente WAF e Nginx.
- `app_backend`: somente Nginx e PHP.
- WAF continua expondo 80/443; Nginx e PHP sem portas publicadas.
- Não definir `internal: true` em `app_backend` antes de comprovar a conectividade de saída do PHP com o banco da EP126 e demais dependências.
- **Atenção:** redes Docker não implementam ACL de destino por porta nem impedem o PHP comprometido de alcançar Nginx na rede compartilhada. Não declarar o bypass totalmente mitigado sem teste negativo e controles complementares.

## Pré-requisitos de implementação

1. Gerar `docker compose config` com **exatamente a lista e ordem** dos dez overlays atualmente usados na EP125, sem publicar variáveis secretas no log; comparar `services.*.networks`, `networks`, `ports`, `extra_hosts`, `network_mode` e dependências.
2. Preparar overlay específico com substituição explícita da lista de redes dos três serviços, observando semântica de merge do Compose (`!override` se suportado), e definição das redes. Não usar `docker compose down`.
3. Validar sintaxe e diferença de configuração; confirmar se PHP requer DNS, saída TCP para MariaDB, OpenBao, e-mail ou outros serviços.
4. Aprovar janela, backup dos arquivos e rollback. Aplicar com recriação dirigida apenas dos serviços impactados.
5. Testes de aceite: HTTPS WAF→Nginx→PHP funcional; Nginx não publicado no host; teste de isolamento de contêiner não autorizado; comunicação PHP→DB; ausência de falhas de health; reteste de bypass com origem controlada; rollback ensaiado.
6. Confirmar persistência após recriação e registrar evidências sanitizadas em diário EP125 e Trello.

## Critério de encerramento

A GA-08 só pode ser encerrada com alteração efetivamente aplicada, teste positivo e negativo reproduzível, evidência de topologia e verificação de que o bypass não continua disponível para a origem do cenário original. A segmentação de duas redes **não equivale** à garantia de que todo acesso ao Nginx passe pelo WAF.
