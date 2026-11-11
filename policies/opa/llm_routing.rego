# Roteamento de inferência entre STI (SRV-3) e LMISup/UnB — ADR-017, doc 06 §6.13
# Consultada pelo llm-gateway a cada requisição. A classificação do contexto vem
# dos metadados dos chunks e das evidências (RLS/catálogo), nunca do LLM.
#
# Entrada esperada:
# {
#   "task": "triagem" | "intencao" | "embedding" | "rerank" | "sintese" | "planejamento"
#           | "verificacao" | "runbook" | "avaliacao" | "ajuste_fino" | "reindexacao",
#   "context_classifications": ["INTERNO", "CONFIDENCIAL"],   # de pergunta, chunks e evidências
#   "lmisup": {"healthy": true, "breaker_open": false}
# }
package llm.routing

import rego.v1

levels := {"PUBLICO": 0, "INTERNO": 1, "CONFIDENCIAL": 2, "RESTRITO": 3}

teto_lmisup := 2 # CONFIDENCIAL

caminho_critico := {"triagem", "intencao", "embedding", "rerank"}

lote := {"avaliacao", "ajuste_fino", "reindexacao"}

interativas := {"sintese", "planejamento", "verificacao", "runbook"}

# Classificação desconhecida ou ausente conta como RESTRITO (falha fechada)
nivel(c) := levels[c]

nivel(c) := 3 if not levels[c]

classificacao_informada if is_array(input.context_classifications)

max_nivel := 3 if not classificacao_informada

else := 0 if count(input.context_classifications) == 0

else := max({nivel(c) | some c in input.context_classifications})

lmisup_disponivel if {
	input.lmisup.healthy == true
	not input.lmisup.breaker_open == true
	not data.flags.lmisup_disabled
}

tarefas := (caminho_critico | lote) | interativas

tarefa_conhecida if input.task in tarefas

pode_ir_ao_lmisup if {
	max_nivel <= teto_lmisup
	not input.task in caminho_critico
	tarefa_conhecida
}

route := "lmisup" if {
	pode_ir_ao_lmisup
	lmisup_disponivel
} else := "fila" if {
	pode_ir_ao_lmisup
	input.task in lote
} else := "sti"

contingencia if {
	route == "sti"
	pode_ir_ao_lmisup
	input.task in interativas
}

reason := "conteudo_acima_do_teto" if max_nivel > teto_lmisup

else := "caminho_critico" if input.task in caminho_critico

else := "tarefa_desconhecida" if not tarefa_conhecida

else := "lmisup_indisponivel" if not lmisup_disponivel

else := "preferencial"

decision := {
	"route": route,
	"contingencia": contingencia,
	"reason": reason,
	"max_classification": max_nivel,
}

default contingencia := false
