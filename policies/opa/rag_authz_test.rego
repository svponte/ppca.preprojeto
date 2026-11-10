package rag.authz_test

import rego.v1

import data.rag.authz

junior := {"sub": "j", "groups": ["GG-DBA-Junior"], "mfa": true}

pleno_sem_mfa := {"sub": "p", "groups": ["GG-DBA-Pleno"], "mfa": false}

senior := {"sub": "s", "groups": ["GG-DBA-Senior"], "mfa": true}

test_junior_pode_perguntar if {
	authz.allow with input as {"user": junior, "action": "ask", "channel": "web"}
}

test_junior_nao_usa_ferramenta_em_prod if {
	not authz.allow with input as {"user": junior, "action": "tool", "channel": "web",
		"tool": {"server_env": "PROD", "read_only": true}}
}

test_junior_usa_ferramenta_em_hml if {
	authz.allow with input as {"user": junior, "action": "tool", "channel": "web",
		"tool": {"server_env": "HML", "read_only": true}}
}

test_ferramenta_de_escrita_negada_ate_para_senior if {
	not authz.allow with input as {"user": senior, "action": "tool", "channel": "web",
		"tool": {"server_env": "DEV", "read_only": false}}
}

test_sem_mfa_rebaixa_para_interno if {
	authz.obligations.clearance == "INTERNO" with input as {"user": pleno_sem_mfa, "action": "ask", "channel": "web"}
}

test_sem_mfa_nao_usa_ferramenta_em_prod if {
	not authz.allow with input as {"user": pleno_sem_mfa, "action": "tool", "channel": "web",
		"tool": {"server_env": "PROD", "read_only": true}}
}

test_mcp_limitado_a_interno_mesmo_para_senior if {
	authz.obligations.clearance == "INTERNO" with input as {"user": senior, "action": "ask", "channel": "mcp"}
}

test_mcp_sem_ferramentas if {
	not authz.allow with input as {"user": senior, "action": "tool", "channel": "mcp",
		"tool": {"server_env": "DEV", "read_only": true}}
}

test_senior_sem_mascara if {
	authz.obligations.mask_level == "none" with input as {"user": senior, "action": "ask", "channel": "web"}
}

test_kill_switch_pesquisa_externa if {
	not authz.allow with input as {"user": senior, "action": "external_search", "channel": "web"}
		with data.flags.external_search_disabled as true
}

test_pesquisa_externa_permitida_para_senior if {
	authz.allow with input as {"user": senior, "action": "external_search", "channel": "web"}
}

test_usuario_sem_grupo_negado if {
	not authz.allow with input as {"user": {"sub": "x", "groups": ["GG-Outro"], "mfa": true}, "action": "ask", "channel": "web"}
}

test_somente_senior_aprova_runbook if {
	not authz.allow with input as {"user": junior, "action": "approve_runbook", "channel": "web"}
	authz.allow with input as {"user": senior, "action": "approve_runbook", "channel": "web"}
}
