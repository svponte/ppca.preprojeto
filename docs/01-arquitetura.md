# 01 — Arquitetura da Solução

## 1. Princípios arquiteturais

| # | Princípio | Justificativa |
|---|-----------|---------------|
| P1 | **Conhecimento interno primeiro (internal-first)** | A documentação da organização é a fonte de verdade; o LLM é um mecanismo de raciocínio, não de memória. Reduz alucinação e mantém respostas aderentes às políticas da equipe. |
| P2 | **Dados sensíveis nunca saem do perímetro** | LLM de pesos abertos auto-hospedado (Ollama) e embeddings locais. A única saída para a Internet é a pesquisa externa, que passa obrigatoriamente pelo *gateway* de anonimização + DLP. Para o LMISup/UnB (avaliação) vão apenas dados sintéticos ou anonimizados (ADR-010). |
| P3 | **Autorização no dado, não na interface** | O filtro de permissão é aplicado no banco (Row-Level Security) **antes** da recuperação. O LLM nunca vê um *chunk* que o usuário não poderia ler (defesa contra *prompt injection* e vazamento por contexto). |
| P4 | **Zero Trust** | Toda chamada entre serviços é autenticada (mTLS + JWT), autorizada (OPA) e auditada. Nenhuma confiança implícita por estar "na rede interna". |
| P5 | **Git como fonte canônica do conhecimento** | Markdown versionado = rastreabilidade, revisão por pares (*merge request*), *rollback* e compatibilidade com o fluxo atual da equipe (VS Code, Claude Code, Codex). O índice vetorial é **derivado** e reconstruível. |
| P6 | **Escrita só por caminho controlado** | O assistente consulta catálogos, métricas e logs e nunca executa DDL/DML. Ações operacionais ocorrem apenas pelo `action-executor`, a partir de runbooks do catálogo com nível de autonomia (0 a 3); DDL, *failover*, permissões e senhas são nível 3 — nunca automatizados (doc 13, ADR-014). |
| P7 | **Observabilidade e auditabilidade completas** | Cada resposta é reproduzível: pergunta, *chunks* recuperados (com versão/commit), ferramentas chamadas, modelo e versão, latência. |
| P8 | **Componentes substituíveis** | LLM, modelo de embedding, *vector store* e orquestrador ficam atrás de interfaces. Permite evolução tecnológica sem reescrita (ver roadmap). |
| P9 | **Estado atual ao vivo; documentação pelo RAG** | Permissões, tamanhos, jobs, parâmetros vigentes e alertas vêm de consulta ao vivo pelas ferramentas do catálogo (somente leitura). O RAG cobre o conhecimento não estruturado: procedimentos, runbooks, políticas e incidentes (ADR-012). |
| P10 | **O LLM no meio, não nas pontas** | Detecção (Zabbix, regras de log) e decisão (motor de políticas + OPA) são determinísticas. O modelo só transforma texto em fatos estruturados, com saída restrita e validada (ADR-013). |

## 2. Visão em camadas

