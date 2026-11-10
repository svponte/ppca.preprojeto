# 09 — Plano de Implantação

Abordagem incremental: cada fase entrega valor utilizável e gera dados para a pesquisa. Segurança não é fase final — cada fase tem seus controles mínimos.

## Fase 0 — Fundação (meses 1–2)

| Entrega | Detalhe |
|---------|---------|
| Infraestrutura | 3 servidores provisionados, VLANs, regras de *firewall* (doc 02), Docker |
| Identidade | Keycloak federado ao AD; grupos `GG-DBA-*` mapeados |
| Segredos | Vault inicializado; engines database, PKI, KV |
| Git | Gitea; repositório `dba/conhecimento`; pré-commit + CI com *markdownlint* e *gitleaks* |
| Banco | ragdb/auditdb com `sql/01–04` |
| Observabilidade | Prometheus, Grafana, Loki, agente Wazuh |
| Governança | RIPD (LGPD) iniciado; submissão ao CEP do protocolo de avaliação |

## Fase 1 — Base de conhecimento e RAG somente leitura (meses 3–5)

- Migração do conteúdo do Teams para Markdown com *templates* (servidor, runbook, incidente, política). Normalização de caracteres invisíveis (ex.: espaço não separável) que hoje quebram comandos colados no MobaXterm.
- Ingestion-worker com classificação + mascaramento.
- Retrieval-service + LLM local; interface web simples.
- **Sem ferramentas** e **sem pesquisa externa**.
- *Baseline* do experimento: conjunto de perguntas (doc 10) e MTTR histórico.

**Critério de saída**: exatidão ≥ meta no conjunto de teste; zero vazamento no teste de RLS.

## Fase 2 — Agente com ferramentas (meses 6–8)

- LangGraph com classificação de intenção, inventário, catálogo de consultas RO, métricas (Zabbix/Prometheus), logs.
- OPA para ferramentas; credenciais dinâmicas por alvo — **começando por DEV/HML**, PROD após 4 semanas sem incidentes.
- Servidor MCP para VS Code (Claude Code / Codex) com teto INTERNO; CLI `dbai` para os *jump hosts*.

## Fase 3 — Pesquisa externa e aprendizado contínuo (meses 9–11)

- Anonimizador em 3 camadas + verificador residual; *red team* com corpus sintético antes de liberar.
- External Search Gateway + SearXNG + proxy *allowlist*.
- Knowledge Writer + fluxo de MR.
- Estudo de campo (H4) inicia.

## Fase 4 — Endurecimento e escala (meses 12–18)

- Migração para Kubernetes (k3s/RKE2 on-premises): namespaces por fronteira, NetworkPolicies, *service mesh* mTLS.
- Alta disponibilidade: Patroni (ragdb), Keycloak em *cluster*, Vault HA.
- vLLM para *throughput*; pool de GPUs.
- *Pentest* externo e auditoria de conformidade.

## Riscos do plano

| Risco | Prob. | Impacto | Mitigação |
|-------|-------|---------|-----------|
| GPU insuficiente para modelo de qualidade | Média | Alto | Avaliar modelos menores quantizados; priorizar recuperação de qualidade (o RAG compensa parte); solicitar GPU com antecedência |
| Documentação atual desatualizada / incompleta | Alta | Alto | Fase 1 inclui saneamento; métrica de "lacunas" orienta esforço |
| Baixa adoção pela equipe | Média | Alto | Integração com ferramentas já usadas (VS Code, MobaXterm); respostas com citação geram confiança |
| Classificação incorreta → vazamento | Baixa | Muito alto | Fail-closed, só eleva, revisão humana, testes adversariais contínuos |
| Respostas erradas aplicadas em produção | Média | Alto | Agente não executa escrita; aviso explícito; runbooks revisados |
| Dependência de bibliotecas em rápida evolução (LangGraph, LlamaIndex) | Alta | Médio | Versões fixadas, interfaces próprias, testes de regressão do agente |

## Cronograma (Gantt)

```mermaid
gantt
    dateFormat  YYYY-MM
    axisFormat  %b/%y
    title Implantação — ambiente de pesquisa
    section Fase 0
    Fundação (infra, IdP, Vault, Git, DB)   :f0, 2027-03, 2M
    section Fase 1
    Migração KB + RAG RO + baseline         :f1, after f0, 3M
    section Fase 2
    Agente + ferramentas + MCP/CLI          :f2, after f1, 3M
    section Fase 3
    Pesquisa externa + aprendizado contínuo :f3, after f2, 3M
    section Fase 4
    Kubernetes, HA, pentest                 :f4, after f3, 6M
    section Pesquisa
    Experimentos offline                    :e1, after f1, 8M
    Estudo de campo (MTTR)                  :e2, after f3, 6M
```

> Datas ilustrativas — ajustar ao calendário do PPCA.
