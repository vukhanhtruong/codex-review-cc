#!/usr/bin/env python3
"""Render evals/results.json (from grade.py --json) into one standalone HTML report.

    python3 report.py results.json report.html

Self-contained: inline CSS, no external assets. Shows a catch-rate grid and, per case,
each arm's planted-issue checklist + raw findings side by side.
"""
import json, sys, html

CSS = """
body{font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;margin:0;background:#0f1115;color:#e6e6e6}
.wrap{max-width:1100px;margin:0 auto;padding:24px}
h1{font-size:20px}h2{font-size:16px;border-bottom:1px solid #2a2f3a;padding-bottom:6px;margin-top:32px}
table{border-collapse:collapse;width:100%;margin:12px 0}
th,td{border:1px solid #2a2f3a;padding:6px 10px;text-align:left;vertical-align:top}
th{background:#1a1e27}
.ok{color:#46d369}.bad{color:#ff5c5c}.tag{font-size:11px;padding:1px 6px;border-radius:4px;background:#1a1e27;border:1px solid #2a2f3a}
.cols{display:flex;gap:16px;flex-wrap:wrap}
.col{flex:1;min-width:320px;background:#141821;border:1px solid #2a2f3a;border-radius:8px;padding:12px}
.findings{white-space:pre-wrap;font:12px/1.45 ui-monospace,Menlo,monospace;background:#0b0d12;border:1px solid #2a2f3a;border-radius:6px;padding:10px;max-height:340px;overflow:auto}
.chk li{list-style:none}.chk{padding-left:0}
small{color:#8a93a6}
.hot{color:#ff8c42}.z{color:#8a93a6}
.barwrap{position:relative;background:#0b0d12;border:1px solid #2a2f3a;border-radius:4px;height:18px;min-width:120px}
.bar{height:100%;border-radius:3px}.barwrap span{position:absolute;right:6px;top:0;font-size:11px;line-height:18px}
details{margin:6px 0;background:#141821;border:1px solid #2a2f3a;border-radius:6px;padding:8px}
summary{cursor:pointer}
"""


def esc(s):
    return html.escape(s or "")


def _chk(p):
    if p["caught"]:
        cls, mark = "ok", "✓"
    elif p["gating"]:
        cls, mark = "bad", "✗"
    else:
        cls, mark = "", "·"   # non-gating miss: neutral, not a failure
    tag = "" if p["gating"] else ' <span class="tag">non-gating</span>'
    return (f'<li><span class="{cls}">[{mark}]</span> '
            f'{esc(p["id"])} {esc(p["desc"])}{tag}</li>')


def quality_section(qpath):
    q = json.load(open(qpath))
    trials, m = q.get("trials", []), q.get("means", {})
    if not trials:
        return ""
    mx = max((t.get("codex_real_total", 0) for t in trials), default=1) or 1

    def bar(v, color):
        return (f'<div class="barwrap"><div class="bar" style="width:{v/mx*100:.0f}%;'
                f'background:{color}"></div><span>{v}</span></div>')
    rows = "".join(
        f'<tr><td>{t.get("trial","?")}</td><td>{t.get("distinct_real_total",0)}</td>'
        f'<td>{bar(t.get("self_real_total",0),"#6b8cce")}</td>'
        f'<td>{bar(t.get("codex_real_total",0),"#3aa76d")}</td>'
        f'<td class="z">{t.get("only_self",0)}</td>'
        f'<td class="hot">{t.get("only_codex",0)}</td></tr>' for t in trials)
    blind = "".join(
        f'<details><summary>Trial {t.get("trial","?")} — '
        f'<b class="hot">only-Codex {t.get("only_codex",0)}</b> · only-self {t.get("only_self",0)}</summary>'
        f'<b>high/med issues only Codex caught:</b><ul>'
        + ("".join(f"<li>{esc(x)}</li>" for x in t.get("only_codex_high_med", [])) or "<li>(none)</li>")
        + '</ul><b>issues only self caught:</b><ul>'
        + ("".join(f"<li>{esc(x)}</li>" for x in t.get("only_self_items", [])) or "<li>(none)</li>")
        + '</ul></details>' for t in trials)
    summ = (f'<p>mean real issues: self <b>{m.get("self_real",0):.1f}</b> vs '
            f'codex <b class="ok">{m.get("codex_real",0):.1f}</b> · '
            f'only-codex <b class="hot">{m.get("only_codex",0):.1f}</b> · '
            f'only-self <b>{m.get("only_self",0):.1f}</b> · '
            f'self coverage {m.get("self_coverage_pct",0):.0f}%</p>') if m else ""
    return (f'<h2>Reviewer-quality — codex vs Claude self-review (judge-scored)</h2>'
            f'<p><small>Directional: nondeterministic models + single judge per trial → treat counts as directional.</small></p>'
            f'{summ}<table><tr><th>trial</th><th>distinct real</th><th>self</th>'
            f'<th>codex</th><th>only-self</th><th>only-codex</th></tr>{rows}</table>{blind}')


def main(results_path, out_path, quality_path=None):
    data = json.load(open(results_path))
    arms = list(dict.fromkeys(d["arm"] for d in data))
    names = list(dict.fromkeys(d["name"] for d in data))
    by = {(d["arm"], d["name"]): d for d in data}

    rows = []
    for name in names:
        cells = []
        for arm in arms:
            d = by.get((arm, name))
            if not d:
                cells.append("<td>—</td>"); continue
            n, tot = d["recall"]
            cls = "ok" if n == tot else "bad"
            vcls = "ok" if d["verdict_ok"] else "bad"
            cells.append(f'<td><span class="{cls}">{n}/{tot}</span> '
                         f'<small class="{vcls}">{esc(d["verdict"])}</small></td>')
        rows.append(f"<tr><td><b>{esc(name)}</b></td>{''.join(cells)}</tr>")
    grid = (f"<table><tr><th>case</th>{''.join(f'<th>{esc(a)}</th>' for a in arms)}</tr>"
            f"{''.join(rows)}</table>")

    sections = []
    for name in names:
        cols = []
        for arm in arms:
            d = by.get((arm, name))
            if not d:
                continue
            chk = "".join(_chk(p) for p in d["planted"])
            cols.append(
                f'<div class="col"><b>{esc(arm)}</b> '
                f'<span class="tag">{esc(d["verdict"])}</span>'
                f'<ul class="chk">{chk}</ul>'
                f'<div class="findings">{esc(d["findings"]) or "(no output)"}</div></div>')
        sections.append(f'<h2>{esc(name)}</h2><div class="cols">{"".join(cols)}</div>')

    qsec = quality_section(quality_path) if quality_path else ""
    doc = (f"<!doctype html><meta charset=utf-8><title>codex-review evals</title>"
           f"<style>{CSS}</style><div class=wrap>"
           f"<h1>codex-review eval report</h1>"
           f"<h2>Gate — planted-issue catch-rate (signal match)</h2>"
           f"<p><small>catch-rate = gating planted issues caught / total · verdict colored vs expected</small></p>"
           f"{grid}{''.join(sections)}{qsec}</div>")
    open(out_path, "w").write(doc)
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
