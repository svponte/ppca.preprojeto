"""Classificação automática (por palavras-chave) dos registros exportados do Web of Science.

Uso: python classificar_wos.py <savedrecs.bib> <saida.csv>

A classificação é heurística (expressões regulares sobre título e resumo) e serve
apenas para organizar a triagem; a decisão de inclusão é sempre manual.
"""
import csv
import collections
import re
import sys

from parse_wos_bib import parse

DB = [r"database administrat", r"database management system", r"\bDBMS", r"database tuning", r"knob tuning",
      r"database diagnos", r"database operation", r"database metadata", r"data catalog", r"\bdatabase"]
DB_ESPECIFICO = (r"database administrat|database management system|\bDBMS|database tuning|knob|database diagnos|"
                 r"database operation|data catalog|natural language (database|interface)|text-to-sql|nl2sql|\bDBA\b")
RAG = [r"retrieval[- ]augmented", r"\bRAG\b"]
INJ = [r"prompt injection", r"LLM-integrated application"]
SEC = [r"secur", r"privacy", r"leak", r"injection", r"access control", r"confidential", r"poison", r"attack",
       r"membership inference", r"exfiltrat", r"jailbreak", r"on-?premise", r"self-hosted", r"private"]
SEC_INTERSECAO = (r"secur|privacy|leak|injection|access control|confidential|attack|on-?premise|"
                  r"local (large )?language|locally|private")

SUB_BD = collections.OrderedDict([
    ("Tuning/configuração", [r"knob", r"tuning", r"configuration"]),
    ("Diagnóstico/operação", [r"diagnos", r"root cause", r"anomal", r"operation", r"\bDBA\b", r"incident"]),
    ("Text-to-SQL/consulta", [r"text-to-sql", r"text to sql", r"nl2sql", r"natural language (interface|quer)"]),
    ("Otimização de consultas", [r"query optimi", r"query rewrit", r"cardinality", r"index"]),
    ("Catálogo/metadados", [r"metadata", r"data catalog", r"schema"]),
])
SUB_SEG = collections.OrderedDict([
    ("Envenenamento da base", [r"poison", r"corpus manipulat", r"knowledge base attack"]),
    ("Vazamento/privacidade", [r"leak", r"privacy", r"membership inference", r"extraction", r"confidential"]),
    ("Injeção de prompt", [r"prompt injection", r"jailbreak"]),
    ("Controle de acesso", [r"access control", r"permission", r"authoriz", r"role-based"]),
    ("Defesas/robustez", [r"defen", r"robust", r"guard", r"detect", r"mitigat"]),
])


def has(text, pats):
    return any(re.search(p, text, re.I) for p in pats)


def primeiro_autor(autores):
    a = autores.split(" and ")
    return a[0] + (" et al." if len(a) > 1 else "")


def classificar(r):
    t, a = r["title"], r.get("abstract", "")
    ta = t + " " + a
    db, rag, sec, inj = has(ta, DB), has(ta, RAG), has(ta, SEC), has(t, INJ)
    eixos = []
    if db and not (rag and sec and not has(ta, DB[:-1])):
        eixos.append("BD")
    if rag and sec:
        eixos.append("RAG seguro")
    if inj:
        eixos.append("Injeção de prompt")
    if not eixos:
        eixos.append("Outros")
    subs = [k for k, v in SUB_BD.items() if has(ta, v)] if "BD" in eixos else []
    if "RAG seguro" in eixos or "Injeção de prompt" in eixos:
        subs += [k for k, v in SUB_SEG.items() if has(ta, v)]
    intersecao = bool(re.search(DB_ESPECIFICO, ta, re.I) and re.search(SEC_INTERSECAO, ta, re.I))
    return eixos, subs, intersecao


def main(bib, saida):
    recs = parse(bib)
    with open(saida, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["id_wos", "ano", "tipo", "primeiro_autor", "titulo", "veiculo", "doi",
                    "eixo_principal", "eixos", "subtemas", "intersecao_bd_seguranca",
                    "decisao_triagem", "criterio", "observacao"])
        for r in sorted(recs, key=lambda x: (x.get("year", ""), x["title"])):
            eixos, subs, inter = classificar(r)
            w.writerow([r.get("unique-id", r["id"]), r.get("year", ""),
                        "Conferência" if r["type"] == "inproceedings" else "Periódico",
                        primeiro_autor(r.get("author", "")), r["title"],
                        r.get("journal") or r.get("booktitle", ""), r.get("doi", ""),
                        eixos[0], "; ".join(eixos), "; ".join(subs), "Sim" if inter else "",
                        "", "", ""])
    print(len(recs), "registros ->", saida)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
