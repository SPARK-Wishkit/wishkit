"""failure_report.py(원인 진단·기록) + tools/learn_from_feedback.py(자동 학습) 테스트."""
import json
import sys
from pathlib import Path

import brand_rules
from failure_report import build_report, diagnose

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import learn_from_feedback as lf


def _body(status, **kw):
    return {"status": status, "tag": kw.pop("tag", {"brand": "X", "product_code": "AB12345"}),
            "candidates_checked": kw.pop("checked", []), **kw}


def test_diagnose_main_causes():
    assert diagnose(_body("found"))[0] == "ok"
    assert diagnose(_body("not_found", skip_reason="no_brand_no_code"))[0] == "no_brand_no_code"
    assert diagnose(_body("not_found"))[0] == "search_empty"
    blocked = [{"url": "https://a.example/p", "reason": "규칙(x) · 페이지를 못 읽음(빈 화면)"}]
    assert diagnose(_body("not_found", checked=blocked))[0] == "page_blocked"
    nocode = [{"url": "https://a.example/p", "reason": "페이지에 품번 없음"}]
    assert diagnose(_body("not_found", checked=nocode))[0] == "code_not_on_page"
    assert diagnose(_body("not_found", note="공식몰 검색에 실패했어요"))[0] == "search_error"
    assert diagnose(_body("needs_confirm"))[0] == "unconfirmed"


def test_report_has_no_personal_fields():
    rep = build_report(_body("found", match={"url": "https://a.example/p", "via": "qr"}),
                       trace_id="t1", stages={"read_tag": 1}, total_ms=10, search_query="X AB12345")
    assert rep["trace_id"] == "t1" and rep["cause"] == "ok"
    for banned in ("image", "photo", "user", "owner", "ip"):
        assert banned not in rep


def test_url_template_replaces_code_and_drops_tracking():
    t = lf.url_template("https://shop.example.com/goods/AB-12345?utm_source=x&style=AB12345", "AB-12345")
    assert t == "https://shop.example.com/goods/{code}?style={code_compact}"
    # 만든 주소 모양으로 다시 주소를 만들면 원래 주소(추적 쿼리 제외)가 나와야 한다
    assert brand_rules._fill(t, "AB-12345", None) == "https://shop.example.com/goods/AB-12345?style=AB12345"
    assert lf.url_template("https://shop.example.com/goods/999", "AB12345") is None


def test_learn_new_brand_seller_and_rule():
    rules = brand_rules.load_rules()
    pos = [{"url": f"https://www.newbrand.co.kr/product/NB{c}", "brand_raw": "NEWBRAND", "brand_canonical": None,
            "code": f"NB{c}", "by": "yes"} for c in ("10001", "10002", "10003")]
    learned, _ = lf.learn(pos, rules, min_confirm=2, min_codes=3, today="2026-11-09")
    entry = learned["brands"]["newbrand"]
    assert entry["sellers"] == ["newbrand.co.kr"] and entry["official_domain"] == "newbrand.co.kr"
    assert entry["rules"][0]["url"] == "https://www.newbrand.co.kr/product/{code_compact}"


def test_one_confirmation_is_only_a_proposal():
    rules = brand_rules.load_rules()
    pos = [{"url": "https://www.musinsa.com/products/123", "brand_raw": "TINYBRAND", "brand_canonical": None,
            "code": "TB1", "by": "yes"}]
    learned, proposals = lf.learn(pos, rules, min_confirm=2, min_codes=3, today="2026-11-09")
    assert not learned["brands"] and any("tinybrand" in p for p in proposals)


def test_learned_file_is_merged_and_human_rules_win(tmp_path):
    learned = {"brands": {
        "newbrand": {"aliases": ["NEWBRAND"], "category": "unknown", "sellers": ["newbrand.co.kr"],
                     "official_domain": "newbrand.co.kr", "evidence": {"confirmed": 3}},
        "zara": {"category": "k_designer", "sellers": ["musinsa.com"]}}}
    path = tmp_path / "learned.json"
    path.write_text(json.dumps(learned), encoding="utf-8")
    brand_rules.load_rules.cache_clear()
    try:
        rules = brand_rules.load_rules(learned_path=str(path))
        assert brand_rules.canonical_brand("NEWBRAND", rules) == "newbrand"
        assert rules["brands"]["zara"]["category"] == "spa"  # 사람이 쓴 분류가 이긴다
        assert brand_rules.seller_hints({"brand": "ZARA"}, rules)[0] == "musinsa.com"  # 판매처는 덧붙는다
    finally:
        brand_rules.load_rules.cache_clear()


def test_tool_reads_engine_log_lines(tmp_path):
    rep = build_report(_body("not_found"), trace_id="abc", stages={}, total_ms=1, search_query=None)
    log = tmp_path / "engine.log"
    log.write_text("2026 INFO something\n2026 INFO [identify-report] " + json.dumps(rep, ensure_ascii=False) + "\n",
                   encoding="utf-8")
    reports = lf.load_reports([log])
    assert len(reports) == 1 and reports[0]["cause"] == "search_empty"


def test_tool_reads_dynamodb_scan_feedback(tmp_path):
    scan = {"Items": [{"answer": {"S": "yes"}, "traceId": {"S": "abc"}, "matchUrl": {"S": "https://a.example/p"}}]}
    p = tmp_path / "fb.json"
    p.write_text(json.dumps(scan), encoding="utf-8")
    fb = lf.load_feedback([p])
    assert fb == [{"answer": "yes", "traceId": "abc", "matchUrl": "https://a.example/p"}]


# ── 실패 보관(failure_store) ──

