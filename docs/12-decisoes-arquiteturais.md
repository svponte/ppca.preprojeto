# 12 — Registro de Decisões Arquiteturais (ADRs)

Formato: contexto → decisão → consequências. Novas decisões são acrescentadas ao final; decisões substituídas recebem status "Substituída por ADR-xxx".

---

## ADR-001 — Inferência 100% local (Ollama)
**Status**: Aceita (complementada por ADR-018)
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
**Status**: Aceita (complementada por ADR-011)
**Contexto**: Requisito de aprender com incidentes; risco de o modelo memorizar dados sensíveis; custo de GPU.
**Decisão**: Aprendizado = runbooks gerados, revisados e versionados no Git + reindexação.
**Consequências**: (+) auditável e reversível; (−) depende de revisão humana (gargalo potencial — medido no doc 08).

---

> As ADRs 010–016 registram as decisões da revisão de 2026-11-11 (análise do capítulo 13 de *Competente o Suficiente* e da infraestrutura do LMISup/UnB).

## ADR-010 — Avaliação no LMISup, operação na STI
**Status**: Substituída por ADR-017 e depois por ADR-018
**Contexto**: O LMISup/UnB (Laboratório Multiusuário de IA e Supercomputação, com participação da STI) oferece cluster de GPUs de data center. A operação diária, porém, precisa de disponibilidade contínua e de dados que não devem sair do domínio de segurança da STI. O laboratório ainda não publicou políticas de uso, de dados nem de acesso.
**Decisão**: O LMISup é usado para **avaliação** (comparação de modelos, execução do *golden set*, experimentos de ablação) e, **somente se necessário**, para ajuste fino (ADR-011). A operação roda no SRV-3 da STI. Para o LMISup vão apenas dados sintéticos ou anonimizados; metadados reais de produção não saem da STI.
**Consequências**: (+) a solução não depende do laboratório para funcionar; experimentos com modelos grandes ficam viáveis sem GPU própria; (−) é preciso confirmar com o LMISup (lmisup@unb.br) as condições de acesso, a modalidade de uso (filas em lote ou serviço de inferência) e a liberdade de levar os pesos derivados para a STI; riscos registrados no doc 09.

## ADR-011 — Modelos em dois níveis; tamanho definido pela avaliação; ajuste fino condicional
**Status**: Aceita
**Contexto**: A triagem de eventos é uma tarefa pequena e fechada; a interação com o analista exige raciocínio e chamada de ferramentas. Modelos menores custam menos memória de GPU, mas têm limites em fluxos longos. Fatos da infraestrutura mudam todos os dias e são sensíveis.
**Decisão**: (1) dois níveis de modelo: um **pequeno** para classificação e triagem de eventos e um **maior** para conversa, planejamento e síntese; (2) os tamanhos não são premissa: saem da avaliação (doc 10) e cabem na GPU da STI; (3) o modelo de partida é um modelo de pesos abertos sem ajuste; o **ajuste fino é opcional**, feito só se a avaliação mostrar lacuna, e restrito a vocabulário de DBA em português, estilo e formato de saída (incluindo chamadas de ferramenta); (4) **fatos nunca entram nos pesos**: o estado atual vem de ferramentas (ADR-012) e o conhecimento documental vem do RAG.
**Consequências**: (+) os pesos não contornam o controle de acesso — o que estivesse nos pesos ficaria visível a qualquer usuário, sem RLS; nada a retreinar quando o ambiente muda; (−) se a avaliação indicar ajuste fino, surge um ciclo de treino no LMISup com dados internos (ADR-018) e uma licença do modelo base compatível com derivados.

## ADR-012 — Enquadramento AIOps; estado atual por consulta ao vivo, RAG para conhecimento não estruturado
**Status**: Aceita
**Contexto**: Com monitoramento, logs e ações automatizadas, a proposta deixou de ser só uma base de conhecimento com RAG. Metadados de infraestrutura (permissões, tamanhos, jobs, parâmetros vigentes) são estruturados e mudam continuamente.
**Decisão**: A proposta se enquadra em **AIOps** (*Artificial Intelligence for IT Operations*) aplicado à administração de bancos de dados. O estado atual dos ambientes é obtido **ao vivo** pelas ferramentas do catálogo (ADR-006), com credenciais somente leitura; o RAG fica restrito ao conhecimento não estruturado (procedimentos, runbooks, políticas, histórico de incidentes). "RAG" e "agentes com ferramentas" permanecem como termos do corpo do texto e palavras-chave.
**Consequências**: (+) respostas sobre o estado atual não ficam desatualizadas; o índice não precisa replicar o catálogo dos SGBDs; o nome descreve a proposta inteira; (−) mais dependência das ferramentas e de um modelo bom em *tool calling*.

