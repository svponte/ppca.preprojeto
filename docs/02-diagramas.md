# 02 — Diagramas

Diagramas em Mermaid (renderizam no VS Code com a extensão *Markdown Preview Mermaid Support* e nativamente no GitLab/Gitea/GitHub).

## 2.1 Diagrama de componentes

```mermaid
flowchart LR
    subgraph Canais
        UI[Interface Web]
        VSC[VS Code<br/>Claude Code / Codex<br/>via MCP]
        CLI[CLI dbai<br/>MobaXterm]
    end

    subgraph SRV1["SRV-1 — Aplicação"]
        PRX[Traefik<br/>TLS + WAF]
        KC[Keycloak<br/>SSO / OIDC]
        API[API Gateway<br/>FastAPI]
        OPA[OPA<br/>PDP]
        AG[Agent Service<br/>LangGraph]
        RET[Retrieval Service<br/>LlamaIndex]
        TOOL[Tool Service<br/>SQL RO / logs / métricas]
        EXT[External Search Gateway<br/>Anonimização + DLP]
        ING[Ingestion Worker]
        KW[Knowledge Writer]
        ORQ[Event Orchestrator<br/>níveis 0–3]
        EXE[Action Executor<br/>catálogo de runbooks]
        LOGP[Log Processor<br/>máscara + padrões]
        GIT[(Gitea<br/>Markdown)]
        VLT[Vault]
        MON[Prometheus / Grafana<br/>Loki / Langfuse]
    end

    subgraph SRV2["SRV-2 — Dados"]
        PG[(PostgreSQL 16<br/>+ pgvector<br/>ragdb + ops.event_queue)]
        AUD[(auditdb<br/>append-only)]
    end

    subgraph SRV3["SRV-3 — Inferência (sem Internet)"]
        LLMGW[LLM Gateway]
        OLL[Ollama<br/>LLM / Embedding / Reranker]
    end

    subgraph Alvos["Ambientes administrados"]
        TPG[(PostgreSQL<br/>PROD / HML / DEV)]
        TSQL[(SQL Server<br/>PROD / HML / DEV)]
        ZBX[Zabbix / Prometheus<br/>Logs]
    end

    WAZ[Wazuh SIEM]
    LMIS[LMISup/UnB<br/>avaliação — dados<br/>sintéticos/anonimizados]
    TEAMS[Teams<br/>notificação / aprovação]
    AD[(Active Directory<br/>LDAP)]
    WEB((Internet<br/>fontes permitidas))

    UI & VSC & CLI --> PRX --> API
    KC --- AD
    API -- valida JWT --> KC
    API -- decisão --> OPA
    API --> AG
    AG --> RET --> PG
    AG --> TOOL
    TOOL -- credenciais dinâmicas --> VLT
    TOOL -- somente leitura --> TPG & TSQL & ZBX
    AG -- com aprovação --> EXT -- proxy de saída --> WEB
    AG & RET & ING & KW --> LLMGW --> OLL
    GIT -- webhook --> ING --> PG
    KW -- merge request --> GIT
    API & AG & TOOL & EXT --> AUD
    ZBX -- webhook --> ORQ
    TPG & TSQL -- Fluent Bit / XE --> LOGP
    LOGP -- eventos --> PG
    LOGP -- zabbix_sender --> ZBX
    PG -- fila --> ORQ
    ORQ --> TOOL
    ORQ --> LLMGW
    ORQ <--> TEAMS
    ORQ -- ação autorizada --> EXE
    EXE -- aiops_executor.vault --> TPG & TSQL
    ORQ & EXE --> AUD
    OLL -. pesos avaliados .- LMIS
    AUD --> WAZ
    SRV1 -. métricas .-> MON
```

## 2.2 Diagrama de implantação (protótipo)

```mermaid
flowchart TB
    subgraph DMZ["Zona de acesso"]
        U[Usuários DBA/AD]
    end
    subgraph APP["VLAN Aplicação — SRV-1"]
        direction LR
        c1[traefik] --- c2[keycloak] --- c3[api] --- c4[agent] --- c5[retrieval]
        c6[tools] --- c7[ext-search] --- c8[ingestion] --- c9[gitea] --- c10[vault] --- c11[opa]
    end
    subgraph DATA["VLAN Dados — SRV-2"]
        d1[(ragdb)] --- d2[(auditdb)]
    end
    subgraph GPU["VLAN Inferência — SRV-3"]
        g1[ollama] --- g2[llm-gateway]
    end
    subgraph OUT["Saída controlada"]
        px[Proxy HTTP de saída<br/>allowlist de domínios]
    end
    U -- HTTPS 443 --> c1
    APP -- 5432 mTLS --> DATA
    APP -- 11434 mTLS --> GPU
    c7 -- 3128 --> px
    GPU -. sem rota .-x px
```

Regras de *firewall* resumidas:

| Origem | Destino | Porta | Observação |
|--------|---------|-------|------------|
| Usuários | SRV-1 | 443 | Única porta exposta |
| SRV-1 | SRV-2 | 5432 | TLS obrigatório (`hostssl` + certificado cliente) |
| SRV-1 | SRV-3 | 11434 (via llm-gateway 8443) | mTLS |
| SRV-1 (`tool-service`) | Bancos alvo | 5432 / 1433 | Somente a partir do IP do tool-service |
| SRV-1 (`ext-search-gateway`) | Proxy de saída | 3128 | Allowlist de domínios |
| Zabbix | SRV-1 (`event-orchestrator`) | 443 | *Webhook* de eventos |
| SRV-1 (`action-executor`) | Bancos alvo / agentes de monitoramento | 5432 / 1433 / 10050 | Somente a partir do IP do executor; credencial `aiops_executor.vault` |
| Servidores PostgreSQL (Fluent Bit) | SRV-1 (`log-processor`) | 24224 (TLS) | Envio de logs |
| SRV-1 (`log-processor`) | Zabbix server | 10051 | `zabbix_sender` (itens *trapper*) |
| Estação de *staging* | LMISup/UnB | conforme o laboratório | Somente dados sintéticos/anonimizados e pesos; nenhum acesso do LMISup à rede de produção |
| SRV-3 | Internet | — | **Bloqueado** |

## 2.3 Fluxo de dados da ingestão

```mermaid
sequenceDiagram
    autonumber
    participant DBA as DBA (VS Code)
    participant GIT as Gitea
    participant CI as CI (lint + segredos)
    participant ING as Ingestion Worker
    participant LLM as Ollama
    participant PG as ragdb

    DBA->>GIT: push / merge request (Markdown)
    GIT->>CI: pipeline
    CI->>CI: markdownlint, gitleaks, validação de front-matter
    CI-->>GIT: aprovado
    GIT->>ING: webhook (commit SHA)
    ING->>GIT: diff de arquivos alterados
    ING->>ING: parse + classificação + mascaramento
    ING->>ING: chunking por seção Markdown
    ING->>LLM: embeddings (bge-m3)
    ING->>PG: upsert document / chunk (transação por arquivo)
    ING->>PG: marca versões anteriores como superseded
```
