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
