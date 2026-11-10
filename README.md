# Plataforma Corporativa de IA para Administração de Bancos de Dados com RAG Seguro

> Pré-projeto de doutorado — PPCA/UnB
> Autor: Samuel
> Status: rascunho arquitetural v0.1 (2026-11-10)

## Questão de pesquisa

**Como projetar uma arquitetura segura baseada em IA Generativa e RAG capaz de apoiar a administração corporativa de bancos de dados, preservando o conhecimento organizacional, protegendo informações sensíveis e reduzindo o tempo de resolução de incidentes?**

### Hipóteses de trabalho

| ID | Hipótese | Como será testada |
|----|----------|-------------------|
| H1 | Um agente RAG com recuperação híbrida (vetorial + léxica + metadados) sobre a documentação interna responde perguntas operacionais de DBA com exatidão superior a um LLM sem RAG. | Benchmark de perguntas (doc 10), métricas de exatidão e fidelidade |
| H2 | A aplicação de autorização no nível do *chunk* (RLS + OPA) impede vazamento entre perfis sem degradar significativamente a qualidade das respostas. | Testes adversariais de vazamento, comparação de qualidade com/sem filtro |
| H3 | A anonimização em camadas (regras determinísticas + NER + lista de entidades do inventário) permite pesquisa externa sem exposição de identificadores internos. | Taxa de vazamento em corpus sintético rotulado |
| H4 | O ciclo de aprendizado contínuo (incidente → runbook → Git → índice) reduz o MTTR de incidentes recorrentes. | Estudo antes/depois em incidentes reais e simulados |

## Estrutura do repositório

```
ppca.preprojeto/
├── README.md                         ← este arquivo
├── CLAUDE.md / AGENTS.md             ← instruções para Claude Code e Codex
├── docs/
│   ├── 01-arquitetura.md             ← arquitetura completa e microsserviços
│   ├── 02-diagramas.md               ← diagramas (Mermaid) de componentes e implantação
│   ├── 03-modelo-de-dados.md         ← modelo relacional (catálogo, auditoria, incidentes)
│   ├── 04-banco-vetorial.md          ← modelo pgvector, chunking, índices
│   ├── 05-agente-inteligente.md      ← fluxo LangGraph e ferramentas
│   ├── 06-seguranca.md               ← fluxo de segurança, Zero Trust, LGPD
│   ├── 07-pesquisa-externa-e-anonimizacao.md
│   ├── 08-aprendizado-continuo.md
│   ├── 09-plano-de-implantacao.md
│   ├── 10-avaliacao-experimental-e-metricas.md
│   ├── 11-roadmap.md
│   └── 12-decisoes-arquiteturais.md  ← ADRs
├── sql/                              ← DDL de referência (PostgreSQL 16 + pgvector)
├── policies/opa/                     ← políticas Rego de autorização
├── deploy/                           ← docker-compose por servidor
└── templates/                        ← modelos de documento (servidor, runbook, incidente)
```

## Leitura recomendada

1. [Arquitetura](docs/01-arquitetura.md) → visão geral e justificativas
2. [Segurança](docs/06-seguranca.md) → requisito obrigatório; condiciona todo o resto
3. [Agente](docs/05-agente-inteligente.md) → comportamento dinâmico
4. [Avaliação](docs/10-avaliacao-experimental-e-metricas.md) → como a pesquisa será validada

## Convenções

- Documentação em Markdown, diagramas em Mermaid (renderizam no VS Code e no Git).
- **Segredos nunca aparecem em texto**: referências a senhas usam a sintaxe `<usuario>.vault` (ex.: `rag_app.vault`), resolvida pelo HashiCorp Vault em tempo de execução.
- Nomes de servidores nos exemplos são fictícios (`PG-PROD02`, `SQL-HML01`).
- Toda decisão arquitetural relevante é registrada como ADR em `docs/12-decisoes-arquiteturais.md`.
