"""
tag_identify.py 단위 테스트. Gemini·브라우저는 가짜로 바꿔 끼운다(실제 호출 없음).
실제 태그 사진으로 정확도를 재는 건 tools/tag_identify_check.py로 한다.
"""
import asyncio

import pytest

from providers import ProviderResult
from tag_identify import (
    IdentifyError,
    PageView,
    classify_host,
    identify,
    normalize_code,
    page_matches,
    parse_search_output,
)

@pytest.fixture(autouse=True)
def _render_verify_on(monkeypatch):
    """이 파일의 기존 테스트는 서버 렌더링 확인 방식(IDENTIFY_RENDER_VERIFY=1)을 검증한다.
    검색 결과만으로 판단하는 기본 방식은 맨 아래 테스트들이 verify_by_render=False로 따로 본다."""
    import config
    monkeypatch.setattr(config, "IDENTIFY_RENDER_VERIFY", True)


NIKE_TAG = {
    "is_product_tag": True,
    "brand": "NIKE",
    "product_code": "DV1234-100",
    "barcode": None,
    "product_name": "에어 포스 1 '07",
    "color": "WHITE",
    "size": "270",
    "tag_price": 139000,
    "confidence": "high",
}

REDIRECT = "https://vertexaisearch.cloud.google.com/grounding-api-redirect/abc"


def _ok(data):
    return ProviderResult("fake", "fake", True, data, 1)


def _run(coro):
    return asyncio.run(coro)


# ── 순수 로직 ──

def test_normalize_code_ignores_separators_and_case():
    assert normalize_code("DV1234-100") == normalize_code("dv1234 100") == "dv1234100"


def test_classify_host():
    assert classify_host("nike.com", "nike.com") == "official"
    assert classify_host("m.nike.com", "nike.com") == "official"
    assert classify_host("musinsa.com", "nike.com") == "mall"
    assert classify_host("blog.naver.com", "nike.com") == "other"
    assert classify_host("random-shop.kr", "nike.com") == "other"
    assert classify_host("notnike.com", "nike.com") == "other"  # 접미사만 같은 다른 도메인


def test_parse_search_output_puts_official_first_and_drops_blogs():
    text = """OFFICIAL_DOMAIN: nike.com
URL: https://www.musinsa.com/products/123
URL: https://blog.naver.com/someone/1
URL: https://www.nike.com/kr/t/air-force-1/DV1234-100
"""
    sources = [{"uri": REDIRECT, "title": "kream.co.kr"}]
    official, cands = parse_search_output(text, sources)
    assert official == "nike.com"
    assert [c.source for c in cands] == ["official", "mall", "mall"]
    assert cands[0].url == "https://www.nike.com/kr/t/air-force-1/DV1234-100"
    assert cands[2].url == REDIRECT and cands[2].hint_host == "kream.co.kr"


def test_parse_search_output_rejects_mall_as_official_domain():
    official, cands = parse_search_output("OFFICIAL_DOMAIN: musinsa.com\nURL: https://www.musinsa.com/products/1", [])
    assert official is None
    assert cands[0].source == "mall"


def test_page_matches_by_code_even_with_different_separators():
    assert page_matches(NIKE_TAG, "스타일: DV1234 100 · 화이트", "https://x") == "product_code"
    assert page_matches(NIKE_TAG, "아무 글자", "https://www.nike.com/kr/t/af1/DV1234-100") == "product_code"


def test_page_matches_rejects_similar_name_when_code_missing_on_page():
    # 품번이 있는데 페이지에 없으면 — 이름이 같아도 다른 색상/모델일 수 있으니 인정하지 않는다.
    assert page_matches(NIKE_TAG, "NIKE 에어 포스 1 '07 블랙 DV0000-001", "https://x") is None


def test_page_matches_by_name_only_when_tag_has_no_code():
    tag = {**NIKE_TAG, "product_code": None, "barcode": None, "product_name": "소프트 헨리넥 반팔 티셔츠"}
    assert page_matches(tag, "NIKE 소프트 헨리넥 반팔 티셔츠 브라운", "https://x") == "name"
    assert page_matches(tag, "ADIDAS 소프트 헨리넥 반팔 티셔츠", "https://x") is None  # 브랜드 불일치