## ADR-013 — Operação orientada a eventos com fila no PostgreSQL
**Status**: Aceita
**Contexto**: O Zabbix já detecta incidentes de forma determinística; colocar o LLM no laço de detecção traria latência, custo e falsa confiança.
**Decisão**: A detecção continua no Zabbix e no pipeline de logs (ADR-016). Eventos chegam por *webhook* a uma fila em tabela PostgreSQL (`ops.event_queue`, consumida com `FOR UPDATE SKIP LOCKED`). O `event-orchestrator` (daemon) enriquece o evento com ferramentas somente leitura e pede ao modelo pequeno uma **classificação restrita** (JSON validado contra enum). A decisão sobre o que fazer é do motor de políticas, em código (doc 13).
**Consequências**: (+) sem infraestrutura nova de filas; deduplicação, reprocessamento e histórico no próprio banco; (−) *throughput* limitado ao de uma fila em tabela — suficiente para o volume de eventos de uma equipe; migrar para Redis Streams/RabbitMQ se necessário (roadmap).

## ADR-014 — Autonomia graduada e executor isolado
**Status**: Aceita
**Contexto**: Executar ações a partir do monitoramento reduz tempo de resposta, mas um LLM pode ser manipulado (*prompt injection* por logs e mensagens de erro) ou simplesmente errar com alta confiança.
**Decisão**: Toda ação pertence a um **catálogo de runbooks** versionado no Git, com nível de autonomia: **0** = informar; **1** = ação reversível e idempotente executada automaticamente, com limites; **2** = ação com impacto, executada só após aprovação humana; **3** = nunca automatizada (DDL, *failover*, alteração de permissões, troca de senhas, `DROP`). O `action-executor` é um processo separado, com credencial própria (`aiops_executor.vault`) e privilégio mínimo; executa apenas itens do catálogo com parâmetros validados por esquema, *timeout*, modo *dry-run*, limite de ações por hora, disjuntor e *kill switch*. O LLM **nunca gera comando livre**: escolhe um item permitido para aquele tipo de evento, e o OPA confirma (`policies/opa/action_authz.rego`). Uma ação só é promovida de nível quando o histórico de aprovações mostrar concordância consistente.
**Consequências**: (+) mesmo um modelo manipulado só consegue escolher entre ações já permitidas; implantação gradual mensurável; (−) o catálogo exige manutenção pela equipe; o princípio P6 (doc 01) passa a admitir escrita, só por este caminho.

## ADR-015 — Verificação pós-ação e auditoria de cada decisão
**Status**: Aceita
**Contexto**: Código de retorno zero não prova que o problema foi resolvido; para a pesquisa, é preciso reconstruir cada decisão.
**Decisão**: Cada runbook do catálogo declara uma **condição de sucesso** verificável (ex.: "o bloqueio deixou de existir", "o agente responde"), conferida pelo executor depois de agir; falha na verificação escala para humano. Cada execução registra evento, contexto enviado ao modelo, resposta, decisão da política, aprovação, ação, resultado e verificação em `ops.action_run`, com eventos `aiops.*` na auditoria *append-only* (`auditdb`).
**Consequências**: (+) rastreabilidade completa e conjunto de dados para a avaliação (doc 10); (−) cada runbook automatizável precisa de uma verificação escrita e testada.

## ADR-016 — Pipeline de logs em funil
**Status**: Aceita
**Contexto**: O Zabbix lê arquivos de log (`log[]`, `logrt[]`, `eventlog[]`) apenas linha a linha e por regex: não trata mensagens de várias linhas, não agrupa padrões nem correlaciona. Enviar todas as linhas ao LLM é inviável e arriscado (senhas e dados pessoais nos logs).
**Decisão**: Coleta com Fluent Bit (ou Vector) nos servidores; fontes estruturadas (`jsonlog` no PostgreSQL 16, `csvlog` no PostgreSQL 14, Extended Events e `sys.xp_readerrorlog` no SQL Server); **mascaramento antes de qualquer armazenamento**; agrupamento em modelos de mensagem (*fingerprint*); regras determinísticas. Só padrões **novos ou anômalos** chegam ao modelo pequeno; métricas por padrão voltam ao Zabbix (`zabbix_sender`), e eventos entram na mesma fila do ADR-013 (doc 14).
**Consequências**: (+) volume baixo chegando ao LLM; alertas continuam centralizados no Zabbix; (−) componente novo a operar; revisão de `log_statement` e de parâmetros de log nos servidores.

