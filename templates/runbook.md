---
tipo: RUNBOOK
titulo: "Tratamento de <problema>"
sgbd: [POSTGRESQL]
ambientes: []               # vazio = genérico
classificacao: INTERNO
grupos: []
origem: manual              # manual | incidente-<id>
gerado_por: humano          # humano | ia
revisado_por: ""
revisado_em: ""
palavras_chave: []          # códigos de erro, parâmetros, wait types
# Bloco opcional — só em runbooks automatizáveis (doc 13). Nunca preenchido por IA:
# inclusão exige MR próprio revisado por DBA sênior. Nível 3 não existe aqui.
# automacao:
#   acao_id: <identificador_unico>
#   categorias: [<categoria_de_triagem>]
#   niveis: { DEV: 1, HML: 1, PROD: 2 }     # 0 = informar, 1 = automático, 2 = com aprovação
#   reversivel: true
#   idempotente: true
#   script: scripts/<sgbd>/<script>.sh
#   parametros: {}                         # JSON Schema dos parâmetros
#   timeout_s: 30
#   max_por_hora: 3
#   credencial: aiops_executor.vault
#   condicao_sucesso: >
#     <consulta somente leitura que confirma o resultado>
---

# Tratamento de <problema>

## Sintomas
O que se observa (alertas, mensagens de erro com código, métricas).

## Diagnóstico
Passos e consultas somente leitura para confirmar a causa.

```sql
-- consulta de diagnóstico
```

## Causa raiz
Explicação técnica.

## Resolução
Passos numerados. Comandos destrutivos marcados com ⚠️ e passo de confirmação.
Credenciais: `<usuario>.vault`.

## Prevenção
Mudanças de configuração, monitoramento, revisão de código.

## Ocorrências
| Data | Incidente | Servidor | Observação |
|------|-----------|----------|------------|

## Referências
- Documentação oficial
- Runbooks relacionados
