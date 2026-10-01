#!/usr/bin/env python3
"""原作の禁止語の表を、非公開の層の禁止語の規則(forbidden)に書き出す。

公開リポジトリには語そのものを書かない(docs/architecture/E-content.md §5.2)。このスクリプトも語を持たず、
実行するたびに原作のリポジトリ(非公開)から読み、出力は非公開の層(既定 content/private。gitignore 済み)に置く。

読むもの(原作 /data/ashwell/reforge):
  - CLAUDE.md の「Perception-Truth 原則」の表(Era | 認識 | 絶対に出してはいけない用語)
  - src/ReForge.Core/Data/PerceptionFilter.cs の置き換え(currentEra < N の間に置き換える語 = Era N まで禁止)
同じ語が両方にあれば、長く禁止する方(大きい Era)を取る。

Era は事実の 1 つとして扱う(fact.era.2 … fact.era.5。fact.era.N は fact.era.N-1 を含意する)。
Era 単位の規則は原作どおりの土台で、事実単位の細かい規則(開示の事実ごと)は非公開の層の作者が足す。

書き出すもの(非公開の層の中):
  perception/forbidden.original.json  規則(名札 forbidden.original.eraN)と監査の段(era1 … era4)
  narrative/era-facts.json             Era の事実(--no-facts で書かない。ほかで定義しているとき)

使い方:
  python3 tools/content/extract-forbidden.py [--original /data/ashwell/reforge] [--out content/private] [--no-facts]
  件数だけを表示する(語は表示しない)。
"""
import argparse
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
ERA_MAX = 5


def era_fact(n):
    return f"fact.era.{n}"


def parse_claude_md(text):
    """CLAUDE.md の表 → {語: 解ける Era}。"""
    out = {}
    in_section = False
    for line in text.splitlines():
        if line.startswith("### Perception-Truth"):
            in_section = True
            continue
        if in_section and line.startswith("### "):
            break
        if not in_section or not line.startswith("|"):
            continue
        cols = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cols) < 3:
            continue
        era = cols[0]
        m = re.fullmatch(r"(\d)(?:-(\d))?", era)
        if m:
            until = int(m.group(2) or m.group(1)) + 1
        else:
            m = re.fullmatch(r"<\s*(\d)", era)
            if not m:
                continue
            until = int(m.group(1))
        cell = re.sub(r"[（(][^）)]*[）)]", "", cols[2])
        for w in re.split(r"[、,]", cell):
            w = w.strip()
            if "等の" in w:
                w = w.split("等の")[0]
            if w and not re.fullmatch(r"[-—―─ ]+", w):
                out[w] = max(out.get(w, 0), until)
    return out


def parse_filter_cs(text):
    """PerceptionFilter.cs の置き換え → {語: 解ける Era}。"""
    out = {}
    until = None
    for line in text.splitlines():
        m = re.search(r"currentEra\s*<\s*(\d)", line)
        if m:
            until = int(m.group(1))
        if until is None:
            continue
        for m in re.finditer(r'(?:Replace\(\s*"([^"]+)"\s*,|"([^"]+)"\s*=>|specialty\s*==\s*"([^"]+)")', line):
            w = next(g for g in m.groups() if g)
            out[w] = max(out.get(w, 0), until)
        if line.strip().startswith("return") and line.strip() == "return text;":
            until = None
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--original", default="/data/ashwell/reforge")
    ap.add_argument("--out", default=str(ROOT / "content" / "private"))
    ap.add_argument("--no-facts", action="store_true")
    a = ap.parse_args()
    orig = pathlib.Path(a.original)
    words = parse_claude_md((orig / "CLAUDE.md").read_text(encoding="utf-8"))
    for w, u in parse_filter_cs((orig / "src/ReForge.Core/Data/PerceptionFilter.cs").read_text(encoding="utf-8")).items():
        words[w] = max(words.get(w, 0), u)

    # 長い句の方が長く禁止されているなら、その中の短い語も同じだけ禁止する(安全側)。
    for w in list(words):
        words[w] = max([words[w]] + [u for v, u in words.items() if w in v])
    # 短い語が同じかより長く禁止されていれば、それを含む長い句は要らない。
    words = {v: u for v, u in words.items() if not any(w != v and w in v and words[w] >= u for w in words)}

    by_era = {}
    for w, u in words.items():
        by_era.setdefault(min(u, ERA_MAX), []).append(w)
    rules = [
        {"id": f"forbidden.original.era{u}", "words": sorted(ws), "until": era_fact(u)}
        for u, ws in sorted(by_era.items())
    ]
    stages = [{"id": "era1", "facts": []}] + [
        {"id": f"era{n}", "facts": [era_fact(k) for k in range(2, n + 1)]} for n in range(2, ERA_MAX)
    ]
    out = pathlib.Path(a.out)
    (out / "perception").mkdir(parents=True, exist_ok=True)
    note = ("生成物(tools/content/extract-forbidden.py)。原作 CLAUDE.md の表と PerceptionFilter.cs の置き換えから作った "
            "Era 単位の土台。手で直さず、事実単位の規則は別のファイルに足す。")
    (out / "perception" / "forbidden.original.json").write_text(
        json.dumps({"//": note, "forbidden": rules, "auditStages": stages}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8")
    if not a.no_facts:
        (out / "narrative").mkdir(parents=True, exist_ok=True)
        facts = [{"id": era_fact(n), **({"implies": [era_fact(n - 1)]} if n > 2 else {})} for n in range(2, ERA_MAX + 1)]
        (out / "narrative" / "era-facts.json").write_text(
            json.dumps({"//": "Era は事実の 1 つ(E-content.md §5.1)。生成物(extract-forbidden.py)。", "facts": facts},
                       ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"規則 {len(rules)} 件・語 {len(words)} 個 → {out}")


if __name__ == "__main__":
    main()