## ADR-017 — Dois sítios de inferência (STI e LMISup) com degradação para a STI
**Status**: Substituída por ADR-018
**Contexto**: O projeto é destinado ao atendimento da STI, que participa do LMISup/UnB; considera-se acesso amplo ao laboratório, para avaliação, ajuste fino e inferência. O laboratório, porém, é multiusuário e está sujeito a **contenção intempestiva**: preempção de jobs, manutenção, prioridade de outros projetos ou queda de capacidade sem aviso.
**Decisão**:
1. **Dois sítios de inferência**: SRV-3 (STI) e LMISup. O `llm-gateway` da STI é o único ponto de entrada e decide a rota.
2. **Caminho crítico sempre na STI**: modelo pequeno de triagem, embeddings, reranker e um **modelo de interação de contingência** rodam no SRV-3. A operação orientada a eventos (doc 13, níveis 0 a 2) e a ingestão **nunca dependem do LMISup**.
3. **LMISup como capacidade preferencial**: modelo maior de interação (rota preferencial quando disponível), avaliação, ajuste fino (ADR-011) e cargas em lote (reindexação em massa, execução do *golden set*).
4. **Degradação automática**: o `llm-gateway` mantém *health check*, *timeout* e disjuntor para a rota LMISup. Em contenção, as requisições interativas passam para o modelo de contingência local, e a resposta informa que foi gerada em modo de contingência. Cargas em lote ficam em fila e são retomadas a partir de *checkpoints*.
5. **Dados**: o LMISup é tratado como domínio institucional, mediante acordo formal STI–LMISup (finalidade, retenção nula de prompts e respostas, acesso restrito ao endpoint da plataforma, mTLS). **Teto de classificação CONFIDENCIAL** para contexto enviado ao LMISup; conteúdo RESTRITO (IPs, contas de serviço, procedimentos de segurança) só é processado no SRV-3 (`policies/opa/llm_routing.rego`).
6. **Mesmos pesos, dois lugares**: modelos avaliados ou ajustados no LMISup são importados para a STI pelo processo controlado (verificação de *hash*), para que a contingência e a rota preferencial tenham comportamento conhecido.
**Consequências**: (+) qualidade do modelo maior no uso normal sem tornar a operação dependente do laboratório; uso de dados reais na avaliação, dentro do acordo; (−) dois ambientes para operar e monitorar; o modelo de contingência também precisa atingir um mínimo aceitável na avaliação (doc 10); acordo STI–LMISup é pré-requisito.

## ADR-018 — LMISup gera o modelo; produção em servidor dimensionado da STI
**Status**: Aceita (substitui ADR-010 e ADR-017)
**Contexto**: O LMISup e os servidores da STI estão no mesmo domínio institucional, sem acesso externo. O LMISup pode ser usado sempre que for preciso gerar um modelo, mas é compartilhado: mesmo disponível, não deve hospedar a operação contínua e está sujeito a contenção sem aviso.
**Decisão**:
1. **LMISup = geração do modelo**, a qualquer tempo: seleção e avaliação de modelos de pesos abertos, ajuste fino quando a avaliação indicar (ADR-011), destilação ou quantização para o porte do servidor de produção, e reexecução do *golden set*. Os trabalhos rodam em lote, com *checkpoint*, e podem ser interrompidos e retomados.
2. **Produção = servidor de inferência da STI (SRV-3)**, dimensionado para os modelos gerados (modelo pequeno de triagem, modelo maior de interação, embeddings, reranker). Não há rota de inferência para o LMISup em produção.
3. **Ciclo repetível**: um novo modelo base, novos dados ou queda de qualidade disparam novo ciclo no LMISup → avaliação → importação dos pesos para o SRV-3 por processo controlado (verificação de *hash*) → troca no `llm-gateway` após passar no *golden set*.
4. **Confidencialidade no acesso, não no processamento**: como o processamento ocorre todo dentro da STI, os dados internos podem ser usados sem anonimização na geração e na avaliação do modelo. Os controles de confidencialidade (RLS, OPA, DLP de saída, mascaramento do que o usuário vê, teto INTERNO no MCP — ADR-007, pesquisa externa — ADR-005) tratam do **uso do sistema pelos usuários**.
**Consequências**: (+) a produção não sofre com a contenção do laboratório; dados reais na avaliação aumentam a validade dos resultados; arquitetura de produção com um só sítio; (−) o SRV-3 precisa ser dimensionado (e, se for o caso, adquirido) depois da escolha do modelo; cada novo modelo exige um ciclo completo de avaliação antes da troca.