```
┌──────────────────────────────────────────────────────────────────────┐
│ CANAIS        Interface Web │ Extensão VS Code (MCP) │ CLI (MobaXterm)│
├──────────────────────────────────────────────────────────────────────┤
│ BORDA         Reverse proxy (Traefik/Nginx) + TLS + WAF + rate limit  │
├──────────────────────────────────────────────────────────────────────┤
│ IDENTIDADE    Keycloak (federação LDAP/AD, SSO OIDC, MFA)             │
├──────────────────────────────────────────────────────────────────────┤
│ API           API Gateway (FastAPI) ── OPA (PDP) ── Auditoria         │
├──────────────────────────────────────────────────────────────────────┤
│ ORQUESTRAÇÃO  Agent Service (LangGraph)                               │
│               ├─ Retrieval Service (LlamaIndex + pgvector)            │
│               ├─ Tool Service (SQL RO, logs, métricas, inventário)    │
│               ├─ External Search Gateway (anonimização + DLP)         │
│               └─ Knowledge Writer (geração de runbooks → Git MR)      │
├──────────────────────────────────────────────────────────────────────┤
│ AIOPS         Event Orchestrator (fila ops.event_queue ← Zabbix/logs) │
│               ├─ Motor de políticas + OPA (autonomia 0–3)             │
│               ├─ Action Executor (catálogo de runbooks, isolado)      │
│               └─ Log Processor (máscara → fingerprint → regras)       │
├──────────────────────────────────────────────────────────────────────┤
│ INGESTÃO      Ingestion Worker (Git webhook → parse → classificar →   │
│               mascarar → chunk → embed → upsert)                      │
├──────────────────────────────────────────────────────────────────────┤
│ INFERÊNCIA    LLM Gateway → Ollama (LLM + embeddings + reranker)      │
├──────────────────────────────────────────────────────────────────────┤
│ DADOS         PostgreSQL 16 + pgvector │ Banco de Auditoria (WORM)    │
│               Git (Gitea/GitLab)       │ Vault (segredos)             │
├──────────────────────────────────────────────────────────────────────┤
│ OPERAÇÃO      Prometheus │ Grafana │ Loki │ Langfuse │ Wazuh (SIEM)    │
└──────────────────────────────────────────────────────────────────────┘
```

## 3. Microsserviços

| Serviço | Responsabilidade | Tecnologia | Comunica com |
|---------|------------------|------------|--------------|
| **web-ui** | Chat, histórico, citações clicáveis, aprovação de pesquisa externa, revisão de runbooks | React/Next.js (ou Open WebUI customizado no protótipo) | api-gateway |
| **api-gateway** | Validação do JWT, chamada ao OPA, *rate limit*, correlação (`trace_id`), registro de auditoria | FastAPI | keycloak, opa, agent-service, audit |
| **agent-service** | Grafo do agente: classificação de intenção, planejamento, chamada de ferramentas, síntese, verificação de fidelidade | Python + LangGraph | retrieval, tools, ext-search, llm-gateway |
| **retrieval-service** | Recuperação híbrida (vetorial + BM25/`tsvector` + filtros de metadados), *reranking*, montagem de contexto com citação | LlamaIndex + pgvector | postgres (com papel do usuário), llm-gateway |
| **tool-service** | Ferramentas determinísticas: consulta SQL somente leitura nos alvos, leitura de logs, consulta de métricas Prometheus/Zabbix, inventário | FastAPI + psycopg / pyodbc | alvos via Vault (credenciais dinâmicas) |
| **ext-search-gateway** | Única saída para a Internet. Anonimiza, aplica DLP, exige aprovação, consulta fontes permitidas, sanitiza o retorno | FastAPI + Presidio + regras próprias | proxy de saída, audit |
| **ingestion-worker** | Pipeline Git → índice. Idempotente, por *commit* | Python + LlamaIndex | git, postgres, llm-gateway |
| **knowledge-writer** | Gera rascunho de runbook a partir do incidente resolvido e abre *merge request* | Python + API do Git | git, llm-gateway |
| **llm-gateway** | Abstração sobre Ollama: roteamento de modelo por tarefa, limites de contexto, fila, métricas de tokens | LiteLLM ou FastAPI próprio | ollama |
| **audit-service** | Grava eventos imutáveis (hash encadeado) e envia ao Wazuh | FastAPI + PostgreSQL | postgres-audit, wazuh |
| **event-orchestrator** | Consome `ops.event_queue`, enriquece com ferramentas RO, pede triagem restrita ao modelo pequeno, aplica o motor de políticas e o OPA (`action_authz`), notifica ou pede aprovação (doc 13) | Python (daemon) | postgres, tool-service, llm-gateway, opa, Teams |
| **action-executor** | Executa somente runbooks do catálogo (`ops.action_catalog`), com parâmetros validados, *dry-run*, limites, disjuntor e verificação pós-ação | Python + scripts bash versionados | alvos via Vault (`aiops_executor.vault`), postgres, audit |
| **log-processor** | Recebe logs (Fluent Bit/Vector, Extended Events, ERRORLOG), mascara, agrupa em padrões, aplica regras; publica métricas no Zabbix e eventos na fila (doc 14) | Python | coletores, postgres, Zabbix (`zabbix_sender`), Loki, llm-gateway |