# ── 오케스트레이션 ──

def _fakes(search_text, pages, sources=None):
    calls = {"render": []}

    async def read_tag(img, mime):
        return _ok(dict(NIKE_TAG))

    async def search(tag):
        return _ok({"text": search_text, "sources": sources or []})

    async def render_page(url):
        calls["render"].append(url)
        return pages.get(url, PageView(ok=False, final_url=url, raw_text="", error="없음"))

    return read_tag, search, render_page, calls


def test_identify_prefers_official_site_with_code():
    official = "https://www.nike.com/kr/t/af1/DV1234-100"
    mall = "https://www.musinsa.com/products/1"
    read_tag, search, render_page, calls = _fakes(
        f"OFFICIAL_DOMAIN: nike.com\nURL: {mall}\nURL: {official}",
        {
            official: PageView(True, official, "에어 포스 1 DV1234-100"),
            mall: PageView(True, mall, "나이키 에어포스 DV1234-100"),
        },
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "found"
    assert out.match["source"] == "official"
    assert out.match["url"] == official
    assert calls["render"] == [official]  # 공식몰에서 바로 확인됐으니 쇼핑몰은 안 열어 봄


def test_identify_falls_back_to_mall_when_official_page_lacks_code():
    official = "https://www.nike.com/kr/t/af1/other"
    mall = "https://www.musinsa.com/products/1"
    read_tag, search, render_page, _ = _fakes(
        f"OFFICIAL_DOMAIN: nike.com\nURL: {official}\nURL: {mall}",
        {
            official: PageView(True, official, "다른 상품 DV9999-001"),
            mall: PageView(True, mall, "나이키 에어포스 DV1234-100"),
        },
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "found"
    assert out.match["source"] == "mall"
    assert out.match["verified_by"] == "product_code"


def test_identify_uses_final_url_after_grounding_redirect():
    final = "https://www.nike.com/kr/t/af1/DV1234-100"
    read_tag, search, render_page, _ = _fakes(
        "OFFICIAL_DOMAIN: nike.com",
        {REDIRECT: PageView(True, final, "DV1234-100")},
        sources=[{"uri": REDIRECT, "title": "nike.com"}],
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "found"
    assert out.match["url"] == final
    assert out.match["source"] == "official"


def test_identify_not_found_when_nothing_verifies():
    url = "https://www.musinsa.com/products/1"
    read_tag, search, render_page, _ = _fakes(
        f"OFFICIAL_DOMAIN: 없음\nURL: {url}", {url: PageView(True, url, "전혀 다른 상품")}
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "not_found"
    assert out.match is None
    assert out.tag["product_code"] == "DV1234-100"  # 앱이 이름이라도 채울 수 있게 태그는 돌려준다


def test_identify_skips_renders_when_out_of_time():
    url = "https://www.musinsa.com/products/1"
    read_tag, search, render_page, calls = _fakes(
        f"URL: {url}", {url: PageView(True, url, "DV1234-100")}
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 3))
    # 열어 보지 못한 후보는 버리지 않고 "확인 필요"로 돌려준다(앱이 사용자에게 묻는다).
    assert out.status == "needs_confirm"
    assert out.match["url"] == url and out.match["verified_by"] == "search"
    assert calls["render"] == []


def test_identify_not_a_tag():
    async def read_tag(img, mime):
        return _ok({**NIKE_TAG, "is_product_tag": False})

    async def never(*_):
        raise AssertionError("검색하면 안 됨")

    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=never,
                        render_page=never, time_left=lambda: 40))
    assert out.status == "not_a_tag"


def test_identify_raises_when_tag_reading_fails():
    async def read_tag(img, mime):
        return ProviderResult("fake", "fake", False, None, 1, error="boom")

    with pytest.raises(IdentifyError):
        _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=None,
                      render_page=None, time_left=lambda: 40))


# ── 바코드 검증 · 태그 가격 · 후보 순위 (2026-10-23 추가) ──

def _tag_reader(tag):
    async def read_tag(img, mime):
        return _ok(dict(tag))
    return read_tag


