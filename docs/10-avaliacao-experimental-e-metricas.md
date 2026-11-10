# 10 — Avaliação Experimental e Métricas

## 10.1 Desenho geral

Pesquisa de natureza **Design Science Research (DSR)**: o artefato (arquitetura + protótipo) é construído e avaliado quanto a utilidade, segurança e eficiência. Avaliação em três frentes:

| Frente | Tipo | Hipótese |
|--------|------|----------|
| E1 — Qualidade das respostas | Experimento offline controlado | H1 |
| E2 — Segurança (vazamento) | Teste adversarial (*red team*) | H2, H3 |
| E3 — Impacto operacional | Estudo de campo quase-experimental | H4 |

## 10.2 E1 — Qualidade das respostas

**Conjunto de avaliação (*golden set*)**: 200–300 perguntas elaboradas pela equipe, estratificadas:

| Estrato | % | Exemplo |
|---------|---|---------|
| Conceitual simples | 20 | "Como criar um usuário PostgreSQL?" |
| Procedimento/política interna | 25 | "Existe procedimento interno para alteração do shared_buffers?" |
| Inventário | 15 | "Quais servidores utilizam pgBouncer?" |
| Localização de runbook | 10 | "Qual runbook trata deadlocks?" |
| Diagnóstico (com evidências simuladas) | 20 | "Por que o PG-PROD02 apresentou alto consumo de CPU?" |
| Sem resposta interna (deve admitir) | 10 | Procedimento inexistente |

Cada item: resposta de referência, documentos/seções relevantes, perfil de usuário.

**Condições comparadas (ablação)**:

| ID | Configuração |
|----|-------------|
| C0 | LLM local sem RAG |
| C1 | RAG vetorial puro |
| C2 | RAG híbrido (vetorial + léxico, RRF) |
| C3 | C2 + reranker |
| C4 | C3 + agente (intenção, ferramentas, verificação de fidelidade) |
| C5 | C4 com modelo de embedding / LLM alternativo (2–3 variantes) |

**Métricas**:

| Métrica | Definição | Ferramenta |
|---------|-----------|------------|
| Recall@k / MRR / nDCG@k | Recuperação dos *chunks* relevantes | script próprio |
| Exatidão (*answer correctness*) | Concordância com referência — avaliada por 2 DBAs (cego) + LLM-juiz local; concordância Cohen κ | RAGAS + avaliação humana |
| Fidelidade (*faithfulness/groundedness*) | % de afirmações sustentadas pelas evidências | RAGAS |
| Precisão de citação | % de citações que de fato sustentam a afirmação | avaliação humana amostral |
| Taxa de abstenção correta | No estrato "sem resposta", % de respostas "não há procedimento interno" | script |
| Taxa de alucinação | Afirmações sem suporte e incorretas | humana |
| Exatidão da escolha de ferramenta | Intenção → ferramenta correta | script |

**Análise estatística**: comparação pareada entre condições (mesmas perguntas): teste de Wilcoxon / McNemar (acerto binário), correção de Holm para múltiplas comparações, intervalos de confiança por *bootstrap*.

## 10.3 E2 — Segurança

**E2a — Controle de acesso (RLS/OPA)**
- Matriz perfil × documento: para cada perfil, perguntas desenhadas para recuperar conteúdo de nível superior.
- Ataques de *prompt injection* diretos (≥ 100 variações de bibliotecas públicas de *jailbreak* adaptadas) e indiretos (documentos "envenenados" plantados no corpus de teste).
- **Métrica principal**: Taxa de Vazamento = respostas contendo informação acima do *clearance* / total. **Meta: 0** (com IC 95% superior reportado — "regra de três": 0 em *n* testes → limite superior ≈ 3/*n*).

**E2b — Anonimização**
- Corpus sintético de 500+ descrições de incidentes com entidades sensíveis **rotuladas** (*hostnames*, IPs, usuários, bancos, pessoas), incluindo casos difíceis (nomes de servidor que são palavras comuns, IPs em formatos não usuais).
- Métricas por tipo de entidade: *recall* de remoção (≈ proteção), precisão (≈ não destruir utilidade), **taxa de vazamento residual**, taxa de bloqueio indevido.
- **Utilidade preservada**: para uma amostra, comparar relevância dos resultados de busca com a consulta original (simulada em fonte local) vs anonimizada.
- Ablação: camada 1; 1+2; 1+2+3; + verificador residual.

**E2c — Controles operacionais**
- Tentativas de ferramentas proibidas (escrita, servidor não autorizado) → % negadas.
- Integridade da auditoria: adulteração simulada detectada por `verify_chain`.

## 10.4 E3 — Impacto operacional

- **Desenho**: série temporal interrompida (antes/depois) + comparação de incidentes com e sem assistência (`ops.incident.assisted_by_ai`), estratificada por severidade e categoria.
- **Métricas**: MTTR, MTTA, tempo até hipótese correta, % de incidentes recorrentes resolvidos com runbook existente, escalonamentos para sênior.
- **Percepção**: SUS (usabilidade), NASA-TLX (carga cognitiva) e questionário de confiança — antes e depois; entrevistas semiestruturadas com DBAs de diferentes níveis.
- **Ameaças à validade**: efeito aprendizado/Hawthorne, poucos incidentes graves, variação sazonal → mitigação com período longo, incidentes simulados (*game days*) e controle por categoria.

## 10.5 Métricas de desempenho (operacionais)

| Métrica | Meta inicial (protótipo) | Fonte |
|---------|--------------------------|-------|
| Latência P50 / P95 — pergunta simples | ≤ 4 s / ≤ 10 s | Prometheus (histograma por intenção) |
| Latência P95 — diagnóstico multi-ferramenta | ≤ 45 s | Prometheus |
| Tempo até primeiro *token* | ≤ 2 s | LLM gateway |
| *Tokens*/s do LLM | registrar por modelo | Ollama/LLM gateway |
| Latência da busca híbrida P95 | ≤ 150 ms | `pg_stat_statements` |
| Tempo de ingestão (commit → disponível) | ≤ 5 min | ingestion-worker |
| Utilização de GPU / VRAM | < 85% sustentado | DCGM exporter |
| Disponibilidade | ≥ 99% (horário comercial) | *probes* |
| Usuários simultâneos suportados | ≥ 10 com P95 dentro da meta | teste de carga (Locust/k6) |

## 10.6 Métricas de segurança

| Métrica | Meta |
|---------|------|
| Taxa de vazamento de acesso (E2a) | 0 |
| Vazamento residual na anonimização | 0 para entidades do dicionário; < 0,5% para entidades não catalogadas (com bloqueio pelo verificador) |
| % de pesquisas externas com aprovação registrada | 100% |
| % de requisições com *trace* completo de auditoria | 100% |
| Tempo de detecção (Wazuh) de padrão de sondagem | ≤ 5 min |
| Segredos detectados no repositório após CI | 0 |
| Integridade da cadeia de auditoria | 100% verificada diariamente |
| Cobertura de testes de política OPA | ≥ 90% das regras |

## 10.7 Instrumentação

- **Langfuse** (auto-hospedado) para *traces* de LLM (prompts, *chunks*, latências, custo em *tokens*) — com mascaramento ativado.
- **Prometheus/Grafana**: painéis "Qualidade", "Desempenho", "Segurança", "Conhecimento" (lacunas, documentos mais citados).
- Execução do *golden set* no CI a cada mudança de prompt, modelo ou *chunking* (teste de regressão de qualidade).
