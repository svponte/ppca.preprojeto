package aiops.action_test

import rego.v1

import data.aiops.action

acao := {
	"action_id": "encerrar_idle_in_transaction",
	"enabled": true,
	"categories": ["sessao_idle_in_transaction"],
	"levels": {"DEV": 1, "HML": 1, "PROD": 2},
	"reversible": true,
	"max_per_hour": 3,
}

evento(env) := {"environment": env, "triage": {"categoria": "sessao_idle_in_transaction"}}

senior := {"sub": "s", "groups": ["GG-DBA-Senior"], "mfa": true}

pleno := {"sub": "p", "groups": ["GG-DBA-Pleno"], "mfa": true}

junior := {"sub": "j", "groups": ["GG-DBA-Junior"], "mfa": true}

base(env) := {"stage": "decide", "event": evento(env), "action": acao, "recent_runs": 0}

exec(env, approval) := object.union(base(env), {"stage": "execute", "approval": approval})

test_hml_nivel_1_executa if {
	action.mode == "executar" with input as base("HML")
}

test_prod_nivel_2_pede_aprovacao if {
	action.mode == "pedir_aprovacao" with input as base("PROD")
}

test_prod_sem_aprovacao_nao_executa if {
	not action.allow_execute with input as object.union(base("PROD"), {"stage": "execute"})
}

test_prod_aprovado_por_senior_executa if {
	action.allow_execute with input as exec("PROD", {"user": senior, "channel": "teams"})
}

test_prod_aprovado_por_pleno_nao_executa if {
	not action.allow_execute with input as exec("PROD", {"user": pleno, "channel": "web"})
}

test_aprovacao_sem_mfa_invalida if {
	not action.allow_execute with input as exec("PROD", {"user": object.union(senior, {"mfa": false}), "channel": "web"})
}

test_aprovacao_por_mcp_invalida if {
	not action.allow_execute with input as exec("PROD", {"user": senior, "channel": "mcp"})
}

test_hml_nivel_2_aprovado_por_pleno if {
	acao2 := object.union(acao, {"levels": {"HML": 2}})
	inp := object.union(exec("HML", {"user": pleno, "channel": "web"}), {"action": acao2})
	action.allow_execute with input as inp
}

test_hml_nivel_2_junior_nao_aprova if {
	acao2 := object.union(acao, {"levels": {"HML": 2}})
	inp := object.union(exec("HML", {"user": junior, "channel": "web"}), {"action": acao2})
	not action.allow_execute with input as inp
}

test_nivel_3_so_informa if {
	inp := object.union(base("PROD"), {"action": object.union(acao, {"levels": {"PROD": 3}})})
	action.mode == "informar" with input as inp
}

test_nivel_3_nunca_executa_mesmo_aprovado if {
	inp := object.union(exec("PROD", {"user": senior, "channel": "web"}), {"action": object.union(acao, {"levels": {"PROD": 3}})})
	not action.allow_execute with input as inp
}

com_niveis(levels) := object.union(object.remove(acao, ["levels"]), {"levels": levels})

# object.union mescla objetos recursivamente; para trocar a ação inteira, remove-se a chave antes
com_acao(inp, a) := object.union(object.remove(inp, ["action"]), {"action": a})

test_ambiente_sem_nivel_so_informa if {
	inp := com_acao(base("DEV"), com_niveis({"PROD": 2}))
	action.mode == "informar" with input as inp
}

test_categoria_fora_do_runbook_so_informa if {
	inp := object.union(base("HML"), {"event": {"environment": "HML", "triage": {"categoria": "lock_bloqueante"}}})
	action.mode == "informar" with input as inp
}

test_acao_desabilitada_so_informa if {
	inp := object.union(base("HML"), {"action": object.union(acao, {"enabled": false})})
	action.mode == "informar" with input as inp
}

test_reversibilidade_ausente_nao_e_automatica if {
	inp := com_acao(base("HML"), object.remove(acao, ["reversible"]))
	action.mode == "pedir_aprovacao" with input as inp
}

test_sem_contagem_de_execucoes_bloqueia if {
	action.mode == "informar" with input as object.remove(base("HML"), ["recent_runs"])
}

test_irreversivel_nivel_1_vira_aprovacao if {
	inp := object.union(base("HML"), {"action": object.union(acao, {"reversible": false})})
	action.mode == "pedir_aprovacao" with input as inp
}

test_disjuntor_bloqueia if {
	inp := object.union(base("HML"), {"recent_runs": 3})
	action.mode == "informar" with input as inp
}

test_kill_switch_bloqueia if {
	action.mode == "informar" with input as base("HML") with data.flags.actions_disabled as true
}

test_kill_switch_bloqueia_execucao_aprovada if {
	not action.allow_execute with input as exec("PROD", {"user": senior, "channel": "web"})
		with data.flags.actions_disabled as true
}

test_primeira_execucao_exige_dry_run if {
	inp := object.union(base("HML"), {"stage": "execute", "first_run_of_version": true})
	not action.allow_execute with input as inp
}

test_primeira_execucao_em_dry_run_permitida if {
	inp := object.union(base("HML"), {"stage": "execute", "first_run_of_version": true, "dry_run": true})
	action.allow_execute with input as inp
}
