# LLM Auto-hospedado para AIOps em Administração de Bancos de Dados

> Pré-projeto de doutorado — PPCA/UnB
> Autor: Samuel
> Status: rascunho arquitetural v0.2 (2026-11-11)

## Enquadramento

A proposta se insere em **AIOps** (*Artificial Intelligence for IT Operations*) aplicado à administração de bancos de dados (PostgreSQL e SQL Server). A plataforma tem dois modos de uso sobre a mesma base — mesmas ferramentas, mesmos modelos, mesma auditoria:

1. **Base de conhecimento assistida** para os analistas: perguntas respondidas com o estado atual dos ambientes (consulta ao vivo por ferramentas somente leitura) e com o conhecimento documentado da equipe (RAG sobre procedimentos, runbooks e incidentes).
2. **Operação orientada a eventos**: eventos do Zabbix e do pipeline de logs são triados por um modelo pequeno e tratados por runbooks com **autonomia graduada** (informar → agir sozinho em ação reversível → agir com aprovação humana → nunca automatizar).

Terminologia: o modelo usado é um **LLM de pesos abertos auto-hospedado em infraestrutura institucional** — não um modelo "fechado" (termo que na literatura designa modelos proprietários). A operação roda na STI; o LMISup/UnB é usado para avaliação e, se necessário, ajuste fino (ADR-010).

**Núcleo e extensão**: o núcleo da pesquisa é a consulta segura ao contexto (RAG + ferramentas) e a triagem de eventos no nível 0 (informar). As ações automáticas (níveis 1 e 2) são a extensão, liberadas por evidência medida.

Palavras-chave: AIOps; LLM de pesos abertos; RAG; agentes com ferramentas; administração de bancos de dados; segurança da informação; LGPD.

## Questão de pesquisa

**Como projetar uma arquitetura segura de AIOps, baseada em um LLM de pesos abertos auto-hospedado, capaz de apoiar a administração corporativa de bancos de dados — consultando com segurança o contexto operacional e documental e agindo sobre eventos com autonomia graduada — preservando o conhecimento organizacional, protegendo informações sensíveis e reduzindo o tempo de resolução de incidentes?**

### Hipóteses de trabalho

| ID | Hipótese | Como será testada |
|----|----------|-------------------|
| H1 | Um agente RAG com recuperação híbrida (vetorial + léxica + metadados) sobre a documentação interna responde perguntas operacionais de DBA com exatidão superior a um LLM sem RAG. | Benchmark de perguntas (doc 10), métricas de exatidão e fidelidade |
| H2 | A aplicação de autorização no nível do *chunk* (RLS + OPA) impede vazamento entre perfis sem degradar significativamente a qualidade das respostas. | Testes adversariais de vazamento, comparação de qualidade com/sem filtro |
| H3 | A anonimização em camadas (regras determinísticas + NER + lista de entidades do inventário) permite pesquisa externa sem exposição de identificadores internos. | Taxa de vazamento em corpus sintético rotulado |
| H4 | O ciclo de aprendizado contínuo (incidente → runbook → Git → índice) reduz o MTTR de incidentes recorrentes. | Estudo antes/depois em incidentes reais e simulados |
| H5 | A triagem de eventos por modelo local pequeno, combinada com autonomia graduada (catálogo de runbooks, executor isolado, verificação pós-ação), reduz o tempo de resposta a eventos recorrentes sem ações indevidas. | Auditoria das triagens e execuções (doc 13), em DEV/HML antes de PROD |

> **Metodologia**: *Design Science Research*. Os critérios de avaliação (exatidão, segurança, desempenho, custo operacional, aceitação pelos analistas) estão definidos; o protocolo experimental detalhado (conjuntos de teste, métricas exatas, limiares, modelos comparados) é preliminar e será fechado na qualificação (doc 10).

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
│   ├── 12-decisoes-arquiteturais.md  ← ADRs
│   ├── 13-aiops-eventos-e-autonomia.md ← orquestrador, níveis de autonomia, executor
│   └── 14-pipeline-de-logs.md        ← coleta, mascaramento e triagem de logs dos SGBDs
├── sql/                              ← DDL de referência (PostgreSQL 16 + pgvector)
├── policies/opa/                     ← políticas Rego (consulta e ações automáticas)
├── deploy/                           ← docker-compose por servidor
└── templates/                        ← modelos de documento (servidor, runbook, incidente)
```

## Leitura recomendada

1. [Arquitetura](docs/01-arquitetura.md) → visão geral e justificativas
2. [Segurança](docs/06-seguranca.md) → requisito obrigatório; condiciona todo o resto
3. [Agente](docs/05-agente-inteligente.md) → comportamento dinâmico
4. [AIOps: eventos e autonomia](docs/13-aiops-eventos-e-autonomia.md) → operação orientada a eventos
5. [Avaliação](docs/10-avaliacao-experimental-e-metricas.md) → como a pesquisa será validada

## Convenções

- Documentação em Markdown, diagramas em Mermaid (renderizam no VS Code e no Git).
- **Segredos nunca aparecem em texto**: referências a senhas usam a sintaxe `<usuario>.vault` (ex.: `rag_app.vault`), resolvida pelo HashiCorp Vault em tempo de execução.
- Nomes de servidores nos exemplos são fictícios (`PG-PROD02`, `SQL-HML01`).
- Toda decisão arquitetural relevante é registrada como ADR em `docs/12-decisoes-arquiteturais.md`.