def test_identify_drops_barcode_with_wrong_check_digit():
    seen = {}

    async def search(tag):
        seen["tag"] = tag
        return _ok({"text": "", "sources": []})

    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader({**NIKE_TAG, "barcode": "8801234567890"}),
                        search=search, render_page=None, time_left=lambda: 40))
    assert seen["tag"]["barcode"] is None
    assert out.tag["barcode_rejected"] == "8801234567890"


def test_identify_prefers_page_showing_tag_price_among_equal_matches():
    a, b = "https://www.musinsa.com/products/1", "https://www.29cm.co.kr/products/2"
    read_tag, search, render_page, _ = _fakes(
        f"OFFICIAL_DOMAIN: 없음\nURL: {a}\nURL: {b}",
        {a: PageView(True, a, "DV1234-100 99,000원"), b: PageView(True, b, "DV1234-100 정가 139,000원")},
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.match["url"] == b and out.match["tag_price_seen"] is True


def test_official_base_code_match_beats_mall_full_code_match():
    official, mall = "https://www.nike.com/kr/t/af1/x", "https://www.musinsa.com/products/1"
    read_tag, search, render_page, _ = _fakes(
        f"OFFICIAL_DOMAIN: nike.com\nURL: {mall}\nURL: {official}",
        {mall: PageView(True, mall, "나이키 DV1234-100"), official: PageView(True, official, "스타일: DV1234")},
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.match["url"] == official and out.match["verified_by"] == "product_code_base"


def test_mall_code_match_still_beats_official_name_only_match():
    tag = {**NIKE_TAG, "product_code": None, "barcode": None, "product_name": "소프트 헨리넥 반팔 티셔츠"}
    official, mall = "https://www.nike.com/kr/t/x", "https://www.musinsa.com/products/1"

    async def search(t):
        return _ok({"text": f"OFFICIAL_DOMAIN: nike.com\nURL: {official}\nURL: {mall}", "sources": []})

    pages = {official: PageView(True, official, "NIKE 소프트 헨리넥 반팔 티셔츠"),
             mall: PageView(True, mall, "NIKE 소프트 헨리넥 반팔 티셔츠")}

    async def render_page(url):
        return pages[url]

    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(tag), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.match["url"] == official and out.match["verified_by"] == "name"  # 둘 다 이름 → 공식몰


# ── 무신사 검색 단계를 뺀 뒤 (2026-10-28) ──

TAG_1993 = {**NIKE_TAG, "brand": "1993STUDIO", "product_code": "93251TTL1202", "barcode": None,
            "other_codes": [], "product_name": None, "tag_price": 29900}


def test_google_search_finds_official_site_without_musinsa_step():
    official = "https://1993studio.com/product/detail.html?product_no=1"
    rendered = []

    async def search(tag):
        return _ok({"text": f"OFFICIAL_DOMAIN: 1993studio.com\nURL: {official}", "sources": []})

    async def render_page(url):
        rendered.append(url)
        return PageView(True, url, "1993STUDIO 베이직 우먼 롱슬리브 93251TTL1202 29,900원")

    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(TAG_1993), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "found" and out.match["source"] == "official"
    assert rendered == [official]  # 무신사 검색 페이지를 열지 않는다


def test_google_search_429_gives_quota_note():
    async def search(tag):
        return ProviderResult("s", "m", False, None, 1, "ClientError: 429 RESOURCE_EXHAUSTED")

    async def render_page(url):
        raise AssertionError("검색이 실패하면 페이지를 열지 않는다")

    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(TAG_1993), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "not_found" and "한도" in out.note


# ── 2026-11-02: 몰 우선순위 · 사이트마다 하나 · 화면 밖 품번 ──────────────

def test_parse_search_output_orders_malls_by_priority():
    text = """OFFICIAL_DOMAIN: nike.com
URL: https://www.29cm.co.kr/products/9
URL: https://a-bly.com/goods/3
URL: https://www.ssfshop.com/x/GM1
URL: https://www.musinsa.com/products/1
URL: https://www.nike.com/kr/t/af1/DV1234-100
"""
    _, cands = parse_search_output(text, [])
    assert [c.hint_host for c in cands] == [
        "nike.com", "musinsa.com", "ssfshop.com", "a-bly.com", "29cm.co.kr",
    ]


def test_parse_search_output_keeps_one_candidate_per_site():
    text = """OFFICIAL_DOMAIN: nike.com
URL: https://www.musinsa.com/products/1
URL: https://m.musinsa.com/products/2
URL: https://www.nike.com/kr/t/a
URL: https://www.nike.com/kr/t/b
"""
    sources = [{"uri": REDIRECT, "title": "musinsa.com"}]
    _, cands = parse_search_output(text, sources)
    assert [c.url for c in cands] == ["https://www.nike.com/kr/t/a", "https://www.musinsa.com/products/1"]


def test_page_matches_uses_hidden_code_hints():
    tag = dict(NIKE_TAG)
    assert page_matches(tag, "나이키 에어포스 1 '07", "https://x.com/p/1") is None
    hints = ["https://img.x.com/goods/DV1234-100_01.jpg"]
    assert page_matches(tag, "나이키 에어포스 1 '07", "https://x.com/p/1", hints) == "product_code"


def test_identify_confirms_page_by_structured_sku_and_marks_reason():
    url = "https://www.musinsa.com/products/1"
    page = PageView(True, url, "나이키 에어포스 1 '07 139,000원", code_hints=["DV1234-100"])
    read_tag, search, render_page, _ = _fakes(f"OFFICIAL_DOMAIN: 없음\nURL: {url}", {url: page})
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "found" and out.match["verified_by"] == "product_code"
    assert out.checked[0]["reason"] == "product_code (화면 밖 정보)"


# ── 2026-11-02: 못 읽은 후보는 needs_confirm ─────────────────

SSF = "https://www.ssfshop.com/BEAKER/GM0026101660266/good?dspCtgNo="
BEAKER_TAG = {**NIKE_TAG, "brand": "BEAKER", "product_code": "QQ6X39EP20 - DEP",
              "other_codes": ["QQ6X39EP20 F"], "product_name": None}


def test_blank_page_is_unread_not_wrong_product():
    """실제 로그(2026-11-02): SSF샵이 서버에 빈 화면을 줘서 품번을 못 찾음 → 확인 필요."""
    pages = {SSF: PageView(True, SSF, "SSF SHOP", body_chars=0)}
    read_tag, search, render_page, _ = _fakes(f"OFFICIAL_DOMAIN: 없음\nURL: {SSF}", pages)
    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(BEAKER_TAG), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "needs_confirm"
    assert out.match == {"url": SSF, "host": "ssfshop.com", "source": "mall",
                         "verified_by": "search", "tag_price_seen": None}
    assert out.checked[0]["verified"] is None and "비어 있음" in out.checked[0]["reason"]


def test_same_page_with_code_is_found():
    pages = {SSF: PageView(True, SSF, "[BEAKER] EPINGLER Laced Hoodie QQ6X39EP20 299,000원", body_chars=900)}
    _, search, render_page, _ = _fakes(f"OFFICIAL_DOMAIN: 없음\nURL: {SSF}", pages)
    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(BEAKER_TAG), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "found" and out.match["verified_by"] == "product_code_base"


def test_page_read_without_code_stays_not_found():
    """페이지를 제대로 읽었는데 품번이 없으면 다른 상품일 수 있다 — 확인 필요로 올리지 않는다."""
    pages = {SSF: PageView(True, SSF, "다른 후디 189,000원 " + "설명 " * 200, body_chars=1200)}
    _, search, render_page, _ = _fakes(f"OFFICIAL_DOMAIN: 없음\nURL: {SSF}", pages)
    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(BEAKER_TAG), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "not_found" and out.match is None


def test_verified_page_beats_unread_candidate():
    blocked, ok = "https://www.musinsa.com/products/1", "https://www.ssfshop.com/x/GM1"
    pages = {blocked: PageView(False, blocked, "", error="렌더링 실패/차단"),
             ok: PageView(True, ok, "QQ6X39EP20", body_chars=500)}
    _, search, render_page, _ = _fakes(f"OFFICIAL_DOMAIN: 없음\nURL: {blocked}\nURL: {ok}", pages)
    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(BEAKER_TAG), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "found" and out.match["url"] == ok


def test_unread_redirect_address_is_not_offered():
    """구글 리다이렉트 주소만 남으면 실제 상품 주소를 몰라서 확인 필요로도 줄 수 없다."""
    _, search, render_page, _ = _fakes("OFFICIAL_DOMAIN: 없음", {}, sources=[{"uri": REDIRECT, "title": "musinsa.com"}])
    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(BEAKER_TAG), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "not_found"



def test_page_without_any_price_is_unread():
    """실제 로그(2026-11-02 06:02): SSF가 본문은 있는데 상품 정보·가격이 없는 화면을 줌 → 확인 필요."""
    text = "SSF SHOP 로그인 장바구니 고객센터 " + "메뉴 " * 100
    pages = {SSF: PageView(True, SSF, text, body_chars=len(text))}
    _, search, render_page, _ = _fakes(f"OFFICIAL_DOMAIN: 없음\nURL: {SSF}", pages)
    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(BEAKER_TAG), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "needs_confirm"
    assert out.checked[0]["reason"].startswith("상품 정보가 안 보임")


def test_parse_search_output_strips_markdown_junk_from_urls():
    text = """OFFICIAL_DOMAIN: 없음
URL: https://www.ssfshop.com/BEAKER/GM0026101660266/good?dspCtgNo=GNB41`
URL: `https://www.musinsa.com/products/1`
URL: **https://www.29cm.co.kr/products/2**
"""
    _, cands = parse_search_output(text, [])
    assert [c.url for c in cands] == [
        "https://www.musinsa.com/products/1",
        "https://www.ssfshop.com/BEAKER/GM0026101660266/good?dspCtgNo=GNB41",
        "https://www.29cm.co.kr/products/2",
    ]



# ── 2026-11-02: 기본 방식 — 서버에서 열지 않고 검색 제목·주소로 판단 ──────────

SSF_TITLE = "[BEAKER] EPINGLER | Laced Hoodie - Oatmeal QQ6X39EP20"
SSF_SOURCES = [{"uri": REDIRECT, "title": "ssfshop.com"}]


def _search_only(text, tag=BEAKER_TAG, sources=SSF_SOURCES):
    calls = {"render": []}

    async def search(t):
        return _ok({"text": text, "sources": sources})

    async def render_page(url):
        calls["render"].append(url)
        raise AssertionError("기본 방식에서는 서버가 페이지를 열면 안 된다")

    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(tag), search=search,
                        render_page=render_page, time_left=lambda: 40, verify_by_render=False))
    return out, calls


