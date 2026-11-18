"""
실패한 태그로 브랜드별 새 규칙 찾기 — 사람 없이 돌아가는 "자동 분석".

엔진은 25초 안에 끝내야 해서 몇 가지만 시도하지만, 이 도구는 실패한 태그 하나하나에 시간을 넉넉히 주고
여러 방법을 차례로 시도한다. 어떤 방법으로 **페이지 안에서 품번이 확인되면** 그 방법을 그 브랜드의 규칙 후보로
기록하고, 같은 브랜드의 서로 다른 품번 N개(기본 2)에서 통하면 brand_rules.learned.json에 자동으로 넣는다.

시도하는 방법(브랜드마다):
  1. 무신사: "브랜드 품번" 검색 → 첫 상품 → 품번 확인 / 품번만 검색
  2. 공식몰 사이트 검색: 엔진의 구글 검색으로 공식몰 도메인을 알아낸 뒤(이미 알면 생략) 홈을 열어 사이트가
     알려 주는 검색 주소(schema.org SearchAction)를 쓰고, 없으면 플랫폼별 검색 주소 모양(카페24·고도몰·쇼피파이·
     일반 /search)을 차례로 시도한다(server/site_search.py). 한 번 확인되면 그 사이트 검색 규칙을 바로 학습한다.
  3. 이미 아는 모회사 몰·브랜드 규칙(엔진과 같은 것, 시간 제한 없이 다시)

입력: 실패 보관 폴더(TAG_FAILURE_DIR, 또는 S3에서 `aws s3 sync`로 받은 폴더)의 *.json,
      또는 tag_identify_check.py 결과(tag_identify_result.json). 둘 다 브랜드·품번이 있는 것만 다시 시도한다.

  python discover_rules.py --failures ~/tag-failures                  # 미리보기(리포트만)
  python discover_rules.py --failures tag_identify_result.json --write-learned
엔진 서버와 같은 .env(GEMINI_API_KEY)와 Playwright 브라우저가 필요하다(엔진 서버는 안 켜도 됨).
"""
from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import json
import sys
from collections import defaultdict
from pathlib import Path

SERVER = Path(__file__).resolve().parent.parent / "server"
TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(SERVER))
sys.path.insert(0, str(TOOLS))

import brand_rules
from brand_rules import RuleUrl, _fill
from tag_identify import PageView, _try_brand_rules, parse_search_output

REPORTS_DIR = Path(__file__).resolve().parent.parent / "reports"
LEARNED = SERVER / "brand_rules.learned.json"
SKIP_CAUSES = {"ok", "no_brand_no_code", "no_brand", "no_code", "not_a_tag"}

import site_search


def _site_rule(search_url: str) -> dict:
    """공식몰 사이트 검색 규칙(엔진의 브랜드 규칙 형식). 상품 링크는 플랫폼 공통 방식으로 고른다."""
    return {"search_url": search_url, "product_id_pattern": "@generic", "product_url": "{id}"}


def load_failures(paths: list[Path]) -> list[dict]:
    """실패 기록 → [{trace_id, brand, brand_canonical, product_code, other_codes, ..., cause}]."""
    out: list[dict] = []
    for p in paths:
        files = sorted(p.rglob("*.json")) if p.is_dir() else [p]
        for f in files:
            data = json.loads(f.read_text(encoding="utf-8"))
            if isinstance(data, list):  # tag_identify_check 결과
                for r in data:
                    body = r.get("response") or {}
                    tag = body.get("tag") or {}
                    if body.get("status") == "found":
                        continue
                    out.append({"trace_id": body.get("trace_id") or f"file:{r.get('file')}",
                                "source": r.get("file"), "cause": body.get("cause"),
                                **{k: tag.get(k) for k in ("brand", "brand_canonical", "product_code", "other_codes",
                                                           "barcode", "product_name", "website",
                                                           "official_domain_hint")}})
            elif isinstance(data, dict) and data.get("trace_id"):
                out.append({**data, "source": str(f)})
    return [r for r in out if r.get("cause") not in SKIP_CAUSES
            and str(r.get("brand") or "").strip() and str(r.get("product_code") or "").strip()]


def _tag(rec: dict) -> dict:
    return {"is_product_tag": True, "brand": rec.get("brand"), "product_code": rec.get("product_code"),
            "other_codes": rec.get("other_codes") or [], "barcode": rec.get("barcode"),
            "product_name": rec.get("product_name"), "tag_price": None}