### Por que microsserviços (e não um monólito)?

- **Fronteiras de confiança distintas**: o `ext-search-gateway` é o único com saída para a Internet; o `tool-service` é o único com credenciais de leitura para os bancos alvo; o `action-executor` é o único com credenciais de escrita, restritas ao catálogo de runbooks. Isolá-los permite políticas de rede (*egress*) e de segredos específicas — princípio do menor privilégio.
- **Perfis de carga diferentes**: ingestão é *batch* e intensiva em GPU (embeddings); consulta é interativa e sensível a latência.
- **Evolução independente**: trocar LlamaIndex por outra biblioteca de recuperação não afeta o agente.

Para o protótipo (3 servidores), os serviços rodam como contêineres Docker Compose; a mesma divisão migra para Kubernetes sem mudança de contrato (ver doc 09).

## 4. Distribuição física — ambiente de pesquisa

| Servidor | Papel | Componentes | Recursos sugeridos |
|----------|-------|-------------|--------------------|
| **SRV-1 — Aplicação** | Borda, identidade, aplicação, Git | Traefik, Keycloak, web-ui, api-gateway, agent-service, retrieval-service, tool-service, ext-search-gateway, ingestion-worker, knowledge-writer, OPA (sidecar), Gitea, Vault, Prometheus, Grafana, agente Wazuh | 8–16 vCPU, 32 GB RAM, 200 GB SSD |
| **SRV-2 — Dados** | Persistência | PostgreSQL 16 + pgvector (base `ragdb`), base `auditdb` (instância ou *cluster* separado, papéis distintos), pgBackRest, postgres_exporter | 8 vCPU, 32–64 GB RAM, 500 GB SSD NVMe |
| **SRV-3 — Inferência** | GPU | Ollama (modelo pequeno de triagem, modelo maior de interação, embeddings, reranker), llm-gateway, nvidia/dcgm-exporter | GPU ≥ 24 GB VRAM (ideal 48 GB), 16 vCPU, 64 GB RAM — dimensionamento final conforme os modelos escolhidos na avaliação (ADR-011) |
| **LMISup/UnB** (externo à STI) | Avaliação e ajuste fino condicional | Execução do *golden set*, comparação de modelos de porte maior, ajuste fino se necessário — só com dados sintéticos/anonimizados | Cluster de GPUs do laboratório; condições de acesso a confirmar (ADR-010) |

**Observações**
- Keycloak e Vault no SRV-1 são aceitáveis para pesquisa; em produção vão para nós dedicados (ver doc 09, fase 4).
- A base de auditoria fica no SRV-2, mas em **banco separado, com papel de escrita *append-only*** e replicação para o Wazuh — o serviço de aplicação não consegue apagar ou alterar eventos.
- O SRV-3 **não tem rota de saída para a Internet**. Modelos são baixados uma vez por um processo controlado e verificados por *hash*.
- A operação **não depende do LMISup**: pesos avaliados ou ajustados lá são importados pelo mesmo processo controlado e servidos no SRV-3.

## 5. Fluxo de uma consulta (resumo)

