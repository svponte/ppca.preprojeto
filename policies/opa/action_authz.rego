# Política de ações automáticas (AIOps) — níveis de autonomia (doc 13, ADR-014)
# Consultada pelo event-orchestrator (decisão) e pelo action-executor (confirmação
# imediatamente antes de executar). O LLM nunca fornece campos desta entrada além
# de `triage.categoria`, já validada contra enum.
#
# Entrada esperada:
# {
#   "stage": "decide" | "execute",
#   "event":  {"environment": "HML", "triage": {"categoria": "sessao_idle_in_transaction"}},
#   "action": {"action_id": "encerrar_idle_in_transaction", "enabled": true,
#              "categories": ["sessao_idle_in_transaction"],
#              "levels": {"DEV": 1, "HML": 1, "PROD": 2},
#              "reversible": true, "max_per_hour": 3},
#   "recent_runs": 0,                     # ops.recent_runs(action_id, server_id)
#   "first_run_of_version": false,        # primeira execução deste commit do catálogo
#   "dry_run": false,
#   "approval": {"user": {"sub": "...", "groups": ["GG-DBA-Senior"], "mfa": true},
#                "channel": "web" | "teams"}       # só no nível 2, stage = execute
# }
package aiops.action

import rego.v1

import data.rag.authz

envs_validos := {"DEV", "HML", "PROD"}

# Kill switch (bundle: data.flags.actions_disabled)
actions_enabled if not data.flags.actions_disabled

env := input.event.environment

# Nível do runbook para o ambiente do evento; ausente ou inválido => 0 (informar)
level := l if {
	env in envs_validos
	l := input.action.levels[env]
	l in {0, 1, 2}
} else := 0

categoria_atendida if input.event.triage.categoria in input.action.categories

catalogo_ok if {
	input.action.enabled == true
	categoria_atendida
}

disjuntor_aberto if input.recent_runs >= input.action.max_per_hour

# Falha fechada: sem contagem de execuções ou sem limite, trata como disjuntor aberto
contagem_informada if is_number(input.recent_runs)

limite_informado if is_number(input.action.max_per_hour)

disjuntor_aberto if not contagem_informada

disjuntor_aberto if not limite_informado

reversivel if input.action.reversible == true

# Irreversível nunca é automático (defesa em profundidade sobre o CHECK do banco)
nivel_efetivo := 2 if {
	level == 1
	not reversivel
} else := level

em_dry_run if input.dry_run == true

reasons contains "kill_switch" if not actions_enabled

reasons contains "fora_do_catalogo_ou_desabilitada" if not catalogo_ok

reasons contains "nivel_0_ou_3" if nivel_efetivo == 0

reasons contains "disjuntor_aberto" if disjuntor_aberto

reasons contains "primeira_execucao_exige_dry_run" if {
	input.stage == "execute"
	input.first_run_of_version == true
	not em_dry_run
}

reasons contains "aprovacao_ausente_ou_invalida" if {
	input.stage == "execute"
	nivel_efetivo == 2
	not aprovacao_valida
}

bloqueios := reasons - {"aprovacao_ausente_ou_invalida", "primeira_execucao_exige_dry_run"}

# ---------------- Modo decidido pelo orquestrador ----------------

mode := "informar" if count(bloqueios) > 0

else := "executar" if nivel_efetivo == 1

else := "pedir_aprovacao"

# ---------------- Confirmação pelo executor ----------------

default allow_execute := false

allow_execute if {
	input.stage == "execute"
	count(reasons) == 0
	nivel_efetivo in {1, 2}
}

# ---------------- Aprovação de nível 2 ----------------
# PROD: dba_senior. DEV/HML: dba_senior ou dba_operador com clearance >= CONFIDENCIAL.
# MFA obrigatório; somente web ou Teams (nunca MCP/CLI).

aprovador_perfis contains p if {
	some g in input.approval.user.groups
	p := authz.profiles[g]
}

aprovador_pode(e) if {
	e == "PROD"
	some p in aprovador_perfis
	p.role == "dba_senior"
}

aprovador_pode(e) if {
	e in {"DEV", "HML"}
	some p in aprovador_perfis
	p.role in {"dba_operador", "dba_senior"}
	p.clearance >= 2
	env in p.envs
}

aprovacao_valida if {
	input.approval.user.mfa == true
	input.approval.channel in {"web", "teams"}
	aprovador_pode(env)
}

decision := {
	"mode": mode,
	"level": nivel_efetivo,
	"allow_execute": allow_execute,
	"reasons": sort([r | some r in reasons]),
}