def _rule_url(rule: dict, tag: dict, label: str, domain: str | None = None) -> RuleUrl | None:
    def sub(text: str) -> str:
        return text.replace("{domain}", domain) if domain else text
    kind = "search" if rule.get("search_url") else "product"
    url = _fill(sub(rule.get("search_url") or rule.get("url", "")), str(tag["product_code"]),
                rule.get("code_pattern"), tag.get("brand"))
    if not url:
        return None
    return RuleUrl(url=url, brand=label, mall=None, label=label, kind=kind,
                   product_id_pattern=rule.get("product_id_pattern", ""), product_url=sub(rule.get("product_url", "")))


async def try_record(rec: dict, *, render_page, find_official) -> dict:
    """실패 하나를 여러 방법으로 다시 시도. 통한 방법(rule)과 찾은 주소를 돌려준다."""
    tag = _tag(rec)
    rules = brand_rules.load_rules()
    attempts: list[tuple[str, dict, str | None]] = []
    for rule in (rules.get("editshop_rules") or {}).get("musinsa.com") or []:
        attempts.append(("musinsa", rule, None))
    domain = rec.get("official_domain_hint") or brand_rules.official_domain(tag, rules)
    if not domain:
        domain = await find_official(tag)
    if domain:
        # 1) 사이트가 직접 알려 주는 검색 주소(홈의 schema.org SearchAction) 2) 플랫폼별 검색 주소 모양
        home = await render_page(f"https://{domain}/")
        own = site_search.search_action_template(home.html) if home.ok else None
        if own:
            attempts.append(("official:searchaction", _site_rule(own), None))
        for name, tpl in site_search.search_patterns(domain):
            attempts.append((f"official:{name}", _site_rule(tpl), None))
    tried = []
    for name, rule, dom in attempts:
        cand = _rule_url(rule, tag, name, dom)
        if cand is None:
            continue
        step = await _try_brand_rules(tag, [cand], render_page=render_page, time_left=lambda: 60.0, min_s=6.0)
        tried.append({"method": name, "url": cand.url, "checked": step.checked})
        if step.found:
            learned_rule = {k: (v.replace("{domain}", dom) if isinstance(v, str) and dom else v)
                            for k, v in rule.items() if k != "verified"}
            return {"rec": rec, "ok": True, "method": name, "rule": learned_rule, "domain": dom or domain,
                    "url": step.found["url"], "tried": tried}
    return {"rec": rec, "ok": False, "domain": domain, "tried": tried}


def summarize(results: list[dict], *, min_codes: int, today: str) -> tuple[dict, list[str]]:
    """브랜드별로 같은 방법이 서로 다른 품번 min_codes개 이상에서 통하면 학습 규칙으로."""
    rules = brand_rules.load_rules()
    wins: dict[tuple[str, str], dict] = {}
    codes: dict[tuple[str, str], set[str]] = defaultdict(set)
    for r in results:
        if not r["ok"]:
            continue
        rec = r["rec"]
        brand = rec.get("brand_canonical") or brand_rules.canonical_brand(rec.get("brand"), rules) \
            or str(rec.get("brand")).strip().lower()
        key = (brand, json.dumps(r["rule"], sort_keys=True))
        wins[key] = {**r, "brand": brand}
        codes[key].add(str(rec.get("product_code")).upper())
    learned: dict = {"brands": {}, "editshop_brands": defaultdict(set)}
    notes: list[str] = []
    for key, r in wins.items():
        brand, n = r["brand"], len(codes[key])
        # 공식몰 사이트 검색 주소는 사이트 단위라 한 번 확인되면 충분하다(매번 페이지 안 품번으로 다시 확인함).
        needed = 1 if r["method"].startswith("official:") else min_codes
        if n < needed:
            notes.append(f"{brand}: {r['method']}로 1개 품번에서 찾음({r['url']}) — {min_codes}개면 자동 규칙")
            continue
        entry = learned["brands"].setdefault(brand, {})
        if brand not in rules["brands"]:
            entry.setdefault("aliases", [str(r["rec"].get("brand"))])
            entry.setdefault("category", "k_designer" if r["method"] == "musinsa" else "unknown")
        if r["method"] == "musinsa":
            learned["editshop_brands"]["musinsa.com"].add(brand)  # 무신사를 먼저 보게 된다
        else:
            entry["official_domain"] = r["domain"]
            entry.setdefault("rules", []).append({**r["rule"], "verified": f"자동 발견 {today}: 서로 다른 품번 {n}개"})
        entry["evidence"] = {"discovered": n, "method": r["method"], "updated": today}
    learned["editshop_brands"] = {k: sorted(v) for k, v in learned["editshop_brands"].items()}
    return learned, notes


