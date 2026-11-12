"""Leitor mínimo do BibTeX exportado pelo Web of Science (sem dependências externas)."""
import re, sys, json

def parse(path):
    txt = open(path, encoding="utf-8").read()
    recs = []
    for m in re.finditer(r"@(\w+)\{\s*([^,]+),", txt):
        start = m.end()
        # find end of entry by brace depth
        depth, i = 1, m.end() - 1
        # entry opens at the '{' after type
        i = txt.index("{", m.start())
        depth = 0
        j = i
        while True:
            c = txt[j]
            if c == "{": depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0: break
            j += 1
        body = txt[start:j]
        rec = {"type": m.group(1).lower(), "id": m.group(2).strip()}
        k = 0
        while True:
            fm = re.compile(r"\s*([A-Za-z\-]+)\s*=\s*\{").match(body, k)
            if not fm: break
            name = fm.group(1).lower()
            d, p = 1, fm.end()
            while d:
                if body[p] == "{": d += 1
                elif body[p] == "}": d -= 1
                p += 1
            val = re.sub(r"\s+", " ", body[fm.end():p - 1]).strip()
            rec[name] = val
            k = p
            cm = re.compile(r"\s*,").match(body, k)
            if cm: k = cm.end()
        recs.append(rec)
    return recs

if __name__ == "__main__":
    recs = parse(sys.argv[1])
    json.dump(recs, open(sys.argv[2], "w"), ensure_ascii=False, indent=1)
    print(len(recs))