1. Usuário autentica via SSO (Keycloak federado ao AD). Recebe JWT com `sub`, grupos, `clearance`, ambientes permitidos.
2. `api-gateway` valida o token e consulta o OPA: "este usuário pode usar o agente com este escopo?".
3. `agent-service` classifica a intenção (conceitual, procedimento interno, diagnóstico de servidor, inventário, otimização).
4. `retrieval-service` abre uma sessão no PostgreSQL com `SET ROLE` + variáveis de sessão do usuário → **RLS filtra os *chunks* permitidos** → busca híbrida → *rerank*.
5. Se for diagnóstico, o agente chama ferramentas (métricas, logs, SQL RO) — cada chamada também passa pelo OPA (ambiente, servidor, tipo de ferramenta).
6. Se o conhecimento interno for insuficiente (escore de recuperação abaixo do limiar + autoavaliação do LLM), o agente **pede autorização** ao usuário para pesquisa externa; o texto anonimizado é exibido antes do envio.
7. Síntese com citações obrigatórias; verificação de fidelidade (cada afirmação ancorada em fonte).
8. Saída passa pelo DLP de resposta (mascaramento conforme *clearance* do usuário).
9. Evento completo gravado na auditoria e enviado ao Wazuh.

Detalhes nos documentos 05 (agente), 06 (segurança) e 07 (pesquisa externa).

### 5.1 Fluxo de um evento (resumo)

1. Trigger do Zabbix ou padrão novo/anômalo no pipeline de logs gera evento em `ops.event_queue`.
2. `event-orchestrator` consome o evento, deduplica, enriquece com ferramentas somente leitura.
3. Modelo pequeno devolve categoria, severidade e resumo (JSON validado contra enum).
4. Motor de políticas + OPA definem o nível: 0 (informar), 1 (executar), 2 (pedir aprovação) ou 3 (só informar).
5. `action-executor` executa o runbook do catálogo e verifica a condição de sucesso.
6. Tudo registrado em `ops.action_run` e na auditoria (`aiops.*`).

Detalhes nos documentos 13 (eventos e autonomia) e 14 (logs).

## 6. Escalabilidade para ambiente corporativo

| Dimensão | Protótipo | Corporativo |
|----------|-----------|-------------|
| Orquestração | Docker Compose | Kubernetes (namespaces por fronteira de confiança, NetworkPolicies, *service mesh* com mTLS — Istio/Linkerd) |
| LLM | 1 GPU, Ollama | Pool de GPUs; vLLM ou TGI para *throughput* (batching contínuo); Ollama mantido para desenvolvimento |
| Vetorial | pgvector, HNSW, 1 nó | pgvector com particionamento por domínio/ambiente + réplicas de leitura; avaliação de Qdrant/Milvus acima de ~50 M vetores |
| Ingestão | Worker único | Fila (Redis Streams / RabbitMQ) + workers horizontais |
| Identidade | Keycloak único | Keycloak em *cluster* (Infinispan), HA |
| Segredos | Vault *standalone* | Vault HA (Raft) com *auto-unseal* (HSM) |
| Multi-equipe | 1 equipe DBA | *Multi-tenant*: `tenant_id` em todas as tabelas + RLS; um índice lógico por equipe |

## 7. Integração com o fluxo atual da equipe

- **VS Code + Claude Code/Codex**: a plataforma expõe um **servidor MCP** (Model Context Protocol) interno com as ferramentas `buscar_documentacao`, `consultar_inventario`, `obter_runbook`. Assim, quem usa Claude Code ou Codex no VS Code consulta a base interna **sem colar documentação em ferramentas externas**. O MCP usa o mesmo token SSO e as mesmas políticas OPA.
  - Atenção: o assistente de código (Claude Code/Codex) roda contra modelos externos; o servidor MCP deve devolver apenas conteúdo com classificação ≤ `INTERNO` e já mascarado. Conteúdo `CONFIDENCIAL`/`RESTRITO` só é exibido na interface web, servido pelo LLM local. (ver ADR-007)
- **MobaXterm**: CLI `dbai` (Python) instalada nos *jump hosts*; consulta a API com o token do usuário. Saídas em texto puro, sem caracteres invisíveis, prontas para colar no terminal.
- **Base de conhecimento atual (Teams)**: migração dos textos para Markdown no Git na fase 1; o Teams passa a receber apenas notificações (novos runbooks, MRs pendentes).
