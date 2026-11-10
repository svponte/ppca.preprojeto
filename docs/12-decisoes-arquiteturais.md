# 12 — Registro de Decisões Arquiteturais (ADRs)

Formato: contexto → decisão → consequências. Novas decisões são acrescentadas ao final; decisões substituídas recebem status "Substituída por ADR-xxx".

---

## ADR-001 — Inferência 100% local (Ollama)
**Status**: Aceita
**Contexto**: Documentação contém topologia, IPs e configurações; requisito de que nenhuma informação confidencial saia da organização; LGPD.
**Decisão**: LLM, embeddings e reranker executam localmente no SRV-3, sem rota para a Internet. Ollama no protótipo; LLM gateway abstrai o provedor.
**Consequências**: (+) soberania dos dados, sem transferência internacional; (−) qualidade limitada pela GPU disponível; necessidade de avaliar modelos abertos (doc 10).

## ADR-002 — PostgreSQL + pgvector como banco vetorial
**Status**: Aceita
**Contexto**: Autorização deve ser garantida no dado; equipe domina PostgreSQL; volume previsto ≤ 10⁶ *chunks*.
**Decisão**: pgvector com HNSW, busca híbrida em SQL, RLS para autorização.
**Consequências**: (+) uma única política para texto, vetor e metadados; operação conhecida; (−) escala limitada comparada a bancos dedicados (ver sinais no roadmap).

## ADR-003 — LangGraph para orquestração, LlamaIndex para dados
**Status**: Aceita
**Contexto**: Agente precisa de estados explícitos, pausa para aprovação humana e retomada.
**Decisão**: LangGraph (grafo + *checkpointer* PostgreSQL + `interrupt`) para o agente; LlamaIndex para parsing, *chunking* e recuperação.
**Consequências**: (+) cada biblioteca no ponto forte; grafo testável; (−) duas dependências em rápida evolução → versões fixadas e interfaces próprias.

## ADR-004 — Git como fonte canônica; índice derivado
**Status**: Aceita
**Contexto**: Conhecimento hoje disperso (Teams); necessidade de rastreabilidade e revisão.
**Decisão**: Markdown no Git é a verdade; o índice é reconstruível a qualquer momento.
**Consequências**: (+) revisão por MR, histórico, *rollback*, fluxo compatível com VS Code/Claude Code/Codex; (−) exige disciplina de documentação e migração inicial.

## ADR-005 — Pesquisa externa sempre com aprovação humana
**Status**: Aceita
**Contexto**: Anonimização automática nunca tem *recall* de 100%.
**Decisão**: Toda pesquisa externa exibe o texto exato e exige aprovação; sem modo automático.
**Consequências**: (+) humano como última barreira, responsabilidade clara, auditoria; (−) atrito; mitigado por pedir apenas quando o conhecimento interno é insuficiente.

## ADR-006 — Ferramentas SQL por catálogo pré-aprovado, não *text-to-SQL*
**Status**: Aceita
**Contexto**: Agente consultará servidores de produção.
**Decisão**: Consultas parametrizadas revisadas pela equipe; credenciais dinâmicas RO; transação RO; *timeout*.
**Consequências**: (+) previsível, seguro, auditável; (−) cobertura limitada ao catálogo — evolui com a equipe; *text-to-SQL* apenas em DEV e sobre `catalog`.

## ADR-007 — Teto de classificação INTERNO para o canal MCP
**Status**: Aceita
**Contexto**: Claude Code e Codex, usados pela equipe no VS Code, enviam o contexto a modelos externos. Conteúdo retornado pelo MCP interno acabaria fora da organização.
**Decisão**: O servidor MCP recebe *clearance* máximo INTERNO (obrigação do OPA para `channel = mcp`), independentemente do perfil do usuário; conteúdo CONFIDENCIAL/RESTRITO só pela interface web servida pelo LLM local.
**Consequências**: (+) fecha um canal de vazamento relevante e pouco óbvio; (−) menos contexto no assistente de código; revisitar se o assistente puder usar modelo local.

## ADR-008 — Autorização em três pontos (OPA, RLS, DLP)
**Status**: Aceita
**Contexto**: LLMs são vulneráveis a *prompt injection*; um único ponto de controle não basta.
**Decisão**: OPA decide na borda e em cada ferramenta; RLS aplica no dado; DLP verifica a saída.
**Consequências**: (+) defesa em profundidade, falha fechada; (−) complexidade e necessidade de testes de consistência entre políticas.

## ADR-009 — Aprendizado contínuo por curadoria, não por *fine-tuning*
**Status**: Aceita
**Contexto**: Requisito de aprender com incidentes; risco de o modelo memorizar dados sensíveis; custo de GPU.
**Decisão**: Aprendizado = runbooks gerados, revisados e versionados no Git + reindexação.
**Consequências**: (+) auditável e reversível; (−) depende de revisão humana (gargalo potencial — medido no doc 08).
