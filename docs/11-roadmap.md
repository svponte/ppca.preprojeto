# 11 — Roadmap de Evolução Tecnológica

## Horizonte 1 — Pesquisa (0–18 meses)

Escopo do doutorado: arquitetura descrita nos docs 01–10, 3 servidores, uma equipe DBA, PostgreSQL e SQL Server.

## Horizonte 2 — Produção institucional (18–36 meses)

| Tema | Evolução |
|------|----------|
| Plataforma | Kubernetes on-premises, GitOps (Argo CD), *service mesh* mTLS |
| Inferência | vLLM com *batching* contínuo; roteamento por complexidade (modelo pequeno ↔ grande); *speculative decoding* |
| Recuperação | GraphRAG: grafo de conhecimento (servidor → banco → aplicação → incidente → runbook) para perguntas relacionais ("o que é afetado se o PG-PROD02 cair?"); possivelmente Apache AGE no próprio PostgreSQL |
| Dados | `halfvec`/quantização binária no pgvector; particionamento; réplicas de leitura |
| Coleta | Inventário e parâmetros coletados automaticamente (detecção de *drift* doc × realidade) |
| Integrações | Zabbix → abertura automática de incidente com contexto pré-carregado; ITSM (GLPI/ServiceNow) |
| Mais SGBDs | MySQL/MariaDB, MongoDB, Oracle |
| Multi-equipe | Infraestrutura, redes, sistemas — *multi-tenant* com RLS por `tenant_id` |

## Horizonte 3 — Operações autônomas supervisionadas (36+ meses)

| Tema | Evolução |
|------|----------|
| Ações assistidas | Agente propõe *plano de ação* executável (ex.: `CREATE INDEX CONCURRENTLY` em HML), executado via pipeline com aprovação (*change management*), nunca diretamente |
| Diagnóstico proativo | Detecção de anomalias em métricas + correlação com incidentes passados antes do alerta |
| *Fine-tuning* / adaptação | LoRA em modelo local com dados **sintéticos e anonimizados** para jargão da equipe — somente se a avaliação mostrar ganho sobre RAG puro |
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
