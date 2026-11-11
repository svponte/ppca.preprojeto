package llm.routing_test

import rego.v1

import data.llm.routing

ok := {"healthy": true, "breaker_open": false}

fora := {"healthy": false, "breaker_open": true}

req(task, cls, lm) := {"task": task, "context_classifications": cls, "lmisup": lm}

test_sintese_confidencial_vai_ao_lmisup if {
	routing.route == "lmisup" with input as req("sintese", ["INTERNO", "CONFIDENCIAL"], ok)
}

test_conteudo_restrito_fica_na_sti if {
	routing.route == "sti" with input as req("sintese", ["INTERNO", "RESTRITO"], ok)
	not routing.contingencia with input as req("sintese", ["RESTRITO"], ok)
}

test_classificacao_desconhecida_fica_na_sti if {
	routing.route == "sti" with input as req("sintese", ["SECRETO"], ok)
}

test_classificacao_ausente_fica_na_sti if {
	routing.route == "sti" with input as {"task": "sintese", "lmisup": ok}
}

test_triagem_sempre_na_sti if {
	routing.route == "sti" with input as req("triagem", ["PUBLICO"], ok)
}

test_embedding_sempre_na_sti if {
	routing.route == "sti" with input as req("embedding", [], ok)
}

test_contencao_degrada_para_contingencia if {
	routing.route == "sti" with input as req("sintese", ["INTERNO"], fora)
	routing.contingencia with input as req("sintese", ["INTERNO"], fora)
	routing.reason == "lmisup_indisponivel" with input as req("sintese", ["INTERNO"], fora)
}

test_kill_switch_degrada if {
	routing.route == "sti" with input as req("planejamento", ["INTERNO"], ok)
		with data.flags.lmisup_disabled as true
}

test_lote_em_contencao_vai_para_fila if {
	routing.route == "fila" with input as req("avaliacao", ["CONFIDENCIAL"], fora)
}

test_lote_restrito_nunca_vai_ao_lmisup if {
	routing.route == "sti" with input as req("ajuste_fino", ["RESTRITO"], ok)
}

test_tarefa_desconhecida_fica_na_sti if {
	routing.route == "sti" with input as req("qualquer", ["PUBLICO"], ok)
}

test_lmisup_sem_status_conta_como_indisponivel if {
	routing.route == "sti" with input as {"task": "sintese", "context_classifications": ["INTERNO"]}
}
