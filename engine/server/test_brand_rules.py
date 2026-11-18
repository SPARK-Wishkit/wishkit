"""brand_rules.py + identify()의 브랜드 규칙 단계 테스트. 실제 규칙 파일(brand_rules.json)을 그대로 읽는다."""
import asyncio

from brand_rules import (
    candidate_urls,
    canonical_brand,
    category_of,
    load_rules,
    plan_for,
    seller_hints,
)
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
    # 컨템포러리 브랜드는 모회사 몰(SSF) 규칙만 — 무신사는 입점이 확인된 브랜드만 직접 연다
    assert urls[0].url == "https://m.ssfshop.com/public/goods/detail/QQ6X39EP20/sapView"
    assert urls[0].mall == "ssf" and not any("musinsa" in u.url for u in urls)


def test_new_balance_style_and_color_split():
    urls = candidate_urls({"brand": "NEW BALANCE", "product_code": "NBNQG41923-01"})
    # 뉴발란스: 무신사에 브랜드 페이지가 없어 전체 검색("뉴발란스 스타일번호")이 먼저, 공식몰 규칙은 그다음
    assert urls[0].url == "https://www.musinsa.com/search/goods?keyword=%EB%89%B4%EB%B0%9C%EB%9E%80%EC%8A%A4%20NBNQG41923"
    assert any(u.url.endswith("styleCode=NBNQG41923&colCode=01") for u in urls)


def test_new_balance_code_without_color_has_no_url():
    urls = candidate_urls({"brand": "NEW BALANCE", "product_code": "NBNQG41923"})
    assert not any("nbkorea.com" in u.url for u in urls)


def test_lf_and_handsome_urls_from_code():
    lf = candidate_urls({"brand": "HAZZYS", "product_code": "JNJU6D701BK"})
    assert lf[0].url == "https://www.lfmall.co.kr/app/product/JNJU6D701BK"
    hs = candidate_urls({"brand": "SYSTEM", "product_code": "SY2GBRJC211WM"})
    assert hs[0].url == "https://www.thehandsome.com/ko/PM/productDetail/SY2GBRJC211WM"


def test_si_village_uses_search_page_rule():
    urls = candidate_urls({"brand": "VOV", "product_code": "46B6301558"})
    assert urls[0].kind == "search"
    assert urls[0].url == "https://m.shinsegaev.com/search/totalSearch.siv?search_kwd=46B6301558"
    assert seller_hints({"brand": "VOV"})[0] == "shinsegaev.com"


def test_mall_without_rule_still_hints_seller():
    tag = {"brand": "KOLON SPORT", "product_code": "JWJPW24501"}
    assert not any("kolonmall.com" in u.url for u in candidate_urls(tag))  # 코오롱몰은 주소 규칙 없음
    # 스포츠 분류: 공식몰(모름) → 모회사 몰 → 편집숍
    assert seller_hints(tag) == ["kolonmall.com", *EDITSHOPS]


EDITSHOPS = ["musinsa.com", "29cm.co.kr", "4910.kr", "wconcept.co.kr"]


def test_categories_decide_where_to_look():
    # 컨템포러리(백화점 층 기준) → 모회사 몰부터
    assert category_of({"brand": "BEAKER"}) == "contemporary"
    assert seller_hints({"brand": "BEAKER"})[:2] == ["ssfshop.com", "lotteon.com"]
    # SPA → 공식몰부터
    assert seller_hints({"brand": "ZARA"}) == ["zara.com"]
    # K디자이너 → 편집숍부터
    assert seller_hints({"brand": "PIEDPIPER"}) == EDITSHOPS


def test_unknown_brand_finds_official_site_first():
    plan = plan_for({"brand": "처음보는브랜드"})
    assert plan.category == "unknown" and plan.order[0] == "official"
    assert plan.find_official_first  # 도메인을 모르니 검색에서 공식 홈페이지부터
    assert seller_hints({"brand": None}) == EDITSHOPS  # 공식몰 다음 순서


def test_editshop_listing_moves_that_shop_first():
    rules = load_rules()
    patched = {**rules, "editshop_brands": {**rules["editshop_brands"], "4910.kr": ["piedpiper"]}}
    assert seller_hints({"brand": "PIEDPIPER"}, patched)[0] == "4910.kr"