def test_failure_store_saves_photo_without_exif_and_record(tmp_path, monkeypatch):
    import io

    import failure_store
    from PIL import Image

    monkeypatch.setenv("TAG_FAILURE_DIR", str(tmp_path))
    img = Image.new("RGB", (50, 50), "white")
    exif = Image.Exif()
    exif[0x0110] = "iPhone 15"  # 기기 모델
    buf = io.BytesIO()
    img.save(buf, "JPEG", exif=exif)
    report = build_report(_body("not_found"), trace_id="t9", stages={}, total_ms=1, search_query=None)
    where = failure_store.save(buf.getvalue(), report)
    assert where
    photo = Path(where).with_suffix(".jpg")
    assert photo.exists() and not Image.open(photo).getexif()  # 메타데이터 없음
    record = json.loads(Path(where).with_suffix(".json").read_text(encoding="utf-8"))
    assert record["cause"] == "search_empty" and record["has_photo"] is True


def test_failure_store_skips_found_and_when_disabled(tmp_path, monkeypatch):
    import failure_store

    found = build_report(_body("found"), trace_id="t1", stages={}, total_ms=1, search_query=None)
    monkeypatch.setenv("TAG_FAILURE_DIR", str(tmp_path))
    assert failure_store.save(b"x", found) is None
    monkeypatch.delenv("TAG_FAILURE_DIR")
    miss = build_report(_body("not_found"), trace_id="t2", stages={}, total_ms=1, search_query=None)
    assert failure_store.save(b"x", miss) is None


# ── 자동 발견(discover_rules) ──

import asyncio

import discover_rules as dr
from tag_identify import PageView


def _rec(code, brand="AMOU"):
    return {"trace_id": code, "brand": brand, "brand_canonical": None, "product_code": code, "other_codes": [],
            "cause": "search_empty"}


def test_discovery_finds_musinsa_and_learns_after_two_codes():
    def render_for(code):
        async def render_page(url):
            if "search/goods" in url and code in url:
                return PageView(True, url, "검색 결과", html=f'<a href="/products/{abs(hash(code)) % 10**7}">x</a>')
            if "/products/" in url:
                return PageView(True, url, f"AMOU 상품번호 {code} 59,600원 " + "설명 " * 100, body_chars=900)
            return PageView(False, url, "", error="차단")
        return render_page

    async def no_official(tag):
        return None

    results = [asyncio.run(dr.try_record(_rec(c), render_page=render_for(c), find_official=no_official))
               for c in ("AM26FWJP07BK001", "AM26FWJP08WH002")]
    assert all(r["ok"] and r["method"] == "musinsa" for r in results)
    learned, _ = dr.summarize(results, min_codes=2, today="2026-11-09")
    assert "amou" in learned["editshop_brands"]["musinsa.com"]


def test_discovery_learns_official_site_search_after_one_success():
    async def render_page(url):
        if url == "https://newbrand.co.kr/":
            return PageView(True, url, "홈", html="<div>홈</div>")  # SearchAction 없음
        if "/product/search.html" in url:
            return PageView(True, url, "검색", html='<a href="/product/coat/123/category/1/">코트</a>')
        if "/product/coat/123/" in url:
            return PageView(True, url, "상품코드 NB-COAT-01 129,000원 " + "설명 " * 100, body_chars=900)
        return PageView(False, url, "", error="없음")

    async def find_official(tag):
        return "newbrand.co.kr"

    r = asyncio.run(dr.try_record(_rec("NB-COAT-01", brand="NEWBRAND"), render_page=render_page,
                                  find_official=find_official))
    assert r["ok"] and r["method"] == "official:cafe24"
    learned, _ = dr.summarize([r], min_codes=2, today="2026-11-10")
    entry = learned["brands"]["newbrand"]
    assert entry["official_domain"] == "newbrand.co.kr"
    assert entry["rules"][0]["search_url"] == "https://newbrand.co.kr/product/search.html?keyword={code}"
    assert entry["rules"][0]["product_id_pattern"] == "@generic"


def test_discovery_prefers_sites_own_search_action():
    home = ('<script type="application/ld+json">{"@type":"WebSite","potentialAction":{"@type":"SearchAction",'
            '"target":"https://shop.brand.kr/find?word={search_term_string}"}}</script>')

    async def render_page(url):
        if url == "https://shop.brand.kr/":
            return PageView(True, url, "홈", html=home)
        if url.startswith("https://shop.brand.kr/find?word="):
            return PageView(True, url, "검색", html='<a href="/goods/goods_view.php?goodsNo=7">옷</a>')
        if "goods_view.php" in url:
            return PageView(True, url, "품번 BR-777 59,000원 " + "설명 " * 100, body_chars=900)
        return PageView(False, url, "", error="없음")

    async def find_official(tag):
        return "shop.brand.kr"

    r = asyncio.run(dr.try_record(_rec("BR-777", brand="BRANDX"), render_page=render_page,
                                  find_official=find_official))
    assert r["ok"] and r["method"] == "official:searchaction"
    assert r["rule"]["search_url"] == "https://shop.brand.kr/find?word={code}"


def test_discovery_skips_records_without_brand_or_code(tmp_path):
    data = [{"file": "a.jpeg", "response": {"status": "not_found", "skip_reason": "no_code", "cause": "no_code",
                                            "tag": {"brand": "X", "product_code": None}}},
            {"file": "b.jpeg", "response": {"status": "not_found", "cause": "search_empty",
                                            "tag": {"brand": "Y", "product_code": "Y12345"}}},
            {"file": "c.jpeg", "response": {"status": "found", "tag": {"brand": "Z", "product_code": "Z1"}}}]
    p = tmp_path / "r.json"
    p.write_text(json.dumps(data), encoding="utf-8")
    recs = dr.load_failures([p])
    assert [r["brand"] for r in recs] == ["Y"]
