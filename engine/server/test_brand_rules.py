"""brand_rules.py + identify()의 브랜드 규칙 단계 테스트. 실제 규칙 파일(brand_rules.json)을 그대로 읽는다."""
import asyncio

from brand_rules import candidate_urls, canonical_brand, load_rules, seller_hint
from providers import ProviderResult
from qr_codes import DecodedCodes
from tag_identify import PageView, build_search_prompt, identify


def test_rules_file_is_valid_and_aliases_are_unique():
    rules = load_rules()
    seen = {}
    for name, info in rules["brands"].items():
        for alias in [name, *info.get("aliases", [])]:
            key = alias.strip().lower().replace(" ", "")
            assert seen.setdefault(key, name) == name, f"별칭 {alias}가 {seen[key]}와 {name}에 겹침"
        if "mall" in info:
            assert info["mall"] in rules["malls"], f"{name}의 몰 {info['mall']}이 malls에 없음"


def test_brand_name_variants_become_one_name():
    for raw in ("8 seconds", "8SECONDS", "에잇세컨즈", "8 Seconds"):
        assert canonical_brand(raw) == "8seconds"
    assert canonical_brand("JUUN.J") == "juun.j"
    assert canonical_brand("처음 보는 브랜드") is None


def test_ssf_brand_gets_sap_view_url_from_code():
    urls = candidate_urls({"brand": "BEAKER", "product_code": "QQ6X39EP20"})
    assert [u.url for u in urls] == ["https://m.ssfshop.com/public/goods/detail/QQ6X39EP20/sapView"]
    assert urls[0].mall == "ssf"


def test_new_balance_style_and_color_split():
    urls = candidate_urls({"brand": "NEW BALANCE", "product_code": "NBNQG41923-01"})
    assert urls[0].url.endswith("styleCode=NBNQG41923&colCode=01")


def test_new_balance_code_without_color_has_no_url():
    assert candidate_urls({"brand": "NEW BALANCE", "product_code": "NBNQG41923"}) == []


def test_unverified_mall_gives_seller_hint_but_no_url():
    tag = {"brand": "HAZZYS", "product_code": "HSSW5F123"}
    assert candidate_urls(tag) == []
    assert seller_hint(tag) == "lfmall.co.kr"


# ── identify()에 붙였을 때 ──

TAG = {"is_product_tag": True, "brand": "BEAKER", "product_code": "QQ6X39EP20", "other_codes": [],
       "barcode": None, "product_name": None, "color": None, "size": None, "tag_price": 298000,
       "confidence": "high"}
SSF_RULE = "https://m.ssfshop.com/public/goods/detail/QQ6X39EP20/sapView"
SSF_PAGE = "https://m.ssfshop.com/BEAKER/GM0026101660266/good"


def _run(tag, pages, time_left=20.0):
    calls = {"search": 0, "render": [], "prompt": None}

    async def read_tag(img, mime):
        return ProviderResult("f", "f", True, dict(tag), 1)

    async def read_codes(img):
        return DecodedCodes()

    async def search(t):
        calls["search"] += 1
        calls["prompt"] = build_search_prompt(t)
        return ProviderResult("f", "f", True, {"text": "", "sources": []}, 1)

    async def render(url):
        calls["render"].append(url)
        return pages.get(url, PageView(ok=False, final_url=url, raw_text="", error="차단"))

    out = asyncio.run(identify(b"x", "image/jpeg", read_tag=read_tag, search=search, render_page=render,
                               time_left=lambda: time_left, read_codes=read_codes,
                               rule_urls=candidate_urls, verify_by_render=False))
    return out, calls


def test_rule_page_with_code_is_found_without_search():
    page = PageView(ok=True, final_url=SSF_PAGE, raw_text="비이커 상품번호 QQ6X39EP20 298,000원 " + "설명 " * 100,
                    body_chars=900)
    out, calls = _run(TAG, {SSF_RULE: page})
    assert out.status == "found" and out.match["via"] == "brand_rule"
    assert out.match["url"] == SSF_PAGE and out.match["source"] == "mall"
    assert calls["search"] == 0


def test_rule_url_containing_code_is_not_evidence_by_itself():
    # 주소는 우리가 품번으로 만든 것 — 페이지에 품번이 없으면 찾은 게 아니다.
    page = PageView(ok=True, final_url=SSF_RULE, raw_text="상품을 찾을 수 없습니다 " + "안내 " * 100,
                    body_chars=900)
    out, calls = _run(TAG, {SSF_RULE: page})
    assert out.status != "found" and calls["search"] == 1


def test_seller_hint_goes_into_search_prompt():
    tag = {**TAG, "brand": "HAZZYS", "product_code": "HSSW5F123"}
    out, calls = _run(tag, {})
    assert calls["render"] == []  # LF몰은 아직 주소 규칙이 없다
    assert "lfmall.co.kr" in calls["prompt"]
    assert out.tag["brand_canonical"] == "hazzys"


def test_low_time_skips_rule_to_leave_room_for_search():
    _, calls = _run(TAG, {}, time_left=9.0)
    assert calls["render"] == [] and calls["search"] == 1