def test_unknown_brand_with_known_company_uses_parent_mall_rule():
    # 목록에 없는 삼성물산 브랜드라도 태그의 회사명으로 SSF 규칙이 걸린다.
    tag = {"brand": "SIYAZU", "company": "삼성물산(주)", "product_code": "AB12CD34"}
    plan = plan_for(tag)
    assert plan.mall == "ssf" and plan.decided_by.startswith("태그 회사명")
    assert candidate_urls(tag)[0].url.endswith("/AB12CD34/sapView")


def test_unknown_brand_with_printed_website_is_official_channel():
    tag = {"brand": "NEWBRAND", "website": "www.newbrand.co.kr", "product_code": "NB-001"}
    plan = plan_for(tag)
    assert plan.official_domain == "newbrand.co.kr" and not plan.find_official_first
    assert seller_hints(tag) == ["newbrand.co.kr", *EDITSHOPS]


def test_instagram_on_tag_is_not_a_website():
    plan = plan_for({"brand": "NEWBRAND", "website": "instagram.com/newbrand"})
    assert plan.official_domain is None and plan.find_official_first


def test_known_brand_wins_over_company():
    plan = plan_for({"brand": "BEAKER", "company": "(주)한섬"})
    assert plan.mall == "ssf" and plan.decided_by == "브랜드 목록"


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
    tag = {**TAG, "brand": "KOLON SPORT", "product_code": "JWJPW24501"}
    out, calls = _run(tag, {})
    assert not any("kolonmall.com" in u for u in calls["render"])  # 코오롱몰은 아직 주소 규칙이 없다
    assert "kolonmall.com" in calls["prompt"]
    assert out.tag["brand_canonical"] == "kolon sport" and out.tag["brand_category"] == "sports"


def test_unknown_brand_search_prompt_asks_for_official_site_first():
    tag = {**TAG, "brand": "처음보는브랜드", "product_code": "XX-100"}
    _, calls = _run(tag, {})
    assert "공식 홈페이지(자사몰)를 먼저" in calls["prompt"]


SIV_SEARCH = "https://m.shinsegaev.com/search/totalSearch.siv?search_kwd=46B6301558"
SIV_PRODUCT = "https://m.shinsegaev.com/goods/initDetailGoods.siv?goods_no=2608981585"


def test_search_rule_opens_first_product_and_verifies_code():
    tag = {**TAG, "brand": "VOV", "product_code": "46B6301558"}
    search_page = PageView(ok=True, final_url=SIV_SEARCH, raw_text="검색 결과 1개",
                           html='<a href="/goods/initDetailGoods.siv?goods_no=2608981585&amp;x=1">코트</a>')
    product = PageView(ok=True, final_url=SIV_PRODUCT, raw_text="상품번호 46B6301558 359,000원 " + "설명 " * 100,
                       body_chars=900)
    out, calls = _run(tag, {SIV_SEARCH: search_page, SIV_PRODUCT: product}, time_left=24.0)
    assert calls["render"] == [SIV_SEARCH, SIV_PRODUCT]
    assert out.status == "found" and out.match["url"] == SIV_PRODUCT and out.match["via"] == "brand_rule"
    assert calls["search"] == 0


def test_search_rule_with_no_results_falls_back_to_search():
    tag = {**TAG, "brand": "VOV", "product_code": "46B6301558"}
    empty = PageView(ok=True, final_url=SIV_SEARCH, raw_text="검색 결과가 없습니다", html="<div>없음</div>")
    out, calls = _run(tag, {SIV_SEARCH: empty}, time_left=24.0)
    assert calls["render"] == [SIV_SEARCH] and calls["search"] == 1
    assert any("검색 결과에 상품 없음" in c["reason"] for c in out.checked)


def test_official_brand_domain_is_used_as_official_in_search():
    # 모델이 공식몰을 모른다고 해도, 규칙 파일의 공식몰(zara.com) 상세 페이지를 받아들인다.
    tag = {**TAG, "brand": "ZARA", "product_code": "0248/707/959"}
    out, _ = _run(tag, {})
    assert out.official_domain == "zara.com"


def test_low_time_skips_rule_to_leave_room_for_search():
    _, calls = _run(TAG, {}, time_left=9.0)
    assert calls["render"] == [] and calls["search"] == 1



