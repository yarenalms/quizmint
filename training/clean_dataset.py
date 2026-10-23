"""Ham veri setini temizler: eksik alanları, yazım hatalı türleri, geçersiz test sorularını ve tekrarları ayıklar.

Kullanım: python clean_dataset.py data/ders_dataset_raw.json data/ders_dataset_clean.json
"""
import json
import sys
from collections import Counter

TYPE_FIX = {"açık_uçlu": "açık uçlu", "açık uclu": "açık uçlu", "açık ulu": "açık uçlu"}


def clean(records):
    report = Counter()
    seen = set()
    out = []
    for r in records:
        q, ctx, ans = r.get("question"), r.get("context"), r.get("answer")
        if not q or not ctx or not ans:
            report["eksik alan"] += 1
            continue
        t = TYPE_FIX.get(r.get("type"), r.get("type"))
        if t is None:
            t = "çoktan seçmeli" if r.get("options") else "açık uçlu"
        if t != r.get("type"):
            report["tür düzeltildi"] += 1
        if t == "çoktan seçmeli":
            opts = r.get("options") or []
            if len(opts) != 4 or len(set(opts)) != 4 or ans not in opts:
                report["geçersiz test sorusu"] += 1
                continue
        key = (ctx.strip(), q.strip())
        if key in seen:
            report["tekrar"] += 1
            continue
        seen.add(key)
        item = {"context": ctx.strip(), "question": q.strip(), "answer": ans.strip(), "type": t}
        if t == "çoktan seçmeli":
            item["options"] = r["options"]
        out.append(item)
    return out, report


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    data = json.load(open(src, encoding="utf-8"))
    cleaned, report = clean(data)
    json.dump(cleaned, open(dst, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"Ham: {len(data)}  Temiz: {len(cleaned)}")
    for k, v in report.items():
        print(f"  {k}: {v}")
    print("Türler:", dict(Counter(r["type"] for r in cleaned)))
