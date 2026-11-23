"""
태그 찾기 실패 모으기 · 원인 정리 · 브랜드 규칙 자동 학습.

엔진은 요청마다 로그에 `[identify-report] {...}` 한 줄(익명)을 남기고, 앱은 사용자가 "맞아요"/"다른 상품이에요"를
누르거나 못 찾았을 때·직접 링크를 넣었을 때 TagFeedback(익명)을 남긴다. 둘은 trace_id로 이어진다.
이 도구는 둘을 모아서

  1. 리포트(engine/reports/tag_learning_YYYY-MM-DD.md): 원인별 집계, 브랜드별 실패, 모르는 브랜드,
     열지 못한 사이트, 사용자가 "아니에요"한 매칭, 이번에 학습한 것과 사람이 볼 제안.
  2. 학습 규칙(engine/server/brand_rules.learned.json, --write-learned일 때): 확실한 것만 자동으로 넣는다.
       - 처음 보는 브랜드인데 같은 사이트에서 N번 이상 확인됨 → 브랜드 + 판매처
       - 아는 브랜드인데 새 판매처에서 N번 이상 확인됨 → 판매처 추가(검색 힌트 맨 앞)
       - 같은 사이트에서 서로 다른 품번 M개의 상품 주소가 "품번만 바뀌는 같은 모양" → 주소 규칙
       - 편집숍에서 확인됨 → 편집숍 입점 목록
     학습 규칙도 엔진이 페이지 안에서 품번을 확인해야 "찾음"이 되므로, 틀린 규칙이 들어가도 잘못된 상품을
     "찾음"으로 내보내지는 않는다(시간만 조금 쓴다). 사람이 쓰는 brand_rules.json은 건드리지 않는다.

입력
  --reports  엔진 로그 파일(…[identify-report] {json} 줄), CloudWatch 내보내기(JSON, events[].message),
             또는 tag_identify_check.py 결과(tag_identify_result.json). 여러 개 가능.
  --feedback TagFeedback 내보내기(JSON 목록 / JSON Lines / `aws dynamodb scan` 결과). 없어도 된다.

  python learn_from_feedback.py --reports ~/engine.log --reports tag_identify_result.json
  python learn_from_feedback.py --reports cw.json --feedback feedback.json --write-learned
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import urllib.parse
from collections import Counter, defaultdict
from pathlib import Path

SERVER = Path(__file__).resolve().parent.parent / "server"
sys.path.insert(0, str(SERVER))

import brand_rules
import failure_report
from tag_identify import MALL_DOMAINS, host_of

REPORTS_DIR = Path(__file__).resolve().parent.parent / "reports"
LEARNED = SERVER / "brand_rules.learned.json"
STRONG_EVIDENCE = {"product_code", "barcode", "product_code_base"}


# ── 읽기 ─────────────────────────────────────────────────────

def _iter_report_lines(text: str):
    for line in text.splitlines():
        i = line.find("[identify-report] ")
        if i >= 0:
            try:
                yield json.loads(line[i + len("[identify-report] "):])
            except ValueError:
                continue


def load_reports(paths: list[Path]) -> list[dict]:
    out: list[dict] = []
    for p in paths:
        text = p.read_text(encoding="utf-8", errors="replace")
        try:
            data = json.loads(text)
        except ValueError:
            data = None
        if isinstance(data, list) and data and isinstance(data[0], dict) and "response" in data[0]:
            # tag_identify_check.py 결과 — 응답에서 기록을 다시 만든다(trace_id가 없으면 파일 이름으로).
            for r in data:
                body = r.get("response") or {}
                if not body:
                    continue
                rep = failure_report.build_report(
                    body, trace_id=body.get("trace_id") or f"file:{r.get('file')}", stages={}, total_ms=0,
                    search_query=None)
                rep["source_file"] = r.get("file")
                out.append(rep)
        elif isinstance(data, dict) and "events" in data:  # aws logs filter-log-events --output json
            for ev in data["events"]:
                out.extend(_iter_report_lines(ev.get("message", "")))
        else:
            out.extend(_iter_report_lines(text))
    # 같은 trace_id는 마지막 것만
    return list({r["trace_id"]: r for r in out}.values())


def _unwrap_dynamo(item: dict) -> dict:
    """`aws dynamodb scan` 결과의 {"S": "..."} 꼴을 평범한 값으로."""
    out = {}
    for k, v in item.items():
        if isinstance(v, dict) and len(v) == 1 and next(iter(v)) in ("S", "N", "BOOL", "NULL"):
            out[k] = next(iter(v.values()))
        else:
            out[k] = v
    return out


def load_feedback(paths: list[Path]) -> list[dict]:
    out: list[dict] = []
    for p in paths:
        text = p.read_text(encoding="utf-8", errors="replace").strip()
        if not text:
            continue
        try:
            data = json.loads(text)
            items = data.get("Items", data) if isinstance(data, dict) else data
        except ValueError:
            items = [json.loads(line) for line in text.splitlines() if line.strip()]
        out.extend(_unwrap_dynamo(i) for i in items)
    return out


# ── 학습 ─────────────────────────────────────────────────────

def _site(host: str) -> str:
    return (host or "").lower().removeprefix("www.").removeprefix("m.")


def _is_mall(host: str) -> bool:
    return any(host == d or host.endswith("." + d) for d in MALL_DOMAINS)


def _compact(code: str | None) -> str:
    return re.sub(r"[^0-9A-Za-z]", "", str(code or "")).upper()


def url_template(url: str, code: str | None) -> str | None:
    """상품 주소에서 품번 자리를 자리표시자로 바꾼 모양. 품번이 주소에 없으면 None.
    태그에 적힌 그대로(하이픈 포함)는 {code}, 영문·숫자만 남긴 모양은 {code_compact}. 품번이 없는 쿼리(utm 등)는 뺀다."""
    c = _compact(code)
    raw = str(code or "").replace(" ", "")
    if len(c) < 5:
        return None
    parts = urllib.parse.urlsplit(url)
    keep = [(k, v) for k, v in urllib.parse.parse_qsl(parts.query) if c in _compact(v)]
    query = "&".join(f"{k}={v}" for k, v in keep)
    rebuilt = f"{parts.scheme}://{parts.netloc}{urllib.parse.unquote(parts.path)}" + (f"?{query}" if query else "")
    tpl = rebuilt
    if raw and raw.upper() != c:
        tpl = re.sub(re.escape(raw), "{code}", tpl, flags=re.IGNORECASE)
    tpl = re.sub(re.escape(c), "{code_compact}", tpl, flags=re.IGNORECASE)
    return tpl if "{code" in tpl else None


def collect_positives(reports: dict[str, dict], feedback: list[dict]) -> list[dict]:
    """확인된 정답들: 사용자 "맞아요"·직접 넣은 링크 + 엔진이 품번으로 확인한 found."""
    pos: list[dict] = []
    answered = set()
    for f in feedback:
        rep = reports.get(f.get("traceId") or "")
        url = f.get("userUrl") if f.get("answer") == "user_link" else (f.get("matchUrl") if f.get("answer") == "yes" else None)
        if not url:
            continue
        answered.add(f.get("traceId"))
        pos.append({"url": url, "brand_raw": (rep or {}).get("brand_raw") or f.get("brand"),
                    "brand_canonical": (rep or {}).get("brand_canonical"),
                    "code": (rep or {}).get("product_code") or f.get("productCode"), "by": f.get("answer")})
    for tid, r in reports.items():
        m = r.get("match") or {}
        if tid in answered or r.get("status") != "found" or m.get("verified_by") not in STRONG_EVIDENCE:
            continue
        pos.append({"url": m.get("url"), "brand_raw": r.get("brand_raw"), "brand_canonical": r.get("brand_canonical"),
                    "code": r.get("product_code"), "by": "engine"})
    return [p for p in pos if p["url"]]


def learn(positives: list[dict], rules: dict, *, min_confirm: int, min_codes: int, today: str) -> tuple[dict, list[str]]:
    """학습 결과(learned.json에 합칠 것)와 사람이 볼 제안 목록."""
    learned: dict = {"brands": {}, "editshop_brands": defaultdict(set)}
    proposals: list[str] = []
    editshops = set(rules.get("editshops") or [])

    by_brand: dict[str, list[dict]] = defaultdict(list)
    for p in positives:
        key = (p["brand_canonical"] or brand_rules.canonical_brand(p["brand_raw"], rules)
               or str(p["brand_raw"] or "").strip().lower())
        if key:
            by_brand[key].append(p)

    for key, items in by_brand.items():
        known = key in rules["brands"]
        info = rules["brands"].get(key) or {}
        sites = Counter(_site(host_of(p["url"])) for p in items)
        existing = {info.get("official_domain"), *(info.get("sellers") or [])}
        mall_key = info.get("mall")
        if mall_key:
            existing.add((rules["malls"].get(mall_key) or {}).get("domain"))
        sellers = [s for s, n in sites.most_common() if n >= min_confirm and s not in existing]
        weak = [s for s, n in sites.items() if n < min_confirm and s not in existing]
        entry: dict = {}
        if not known and sellers:
            raws = sorted({str(p["brand_raw"]).strip() for p in items if p["brand_raw"]})
            official = next((s for s in sellers if not _is_mall(s)), None)
            entry = {"aliases": raws, "category": "k_designer" if all(s in editshops for s in sellers) else "unknown",
                     "sellers": sellers}
            if official:
                entry["official_domain"] = official
        elif known and sellers:
            entry = {"sellers": sellers}
        for s in weak:
            proposals.append(f"{key}: {s}에서 {sites[s]}번 확인 — {min_confirm}번이 되면 자동으로 판매처에 들어가요")

        # 주소 규칙: 같은 사이트, 같은 모양, 서로 다른 품번 min_codes개 이상
        templates: dict[str, set[str]] = defaultdict(set)
        for p in items:
            t = url_template(p["url"], p["code"])
            if t:
                templates[t].add(_compact(p["code"]))
        have = {r.get("url") for r in info.get("rules") or []}
        new_rules = []
        for t, codes in templates.items():
            if t in have:
                continue
            if len(codes) >= min_codes:
                new_rules.append({"url": t, "verified": f"자동 학습 {today}: 서로 다른 품번 {len(codes)}개로 확인"})
            else:
                proposals.append(f"{key}: 주소 모양 {t} (품번 {len(codes)}개 확인, {min_codes}개면 자동 규칙)")
        if new_rules:
            entry["rules"] = new_rules
        if entry:
            entry["evidence"] = {"confirmed": len(items), "sites": dict(sites), "updated": today}
            learned["brands"][key] = entry
        for s, n in sites.items():
            if s in editshops and n >= min_confirm:
                learned["editshop_brands"][s].add(key)
    learned["editshop_brands"] = {k: sorted(v) for k, v in learned["editshop_brands"].items()}
    return learned, proposals


def merge_into_file(learned: dict, path: Path, today: str) -> dict:
    old = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    merged = {
        "_설명": ["tools/learn_from_feedback.py가 자동으로 쓰는 파일입니다. 사람이 고칠 규칙은 brand_rules.json에.",
                 "엔진은 brand_rules.json과 이 파일을 합쳐 읽고, 겹치면 brand_rules.json이 이깁니다."],
        "updated": today, "brands": old.get("brands", {}), "editshop_brands": old.get("editshop_brands", {}),
    }
    for name, entry in learned["brands"].items():
        cur = merged["brands"].setdefault(name, {})
        for k, v in entry.items():
            if isinstance(v, list):
                cur[k] = [*cur.get(k, []), *[x for x in v if x not in cur.get(k, [])]]
            else:
                cur[k] = v
    for shop, brands in learned["editshop_brands"].items():
        merged["editshop_brands"][shop] = sorted({*merged["editshop_brands"].get(shop, []), *brands})
    path.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return merged


# ── 리포트 ───────────────────────────────────────────────────

def write_report(reports: list[dict], feedback: list[dict], learned: dict, proposals: list[str],
                 out: Path, today: str) -> str:
    lines = [f"# 태그 찾기 학습 리포트 ({today})", ""]
    total = len(reports)
    causes = Counter(r["cause"] for r in reports)
    answers = Counter(f.get("answer") for f in feedback)
    yes, no = answers.get("yes", 0), answers.get("no", 0)
    found = causes.get("ok", 0)
    lines += [f"요청 {total}건 중 찾음 {found}건({found / total:.0%})" if total else "요청 기록이 없어요.",
              f"사용자 답: 맞아요 {yes} · 아니에요 {no} · 못 불러옴 {answers.get('not_found', 0)}"
              f" · 직접 링크 {answers.get('user_link', 0)}" + (f" — 정답률 {yes / (yes + no):.0%}" if yes + no else ""),
              "", "## 원인별", "", "| 원인 | 건수 | 비율 | 뜻 | 보통 해결 방법 |", "| --- | --- | --- | --- | --- |"]
    for cause, n in causes.most_common():
        desc, fix = failure_report.CAUSES.get(cause, (cause, "-"))
        lines.append(f"| `{cause}` | {n} | {n / total:.0%} | {desc} | {fix} |")

    fails = [r for r in reports if r["cause"] not in ("ok", "no_brand_no_code", "not_a_tag")]
    by_brand: dict[str, list[dict]] = defaultdict(list)
    for r in fails:
        name = r.get("brand_canonical") or brand_rules.canonical_brand(r.get("brand_raw"))
        by_brand[name or f"? {r.get('brand_raw') or '(브랜드 없음)'}"].append(r)
    lines += ["", "## 실패가 많은 브랜드", "", "| 브랜드 | 실패 | 주 원인 | 예시 품번 | 브랜드 판단 |", "| --- | --- | --- | --- | --- |"]
    for b, rs in sorted(by_brand.items(), key=lambda kv: -len(kv[1]))[:25]:
        main = Counter(r["cause"] for r in rs).most_common(1)[0][0]
        codes = ", ".join(sorted({str(r.get("product_code")) for r in rs if r.get("product_code")})[:3])
        lines.append(f"| {b} | {len(rs)} | `{main}` | {codes} | {rs[0].get('brand_decided_by') or '-'} |")

    unknown = [r for r in reports if "unknown_brand" in (r.get("flags") or [])]
    if unknown:
        lines += ["", "## 규칙에 없는 브랜드 (brand_rules.json에 추가 후보)", "",
                  "| 태그 브랜드 | 건수 | 예시 품번 | 회사명 | 웹사이트 |", "| --- | --- | --- | --- | --- |"]
        grouped: dict[str, list[dict]] = defaultdict(list)
        for r in unknown:
            grouped[str(r.get("brand_raw") or "(없음)")].append(r)
        for raw, rs in sorted(grouped.items(), key=lambda kv: -len(kv[1])):
            lines.append(f"| {raw} | {len(rs)} | {rs[0].get('product_code') or '-'} | {rs[0].get('company') or '-'}"
                         f" | {rs[0].get('website') or '-'} |")

    blocked = Counter(_site(host_of(c["url"])) for r in reports for c in r.get("checked") or []
                      if any(w in str(c.get("reason")) for w in ("못 읽음", "빈 화면", "차단")))
    if blocked:
        lines += ["", "## 열지 못한 사이트 (봇 차단 의심)", "", "| 사이트 | 횟수 |", "| --- | --- |"]
        lines += [f"| {s} | {n} |" for s, n in blocked.most_common(15)]

    wrong = [f for f in feedback if f.get("answer") == "no"]
    if wrong:
        lines += ["", "## 사용자가 \"다른 상품이에요\"라고 한 매칭", "", "| 브랜드 | 품번 | 엔진이 낸 주소 | 찾은 방법 |",
                  "| --- | --- | --- | --- |"]
        lines += [f"| {f.get('brand') or '-'} | {f.get('productCode') or '-'} | {f.get('matchUrl') or '-'} "
                  f"| {f.get('matchVia') or '-'} / {f.get('verifiedBy') or '-'} |" for f in wrong[:30]]

    lines += ["", "## 이번에 자동으로 학습한 것", ""]
    if learned["brands"] or learned["editshop_brands"]:
        for name, e in learned["brands"].items():
            bits = [f"판매처 {', '.join(e['sellers'])}" if e.get("sellers") else "",
                    f"주소 규칙 {len(e['rules'])}개" if e.get("rules") else "",
                    "새 브랜드" if name not in brand_rules.load_rules()["brands"] else ""]
            lines.append(f"- **{name}**: " + " · ".join(b for b in bits if b))
        for shop, bs in learned["editshop_brands"].items():
            lines.append(f"- {shop} 입점: {', '.join(bs)}")
    else:
        lines.append("- 없음 (확인된 정답이 기준보다 적어요)")
    lines += ["", "## 사람이 볼 제안 (근거가 아직 적음)", ""]
    lines += [f"- {p}" for p in proposals[:40]] or ["- 없음"]
    text = "\n".join(lines) + "\n"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")
    return text


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reports", action="append", type=Path, default=[], required=True)
    ap.add_argument("--feedback", action="append", type=Path, default=[])
    ap.add_argument("--write-learned", action="store_true", help="brand_rules.learned.json을 갱신")
    ap.add_argument("--min-confirm", type=int, default=2, help="판매처·새 브랜드 학습에 필요한 확인 횟수")
    ap.add_argument("--min-codes", type=int, default=3, help="주소 규칙 학습에 필요한 서로 다른 품번 수")
    ap.add_argument("--out-dir", type=Path, default=REPORTS_DIR)
    args = ap.parse_args()

    today = dt.date.today().isoformat()
    reports = load_reports(args.reports)
    feedback = load_feedback(args.feedback)
    rules = brand_rules.load_rules()
    positives = collect_positives({r["trace_id"]: r for r in reports}, feedback)
    learned, proposals = learn(positives, rules, min_confirm=args.min_confirm, min_codes=args.min_codes, today=today)
    out = args.out_dir / f"tag_learning_{today}.md"
    text = write_report(reports, feedback, learned, proposals, out, today)
    if args.write_learned and (learned["brands"] or learned["editshop_brands"]):
        merge_into_file(learned, LEARNED, today)
        print(f"학습 규칙을 갱신했어요: {LEARNED}")
    print(text)
    print(f"리포트: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
