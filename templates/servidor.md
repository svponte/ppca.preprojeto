---
tipo: CONFIGURACAO_SERVIDOR
servidor: PG-EXEMPLO01
sgbd: POSTGRESQL            # POSTGRESQL | SQLSERVER | MYSQL
versao: "16.4"
ambiente: PROD              # PROD | HML | DEV
so: "Ubuntu 24.04"
ha: primary                 # primary | standby | ag-primary | ag-secondary | standalone
pgbouncer: false
classificacao: CONFIDENCIAL # PUBLICO | INTERNO | CONFIDENCIAL | RESTRITO
grupos: [dba-pg]
responsavel: equipe-dba
tags: []
---

# PG-EXEMPLO01

## Finalidade
Sistemas e bancos hospedados.

## Topologia
Primário/réplicas, pooler, balanceador.

## Endereçamento de rede <!-- classificacao: RESTRITO -->
| Interface | Endereço |
|-----------|----------|
| serviço   | x.x.x.x  |

## Parâmetros relevantes
| Parâmetro | Valor | Justificativa |
|-----------|-------|---------------|
| shared_buffers | | |
| max_connections | | |

## Backup
Ferramenta, agenda, retenção, local, teste de restauração.

## Monitoramento
Itens/gatilhos do Zabbix associados.

## Acessos
Contas de serviço (senhas: `<usuario>.vault`, nunca em texto).

## Histórico de incidentes
- [incidentes/AAAA-MM-DD-titulo.md](../incidentes/)