def test_search_title_with_code_is_found_without_rendering():
    out, calls = _search_only(f"OFFICIAL_DOMAIN: 없음\nURL: {SSF} | 제목: {SSF_TITLE}")
    assert calls["render"] == []
    assert out.status == "found"
    assert out.match["url"] == SSF and out.match["verified_by"] == "product_code_base"
    assert out.match["title"] == SSF_TITLE
    assert out.checked[0]["reason"] == "product_code_base (검색 제목·설명)"


def test_code_in_url_is_found_even_without_title():
    url = "https://www.nike.com/kr/t/air-force-1/DV1234-100"
    out, _ = _search_only(f"OFFICIAL_DOMAIN: nike.com\nURL: {url}", tag=NIKE_TAG, sources=[])
    assert out.status == "found" and out.match["verified_by"] == "product_code"


def test_title_from_site_not_in_search_sources_is_not_trusted():
    """모델이 지어냈을 수 있는 제목 — 그 사이트가 실제 검색 출처에 없으면 확인 필요로만."""
    out, _ = _search_only(f"OFFICIAL_DOMAIN: 없음\nURL: {SSF} | 제목: {SSF_TITLE}", sources=[])
    assert out.status == "needs_confirm" and out.match["verified_by"] == "search"


def test_title_without_code_gives_needs_confirm():
    out, _ = _search_only(f"OFFICIAL_DOMAIN: 없음\nURL: {SSF} | 제목: [BEAKER] 레이스 후디 오트밀")
    assert out.status == "needs_confirm" and out.match["url"] == SSF


