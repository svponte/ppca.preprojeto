# Instruções para assistentes de IA neste repositório

Repositório do pré-projeto de doutorado (PPCA/UnB): arquitetura de plataforma de AIOps com LLM de pesos abertos auto-hospedado para DBAs (base de conhecimento com RAG + ferramentas e operação orientada a eventos com autonomia graduada).

## Regras
- Idioma: português do Brasil.
- **Nunca** escrever senhas, IPs reais, nomes reais de servidores ou usuários. Senhas: sintaxe `<usuario>.vault`. Servidores nos exemplos: fictícios (`PG-PROD02`, `SQL-HML01`).
- Toda decisão arquitetural nova ou alterada → registrar em `docs/12-decisoes-arquiteturais.md` (ADR numerado) e atualizar os documentos afetados.
- Manter coerência entre `docs/`, `sql/` e `policies/`: se mudar o modelo de dados, atualizar `docs/03` e `docs/04`; se mudar regra de acesso, atualizar `docs/06` e os testes Rego.
- Diagramas em Mermaid dentro dos .md.
- Terminologia: "LLM de pesos abertos auto-hospedado" (nunca "LLM fechado"). Ações automáticas só via catálogo de runbooks e níveis de autonomia (doc 13, ADR-014); mudou nível ou ação → atualizar `docs/13` e `policies/opa/action_authz*.rego`.

## Validação
- SQL: PostgreSQL 16 + pgvector ≥ 0.8. `01–03` e `05` na base ragdb, `04` na base auditdb.
- Políticas: `opa check policies/opa && opa test policies/opa -v`.

## Estrutura
Ver `README.md`.
