# Bacula Director + Storage — hardening de runtime

Validação operacional: 08/09/2026, EP126.

## Controles

Director:
- rootfs read-only;
- PID 1 efetivo como bacula UID 100/GID 101;
- bootstrap root restrito a CHOWN/SETUID/SETGID;
- modo PID-less (`-P`): supervisão e unicidade ficam a cargo do Docker/Compose;
- cap_drop ALL;
- pids_limit 256;
- no-new-privileges;
- healthcheck;
- 9101 não publicado;
- config e TLS somente leitura;
- socket PgBouncer mantido como volume RW necessário.

Storage:
- rootfs read-only;
- PID 1 efetivo como bacula UID 100/GID 101;
- bootstrap root restrito a CHOWN/SETUID/SETGID;
- modo PID-less (`-P`): supervisão e unicidade ficam a cargo do Docker/Compose;
- cap_drop ALL;
- pids_limit 256;
- no-new-privileges;
- healthcheck;
- 9103 publicado somente em 192.168.6.50;
- config/TLS somente leitura;
- /backup persistente RW, bacula:bacula 0750.

## TLS

Arquivos world-readable foram classificados por tipo. Certificados/CA públicos
não são tratados como segredo. Chaves privadas devem permanecer sem acesso
para outros e sem escrita por grupo/outros.

Director↔Storage permanece com TLS Require nos dois lados. O sucesso de
`status storage=ConectaEducaStorage` após a promoção valida o canal funcional
sob a configuração TLS obrigatória.

## Console administrativo

A ausência de recurso Console dedicado foi reclassificada: o bconsole atual usa
a credencial administrativa do Director, mas o arquivo é root-only 0600 e 9101
não é publicado no host. Para este laboratório de operador único, permanece como
console administrativo local. Separação RBAC de consoles pode ser adotada em
produção/multioperador.

A validação automatizada do console usa `docker run -i` para manter STDIN,
`bconsole -n` para modo de scripting e `-u 15` como timeout interno. O lote
de comandos permanece em arquivo temporário 0600 e não é versionado.

## Evidência

Relatório READ-ONLY anterior:
`33482801db04d55e172d01fa3a3bf09221daf194a3c6c3a48790263e8678314f`

Relatório final do Tijolão 6 v9:
`43d962745452d03b90448edd3ecfde48eaea7e5cbbf075778d391d61bed8edc8`

Pacote repo-ready gerado pela v9:
`27355d4dd6982ae94e52b55448bb6b5daaa753e0e232623656dfcccc1ed931f2`

Os testes v3-v8 isolaram a interação entre tmpfs, capabilities, criação do PID file,
coleta de `/proc/1/status`, normalização da nomenclatura de capabilities e transporte
de STDIN para o bconsole. O gate pré-v6 aprovou o modelo PID-less (`-P`) com
diretórios restritivos bacula-owned, sem CAP_DAC_OVERRIDE e sem mutação live.

A documentação deste pacote recebeu uma correção textual pós-validação para restaurar
trechos entre crases que haviam sido expandidos pelo shell durante a geração do pacote.
A correção não altera os overlays YAML nem o runtime validado.

Nenhuma senha, chave privada, verifier ou conteúdo de secret deve ser versionado.