def test_official_title_match_beats_mall_title_match():
    official = "https://kimmatin.com/product/high-neck-shearling-jacket-in-black/886/"
    mall = "https://www.wconcept.co.kr/Product/306766465"
    tag = {**NIKE_TAG, "brand": "KIMMATIN", "product_code": "KM269OFU001M", "other_codes": []}
    text = (f"OFFICIAL_DOMAIN: kimmatin.com\nURL: {mall} | 제목: 킴마틴 시어링 자켓 KM269OFU001M\n"
            f"URL: {official} | 제목: HIGH NECK SHEARLING JACKET KM269OFU001M")
    sources = [{"uri": REDIRECT, "title": "kimmatin.com"}, {"uri": REDIRECT, "title": "wconcept.co.kr"}]
    out, _ = _search_only(text, tag=tag, sources=sources)
    assert out.status == "found" and out.match["source"] == "official"


def test_only_redirect_candidates_is_not_found():
    out, _ = _search_only("OFFICIAL_DOMAIN: 없음", sources=SSF_SOURCES)
    assert out.status == "not_found"


def test_parse_search_output_reads_titles():
    _, cands = parse_search_output(f"URL: {SSF} | 제목: {SSF_TITLE}\nURL: https://www.musinsa.com/products/1 | 제목: 없음", [])
    assert {c.url: c.title for c in cands} == {"https://www.musinsa.com/products/1": "", SSF: SSF_TITLE}



