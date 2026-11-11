# 11 — Roadmap de Evolução Tecnológica

## Horizonte 1 — Pesquisa (0–18 meses)

Escopo do doutorado: arquitetura descrita nos docs 01–14, 3 servidores, uma equipe DBA, PostgreSQL e SQL Server.

- **Núcleo**: consulta segura ao contexto (RAG + ferramentas ao vivo) e AIOps nível 0 (triagem de eventos do Zabbix e do pipeline de logs).
- **Extensão**: AIOps nível 1 em DEV/HML e nível 2 em PROD com aprovação (doc 13).
- Avaliação de modelos no LMISup; operação na STI (ADR-010).

## Horizonte 2 — Produção institucional (18–36 meses)

| Tema | Evolução |
|------|----------|
| Plataforma | Kubernetes on-premises, GitOps (Argo CD), *service mesh* mTLS |
| Inferência | vLLM com *batching* contínuo; roteamento por complexidade (modelo pequeno ↔ grande); *speculative decoding* |
| Recuperação | GraphRAG: grafo de conhecimento (servidor → banco → aplicação → incidente → runbook) para perguntas relacionais ("o que é afetado se o PG-PROD02 cair?"); possivelmente Apache AGE no próprio PostgreSQL |
| Dados | `halfvec`/quantização binária no pgvector; particionamento; réplicas de leitura |
| Coleta | Inventário e parâmetros coletados automaticamente (detecção de *drift* doc × realidade) |
| Integrações | Evento do Zabbix → abertura automática de incidente com contexto pré-carregado (a partir da fila do doc 13); ITSM (GLPI/ServiceNow) |
| Fila de eventos | Redis Streams / RabbitMQ se o volume superar a fila em tabela (ADR-013) |
| Mais SGBDs | MySQL/MariaDB, MongoDB, Oracle |
| Multi-equipe | Infraestrutura, redes, sistemas — *multi-tenant* com RLS por `tenant_id` |

## Horizonte 3 — Operações autônomas supervisionadas (36+ meses)

| Tema | Evolução |
|------|----------|
| Ações assistidas | Além do catálogo de runbooks (doc 13), agente propõe *plano de ação* executável (ex.: `CREATE INDEX CONCURRENTLY` em HML), executado via pipeline com aprovação (*change management*), nunca diretamente |
| Promoção de autonomia | Ações de nível 2 com histórico consistente promovidas a nível 1 também em PROD, por MR revisado (doc 13 §13.8) |
| Diagnóstico proativo | Detecção de anomalias em métricas + correlação com incidentes passados antes do alerta |
| *Fine-tuning* / adaptação | LoRA em modelo de pesos abertos, no LMISup, com dados **sintéticos e anonimizados**, restrito a vocabulário, estilo e formato — somente se a avaliação mostrar lacuna (ADR-011); pode ser antecipado para o horizonte 1 se a lacuna aparecer cedo |
| Multiagente | Agentes especializados (PostgreSQL, SQL Server, segurança, capacidade) coordenados |
| Database DevOps | Revisão automática de *migrations* (*lint* de DDL, impacto em *locks*) integrada aos MRs dos sistemas |
| Padrões abertos | MCP como interface padrão para todas as ferramentas; interoperabilidade com assistentes de código da equipe |

## Sinais para revisitar decisões

| Decisão | Revisitar quando |
|---------|------------------|
| pgvector | > 50 M vetores ou P95 de busca > 300 ms com tuning |
| Ollama | > 20 usuários simultâneos ou necessidade de *batching* |
| LangGraph | Biblioteca deixar de ser mantida ou surgir padrão de orquestração superior; isolar via interfaces |
| Teto INTERNO no MCP | Disponibilidade de assistente de código executando com modelo local |
| Fila em tabela (`ops.event_queue`) | Atraso de consumo P95 > 30 s ou contenção de *locks* na fila |
| Uso do LMISup | Mudança nas condições de acesso ou política de dados do laboratório |
