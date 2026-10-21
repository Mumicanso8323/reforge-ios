#!/usr/bin/env python3
"""時刻の色の写真の画素の要約(screens/time-report.json。tools/collect-screens.py が集める)を判定する(W-19・TEST-O24・TEST-O22 の (2))。

  python3 tools/check-time-tint-shots.py screens/time-report.json             全部の判定
  python3 tools/check-time-tint-shots.py --map-only screens/time-report.json  ③〜⑥だけ(地図の外のハッシュ ①② を見ない)

要約の 1 件: {point, appearance, outside, tabs, map, redFraction, litFraction, dayBar, dayBarLabelHasNoDigits}
  point = dawn/noon/evening/night、appearance = dark/light。
判定:
  ① 点ごとに、ダークとライトで「地図の外」の SHA-256 が同じ(部品は外観に依らない。TEST-O24 の本体)
  ② 全 8 枚でタブの帯の SHA-256 が同じ(時刻にも依らない)
  ③ 点ごとに、ダークとライトで地図の中が同じ。ダークの中で 夜明け≠昼・昼≠夕方・夕方≠夜(地図に時刻の色が掛かっている)
  ④ 予約の赤の割合が全部 0.1% 未満
  ⑤ dayBar は夜明け・昼・夕方にあり夜に無い。ラベルに数字が無い
  ⑥ 夜明け・昼・夕方の地図の中に地形が描かれている(明るい画素の割合 litFraction が 1% 以上。要約に無ければ外れ)
①② は地図の外の画素(OS が描く帯を含み、シミュレータの更新で揺れうる)を比べる。--map-only はそれを見ない(CI で赤にする側)。
外れたら点と外観を出して終了コード 1。python3 標準だけ。"""
import json
import sys

POINTS = ["dawn", "noon", "evening", "night"]
LOOKS = ["dark", "light"]
RED_LIMIT = 0.001


LIT_MIN = 0.01


def main(argv: list) -> int:
    args = argv[1:]
    map_only = "--map-only" in args
    args = [a for a in args if a != "--map-only"]
    if len(args) != 1:
        print("使い方: check-time-tint-shots.py [--map-only] time-report.json", file=sys.stderr)
        return 2
    try:
        with open(args[0], encoding="utf-8") as f:
            entries = json.load(f)
    except (OSError, ValueError) as e:
        print(f"要約を読めない: {e}")
        return 1
    shots = {(e.get("point"), e.get("appearance")): e for e in entries if isinstance(e, dict)}
    problems = []

    missing = [f"{p}/{look}" for p in POINTS for look in LOOKS if (p, look) not in shots]
    if missing:
        print("要約が足りない(点/外観): " + ", ".join(missing))
        return 1

    # ① 地図の外が外観に依らない
    for p in ([] if map_only else POINTS):
        if shots[(p, "dark")]["outside"] != shots[(p, "light")]["outside"]:
            problems.append(f"① {p}: 地図の外の画素がダークとライトで違う(部品が端末の外観を読んでいる)")
    # ② タブの帯が全部同じ
    tabs = {shots[(p, look)]["tabs"] for p in POINTS for look in LOOKS}
    if len(tabs) != 1 and not map_only:
        for p in POINTS:
            for look in LOOKS:
                problems.append(f"② {p}/{look}: タブの帯 {shots[(p, look)]['tabs'][:12]}")
        problems.append("② タブの帯の画素が 8 枚で同じでない")
    # ③ 地図の中は外観に依らず、時刻で替わる
    for p in POINTS:
        if shots[(p, "dark")]["map"] != shots[(p, "light")]["map"]:
            problems.append(f"③ {p}: 地図の中の画素がダークとライトで違う")
    for a, b in zip(POINTS, POINTS[1:]):
        if shots[(a, "dark")]["map"] == shots[(b, "dark")]["map"]:
            problems.append(f"③ dark: {a} と {b} の地図の中が同じ(時刻の色が掛かっていない)")
    # ④ 予約の赤
    for p in POINTS:
        for look in LOOKS:
            fraction = float(shots[(p, look)]["redFraction"])
            if fraction >= RED_LIMIT:
                problems.append(f"④ {p}/{look}: 予約の赤の割合 {fraction * 100:.3f}%(0.1% 以上)")
    # ⑤ 日の棒
    for p in POINTS:
        for look in LOOKS:
            shot = shots[(p, look)]
            want = p != "night"
            if bool(shot["dayBar"]) != want:
                problems.append(f"⑤ {p}/{look}: dayBar が{'ある' if shot['dayBar'] else '無い'}(期待は{'ある' if want else '無い'})")
            if not shot["dayBarLabelHasNoDigits"]:
                problems.append(f"⑤ {p}/{look}: dayBar のラベルに数字がある")

    # ⑥ 昼の側の地図に地形が描かれている(真っ黒な地図どうしは ③ の「同じ」でも「違う」でも素通りしうる)
    for p in POINTS:
        if p == "night":
            continue
        for look in LOOKS:
            fraction = shots[(p, look)].get("litFraction")
            if fraction is None or float(fraction) < LIT_MIN:
                problems.append(f"⑥ {p}/{look}: 地図の中に地形が無い(明るい画素の割合 {fraction})")

    if problems:
        print("時刻の色の写真の検査に当たった:")
        print("\n".join(problems))
        return 1
    print("時刻の色の写真 8 枚: 地図に地形があり、時刻で替わる" + ("(地図の外は見ていない)" if map_only else "。部品は外観・時刻に依らない"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