def write_report(results: list[dict], learned: dict, notes: list[str], out: Path, today: str) -> str:
    ok = [r for r in results if r["ok"]]
    lines = [f"# 실패 태그 자동 분석 ({today})", "",
             f"다시 시도한 실패 {len(results)}건 중 {len(ok)}건을 다른 방법으로 찾았어요.", "",
             "| 브랜드 | 품번 | 결과 | 방법 | 주소 / 마지막 시도 |", "| --- | --- | --- | --- | --- |"]
    for r in results:
        rec = r["rec"]
        if r["ok"]:
            lines.append(f"| {rec.get('brand')} | {rec.get('product_code')} | 찾음 | {r['method']} | {r['url']} |")
        else:
            last = (r["tried"][-1]["checked"][-1]["reason"] if r["tried"] and r["tried"][-1]["checked"] else "시도 없음")
            lines.append(f"| {rec.get('brand')} | {rec.get('product_code')} | 못 찾음 | - | {last} |")
    lines += ["", "## 자동으로 넣은 규칙", ""]
    if learned["brands"] or learned["editshop_brands"]:
        for b, e in learned["brands"].items():
            lines.append(f"- **{b}**: " + (f"공식몰 {e['official_domain']} 검색 규칙" if e.get("rules") else "무신사 우선"))
    else:
        lines.append("- 없음")
    lines += ["", "## 근거가 더 필요한 것", ""] + ([f"- {n}" for n in notes] or ["- 없음"])
    text = "\n".join(lines) + "\n"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")
    return text


async def _real_functions():
    """실제 브라우저와 구글 검색(엔진과 같은 코드)."""
    import tag_identify
    from playwright.async_api import async_playwright
    from render import launch_browser, render

    pw = await async_playwright().start()
    browser = await launch_browser(pw)

    async def render_page(url: str) -> PageView:
        r = await render(browser, url, nav_timeout_ms=20000)
        text = f"{r.meta_text} {r.raw_text}".strip()
        return PageView(ok=r.ok, final_url=r.final_url or url, raw_text=text, error=r.error,
                        code_hints=r.code_hints, body_chars=len(r.raw_text.strip()) if r.ok else None,
                        html=r.cleaned_html if r.ok else "")

    async def find_official(tag: dict) -> str | None:
        res = await asyncio.to_thread(tag_identify.call_gemini_search, tag)
        if not res.ok or not res.data:
            return None
        official, _ = parse_search_output(res.data.get("text", ""), res.data.get("sources", []))
        return official

    async def close():
        await browser.close()
        await pw.stop()

    return render_page, find_official, close


async def run(args) -> int:
    from learn_from_feedback import merge_into_file

    today = dt.date.today().isoformat()
    records = load_failures(args.failures)[: args.limit]
    print(f"다시 시도할 실패 {len(records)}건")
    render_page, find_official, close = await _real_functions()
    sem = asyncio.Semaphore(args.concurrency)

    async def one(rec):
        async with sem:
            r = await try_record(rec, render_page=render_page, find_official=find_official)
            print(("찾음  " if r["ok"] else "못찾음"), rec.get("brand"), rec.get("product_code"), r.get("url") or "")
            return r
    try:
        results = await asyncio.gather(*(one(r) for r in records))
    finally:
        await close()
    learned, notes = summarize(list(results), min_codes=args.min_codes, today=today)
    out = REPORTS_DIR / f"tag_discovery_{today}.md"
    print(write_report(list(results), learned, notes, out, today))
    if args.write_learned and (learned["brands"] or learned["editshop_brands"]):
        merge_into_file(learned, LEARNED, today)
        print(f"학습 규칙을 갱신했어요: {LEARNED}")
    print(f"리포트: {out}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--failures", action="append", type=Path, required=True)
    ap.add_argument("--write-learned", action="store_true")
    ap.add_argument("--min-codes", type=int, default=2)
    ap.add_argument("--limit", type=int, default=200)
    ap.add_argument("--concurrency", type=int, default=3)
    args = ap.parse_args()
    from dotenv import load_dotenv

    load_dotenv(SERVER / ".env")
    return asyncio.run(run(args))


if __name__ == "__main__":
    sys.exit(main())