# ── 2026-11-09 실제 83장 테스트에서 나온 경우 ──

def test_vans_brand_from_code_when_brand_missing():
    plan = plan_for({"brand": None, "product_code": "VN00100FPWT"})
    assert plan.brand == "vans" and plan.decided_by == "품번 모양"


def test_new_balance_misread_as_nba_is_fixed_by_code():
    assert plan_for({"brand": "NBA", "product_code": "NBMLG4W952-00"}).brand == "new balance"


def test_adidas_real_article_is_promoted_from_other_codes():
    from brand_rules import promote_code
    tag = {"brand": "adidas", "product_code": None, "other_codes": ["96000195", "KR9552", "0902368958"]}
    assert promote_code(tag) == "KR9552"
    assert promote_code({"brand": "adidas", "product_code": "KH4509"}) is None  # 이미 맞는 모양


def test_unreadable_rule_page_becomes_needs_confirm_after_search_fails():
    nb = "https://www.nbkorea.com/product/productDetail.action?styleCode=NBNQG41923&colCode=01"
    tag = {**TAG, "brand": "NEW BALANCE", "product_code": "NBNQG41923-01"}
    blank = PageView(ok=True, final_url="about:blank", raw_text="", body_chars=0)
    out, calls = _run(tag, {nb: blank}, time_left=24.0)
    assert calls["search"] == 1
    assert out.status == "needs_confirm" and out.match["url"] == nb and out.match["via"] == "brand_rule"


def test_inferred_brand_is_written_back_to_tag():
    tag = {**TAG, "brand": None, "product_code": "VN000T78RKZ"}
    out, _ = _run(tag, {})
    assert out.tag["brand"] == "VANS" and out.tag["brand_ocr"] is None


def test_musinsa_in_brand_search_url():
    urls = candidate_urls({"brand": "PIEDPIPER", "product_code": "PP263LT01MT"})
    assert urls[0].url == ("https://www.musinsa.com/brand/piedpiper/products"
                           "?keyword=PP263LT01MT&keywordType=keyword&gf=A")


def test_korean_only_brand_uses_rule_name_for_musinsa_slug():
    urls = candidate_urls({"brand": "파이드파이퍼", "product_code": "PP263LT01MT"})
    assert "/brand/piedpiper/products" in urls[0].url


def test_new_balance_written_differently_on_tags_is_one_brand():
    for raw in ("new", "NB", "NEW BALANCE", "new balance", "뉴발란스"):
        assert canonical_brand(raw) == "new balance", raw


def test_musinsa_brand_page_name_can_differ_from_brand():
    urls = candidate_urls({"brand": "AMOU", "product_code": "AM26FWJP07BK001"})
    assert "/brand/machineboymachine/products?keyword=AM26FWJP07BK001" in urls[0].url


def test_no_musinsa_brand_page_skips_in_brand_search():
    urls = candidate_urls({"brand": "OAKLEY", "product_code": "FOS902280"})
    assert not any("/brand/" in u.url for u in urls)


def test_matin_kim_tag_reads_kimmatin_but_musinsa_uses_matinkim():
    urls = candidate_urls({"brand": "KIMMATIN", "product_code": "KM269OFU001M"})
    assert "/brand/matinkim/products?keyword=KM269OFU001M" in urls[0].url


def test_musinsa_only_for_young_brands_or_confirmed_ones():
    # 반스: 무신사에 없고 공식몰에만 있음(2026-11-10 사용자 확인) → 무신사를 직접 열지 않는다
    assert not any("musinsa" in u.url for u in candidate_urls({"brand": "VANS", "product_code": "VN000P79EMP"}))
    # 모르는 브랜드: 공식몰부터(검색 단계) — 무신사를 직접 열지 않는다
    assert candidate_urls({"brand": "처음보는브랜드", "product_code": "AB12345"}) == []
    # 아디다스: 스포츠지만 무신사 입점이 확인돼(editshop_brands) 무신사를 연다
    assert any("musinsa" in u.url for u in candidate_urls({"brand": "adidas", "product_code": "KR9712"}))
    # 젊은 브랜드는 그대로 무신사부터
    assert "musinsa" in candidate_urls({"brand": "PIEDPIPER", "product_code": "PP263LT01MT"})[0].url
