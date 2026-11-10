# Política de autorização da plataforma RAG-DBA (Open Policy Agent, Rego v1)
# Entrada esperada:
# {
#   "user":   {"sub": "...", "groups": ["GG-DBA-Pleno"], "mfa": true},
#   "action": "ask" | "tool" | "external_search" | "approve_runbook" | "read_audit",
#   "channel": "web" | "mcp" | "cli",
#   "tool":   {"name": "sql_somente_leitura", "query_id": "top_queries_cpu",
#              "server_env": "PROD", "read_only": true},
#   "time":   {"hour": 14, "weekday": 2}
# }
package rag.authz

import rego.v1

default allow := false

levels := {"PUBLICO": 0, "INTERNO": 1, "CONFIDENCIAL": 2, "RESTRITO": 3}

level_name := {0: "PUBLICO", 1: "INTERNO", 2: "CONFIDENCIAL", 3: "RESTRITO"}

# Mapeamento AD -> perfil (RBAC) + atributos (ABAC)
profiles := {
	"GG-DBA-Estagiario": {"role": "dba_leitor", "clearance": 1, "envs": ["DEV"]},
	"GG-DBA-Junior": {"role": "dba_operador", "clearance": 1, "envs": ["DEV", "HML"]},
	"GG-DBA-Pleno": {"role": "dba_operador", "clearance": 2, "envs": ["DEV", "HML", "PROD"]},
	"GG-DBA-Senior": {"role": "dba_senior", "clearance": 3, "envs": ["DEV", "HML", "PROD"]},
	"GG-Seguranca": {"role": "auditor", "clearance": 0, "envs": []},
}

user_profiles contains p if {
	some g in input.user.groups
	p := profiles[g]
}

roles contains p.role if some p in user_profiles

# Maior clearance entre os grupos do usuário
raw_clearance := max({p.clearance | some p in user_profiles}) if count(user_profiles) > 0

else := -1

# MFA obrigatório para clearance >= CONFIDENCIAL; sem MFA, rebaixa para INTERNO
mfa_clearance := raw_clearance if input.user.mfa == true

else := min({raw_clearance, 1})

# ADR-007: canal MCP (assistentes de código com modelo externo) limitado a INTERNO
effective_clearance := min({mfa_clearance, 1}) if input.channel == "mcp"

else := mfa_clearance

environments contains e if {
	some p in user_profiles
	some e in p.envs
}

# Kill switches (dados carregados via bundle: data.flags)
external_search_enabled if not data.flags.external_search_disabled

tools_enabled if not data.flags.tools_disabled

# ---------------- Regras ----------------

allow if {
	input.action == "ask"
	effective_clearance >= 0
	some r in roles
	r != "auditor"
}

# Ferramentas: somente leitura, ambiente permitido; PROD exige pleno+
allow if {
	input.action == "tool"
	tools_enabled
	input.channel != "mcp"
	input.tool.read_only == true
	input.tool.server_env in environments
	prod_ok
}

prod_ok if input.tool.server_env != "PROD"

prod_ok if {
	input.tool.server_env == "PROD"
	effective_clearance >= 2
}

allow if {
	input.action == "external_search"
	external_search_enabled
	input.channel == "web"
	some r in roles
	r in {"dba_operador", "dba_senior"}
}

allow if {
	input.action == "approve_runbook"
	"dba_senior" in roles
}

allow if {
	input.action == "read_audit"
	"auditor" in roles
}

# ---------------- Obrigações devolvidas ao chamador ----------------

obligations := {
	"clearance": level_name[effective_clearance],
	"environments": sort([e | some e in environments]),
	"mask_level": mask_level,
	"require_supervisor_for_external": "dba_leitor" in roles,
} if effective_clearance >= 0

mask_level := "none" if effective_clearance == 3

else := "network_and_accounts" if effective_clearance == 2

else := "strict"

decision := {"allow": allow, "obligations": obligations} if effective_clearance >= 0

else := {"allow": false, "obligations": {}}