# ── 2026-11-02: SSF 제목에 상품명만 있고 품번은 없을 때 ─────────────────

SSF_NAME_ONLY = "[BEAKER] EPINGLER | Laced Hoodie - Oatmeal | SSF SHOP"


def test_title_matching_searched_product_name_is_found_as_name():
    """검색으로 확인한 상품 이름(PRODUCT_NAME)과 제목이 맞으면 품번이 없어도 찾음('name' → 앱이 확인 요청)."""
    text = (f"OFFICIAL_DOMAIN: 없음\nPRODUCT_NAME: BEAKER EPINGLER Laced Hoodie - Oatmeal\n"
            f"URL: {SSF} | 제목: {SSF_NAME_ONLY} | 설명: 따뜻한 울 혼방 소재에 레이스 패널을 더한 후디")
    out, calls = _search_only(text)
    assert calls["render"] == []
    assert out.status == "found" and out.match["url"] == SSF
    assert out.match["verified_by"] == "name"
    assert out.checked[0]["reason"] == "name (검색 상품명 일치)"


def test_code_in_snippet_is_found():
    text = (f"OFFICIAL_DOMAIN: 없음\nURL: {SSF} | 제목: {SSF_NAME_ONLY} | "
            f"설명: 품번 QQ6X39EP20 · 울 혼방 후디")
    out, _ = _search_only(text)
    assert out.status == "found" and out.match["verified_by"] == "product_code_base"


def test_title_of_other_product_is_not_name_match():
    text = (f"OFFICIAL_DOMAIN: 없음\nPRODUCT_NAME: BEAKER EPINGLER Laced Hoodie - Oatmeal\n"
            f"URL: {SSF} | 제목: [BEAKER] 크루넥 니트 - 네이비 | 설명: 없음")
    out, _ = _search_only(text)
    assert out.status == "needs_confirm"


def test_code_match_beats_name_match():
    other = "https://www.musinsa.com/products/1"
    text = (f"OFFICIAL_DOMAIN: 없음\nPRODUCT_NAME: BEAKER EPINGLER Laced Hoodie - Oatmeal\n"
            f"URL: {SSF} | 제목: {SSF_NAME_ONLY} | 설명: 없음\n"
            f"URL: {other} | 제목: 에핑글러 레이스 후디 QQ6X39EP20 | 설명: 없음")
    sources = SSF_SOURCES + [{"uri": REDIRECT, "title": "musinsa.com"}]
    out, _ = _search_only(text, sources=sources)
    assert out.status == "found" and out.match["url"] == other
    assert out.match["verified_by"] == "product_code_base"


def test_parse_keeps_pipes_inside_title():
    _, cands = parse_search_output(f"URL: {SSF} | 제목: {SSF_NAME_ONLY} | 설명: 울 후디", [])
    assert cands[0].title == SSF_NAME_ONLY and cands[0].snippet == "울 후디"
