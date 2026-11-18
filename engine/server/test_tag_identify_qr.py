"""tag_identify.identify()의 QR 단계 테스트. Gemini·브라우저·디코더·주소 따라가기는 전부 가짜.

순서: QR로 확인 → (안 되면) 품번·브랜드 검색 → (그래도 안 되면) not_found(앱이 직접 기록 화면으로).
"""
import asyncio

from providers import ProviderResult
from qr_codes import DecodedCodes, QrPayload, QrResolution
from tag_identify import PageView, identify

TAG = {
    "is_product_tag": True, "brand": "NIKE", "product_code": "DV1234-100", "other_codes": [],
    "barcode": None, "product_name": "에어 포스 1 '07", "color": "WHITE", "size": "270",
    "tag_price": 139000, "confidence": "high",
}
PRODUCT_PAGE = "상품 상세 · 스타일 DV1234-100 · 139,000원 " + "설명 " * 120
OTHER_PAGE = "다른 상품 · 스타일 AB0000-001 · 99,000원 " + "설명 " * 120


def _ok(data):
    return ProviderResult("fake", "fake", True, data, 1)


def _run(coro):
    return asyncio.run(coro)


def _codes(*urls, barcodes=(), text_codes=()):
    qr = [QrPayload(u, "url", url=u) for u in urls]
    if text_codes:
        qr.append(QrPayload(" ".join(text_codes), "text", codes=list(text_codes)))
    return DecodedCodes(qr=qr, barcodes=list(barcodes))


def _run_identify(*, codes, pages, redirects=None, search_text="", tag=None, unsafe=(), time_left=20.0):
    calls = {"search": 0, "render": [], "resolve": []}

    async def read_tag(img, mime):
        return _ok(dict(tag or TAG))

    async def read_codes(img):
        return codes

    async def resolve_url(url):
        calls["resolve"].append(url)
        if url in unsafe:
            return QrResolution(url, url, ok=False, error="공개 웹 주소가 아님", unsafe=True)
        return QrResolution(url, (redirects or {}).get(url, url), ok=True)

    async def search(t):
        calls["search"] += 1
        calls["search_tag"] = t
        return _ok({"text": search_text, "sources": []})

    async def render_page(url):
        calls["render"].append(url)
        return pages.get(url, PageView(ok=False, final_url=url, raw_text="", error="차단"))

    outcome = _run(identify(
        b"img", "image/jpeg", read_tag=read_tag, search=search, render_page=render_page,
        time_left=lambda: time_left, read_codes=read_codes, resolve_url=resolve_url, verify_by_render=False,
    ))
    return outcome, calls


def test_qr_product_page_with_code_is_found_without_search():
    qr = "https://qr.nike.example/x"
    final = "https://www.nike.com/kr/t/af1/123"
    outcome, calls = _run_identify(
        codes=_codes(qr), redirects={qr: final},
        pages={final: PageView(ok=True, final_url=final, raw_text=PRODUCT_PAGE, body_chars=900)},
    )
    assert outcome.status == "found"
    assert outcome.match["via"] == "qr" and outcome.match["url"] == final
    assert outcome.match["source"] == "official" and outcome.match["verified_by"] == "product_code"
    assert outcome.match["tag_price_seen"] is True
    assert outcome.official_domain == "nike.com"
    assert calls["search"] == 0  # 검색을 아예 안 했다
    assert outcome.qr[0]["result"].startswith("페이지에서 품번 확인")


def test_qr_to_brand_homepage_becomes_official_domain_for_search():
    qr = "https://qr.example/brand"
    search_text = ("OFFICIAL_DOMAIN: 없음\n"
                   "URL: https://www.nike.com/kr/t/af1/DV1234-100 | 제목: 에어 포스 1 DV1234-100 | 설명: 없음\n")
    outcome, calls = _run_identify(codes=_codes(qr), redirects={qr: "https://www.nike.com/"},
                                   pages={}, search_text=search_text)
    # 모델은 공식몰을 모른다고 했지만, QR이 알려 준 nike.com을 공식몰로 보고 그 후보를 받아들였다.
    assert outcome.status == "found"
    assert outcome.official_domain == "nike.com"
    assert outcome.match["source"] == "official" and "via" not in outcome.match
    assert calls["search"] == 1 and calls["render"] == []
    assert outcome.qr[0]["result"].startswith("브랜드 메인 페이지")


def test_qr_page_unreadable_falls_back_to_search_then_asks_user_with_qr_page():
    qr = "https://www.nike.com/kr/t/af1/123"
    outcome, calls = _run_identify(codes=_codes(qr), pages={}, search_text="OFFICIAL_DOMAIN: 없음\n")
    assert calls["search"] == 1  # QR로 확인 못 해서 검색까지 해 봤다
    assert outcome.status == "needs_confirm"
    assert outcome.match["url"] == qr and outcome.match["via"] == "qr" and outcome.match["verified_by"] == "qr"


def test_search_found_beats_unconfirmed_qr_page():
    qr = "https://www.nike.com/kr/t/af1/123"
    # 제목은 그라운딩 출처가 있어야 믿으므로, 주소에 품번이 있어 확인되는 후보를 쓴다.
    search_text = "URL: https://www.musinsa.com/products/DV1234-100 | 제목: 없음 | 설명: 없음\n"
    outcome, _ = _run_identify(codes=_codes(qr), pages={}, search_text=search_text)
    assert outcome.status == "found" and outcome.match["host"] == "musinsa.com"


def test_qr_page_readable_without_code_is_not_offered():
    qr = "https://www.nike.com/kr/event/summer"
    outcome, _ = _run_identify(
        codes=_codes(qr),
        pages={qr: PageView(ok=True, final_url=qr, raw_text=OTHER_PAGE, body_chars=900)},
        search_text="OFFICIAL_DOMAIN: 없음\n",
    )
    # 읽었는데 품번이 없는 페이지(이벤트·다른 상품)는 "맞나요?"로도 내밀지 않는다.
    assert outcome.status == "not_found"
    assert any(c["reason"] == "QR · 페이지에 품번 없음" for c in outcome.checked)


def test_unsafe_qr_is_never_rendered():
    qr = "http://169.254.169.254/latest"
    outcome, calls = _run_identify(codes=_codes(qr), pages={}, unsafe={qr}, search_text="")
    assert qr not in calls["render"] and not any("169.254" in u for u in calls["render"])
    assert outcome.qr[0]["result"].startswith("막음")


def test_qr_to_instagram_is_ignored_and_not_used_as_official_domain():
    qr = "https://www.instagram.com/nike"
    outcome, calls = _run_identify(codes=_codes(qr), pages={}, search_text="")
    # 인스타그램을 공식몰로 쓰지 않는다(공식몰은 브랜드 규칙의 nike.com — 그 사이트 검색은 해도 된다).
    assert not any("instagram" in u for u in calls["render"]) and outcome.official_domain != "instagram.com"


def test_decoded_barcode_replaces_ocr_barcode_and_qr_text_codes_are_added():
    tag = {**TAG, "barcode": "8801234567890"}  # OCR이 마지막 자리를 잘못 읽음(검증 숫자 불일치 → _clean_tag가 버림)
    _, calls = _run_identify(
        codes=_codes(barcodes=["8801234567893"], text_codes=["93251-TTL-1202"]), pages={}, tag=tag,
        search_text="",
    )
    searched = calls["search_tag"]
    assert searched["barcode"] == "8801234567893" and searched["barcode_source"] == "decoded"
    assert "93251-TTL-1202" in searched["other_codes"]


def test_not_a_tag_photo_with_unreadable_qr_page_asks_user():
    qr = "https://shop.brand.example/item/77"
    tag = {**TAG, "is_product_tag": False, "product_code": None, "brand": None, "product_name": None}
    outcome, calls = _run_identify(codes=_codes(qr), pages={}, tag=tag)
    assert outcome.status == "needs_confirm" and outcome.match["via"] == "qr"
    assert calls["search"] == 0


def test_low_time_skips_qr_and_goes_to_search():
    qr = "https://www.nike.com/kr/t/af1/DV1234-100"
    outcome, calls = _run_identify(codes=_codes(qr), pages={}, search_text="", time_left=5.0)
    assert calls["resolve"] == [] and outcome.qr[0]["result"] == "시간 부족"


# ── 실제 오프라인 태그(2026-11-08, 83장)에서 나온 경우 ──

def test_northface_qr_points_to_other_color_of_same_style():
    # 태그 품번 NJ1DS87K(파스텔 블루), QR은 /product/NJ1DS87J — 끝 글자만 다른 같은 스타일.
    qr = "https://www.thenorthfacekorea.co.kr/product/NJ1DS87J"
    tag = {**TAG, "brand": "THE NORTH FACE", "product_code": "NJ1DS87K"}
    outcome, calls = _run_identify(codes=_codes(qr), pages={}, tag=tag)  # 페이지는 못 읽음
    assert outcome.status == "found"
    assert outcome.match["verified_by"] == "product_code_base" and outcome.match["via"] == "qr"
    assert calls["search"] == 0


def test_8seconds_qr_with_exact_code_in_next_url_is_found_even_if_ssf_page_is_blank():
    qr = ("http://m.ssfshop.com/public/inflow/partnerGate/serviceId/66290"
          "?nextUrl=/public/goods/detail/456X51CM86/sapView")
    tag = {**TAG, "brand": "8seconds", "product_code": "456X51CM86"}
    outcome, calls = _run_identify(codes=_codes(qr), pages={}, tag=tag)
    assert outcome.status == "found" and outcome.match["verified_by"] == "product_code"
    assert outcome.match["source"] == "mall" and calls["search"] == 0


def test_8seconds_qr_pointing_to_different_code_is_not_offered():
    # 태그 456X39CM55인데 QR은 456941CM13 — 다른 상품. 페이지를 못 읽어도 "맞나요?"로 내밀지 않는다.
    qr = ("http://m.ssfshop.com/public/inflow/partnerGate/serviceId/66290"
          "?nextUrl=/public/goods/detail/456941CM13/sapView")
    tag = {**TAG, "brand": "8seconds", "product_code": "456X39CM55"}
    outcome, calls = _run_identify(codes=_codes(qr), pages={}, tag=tag, search_text="")
    assert outcome.status == "not_found" and calls["search"] == 1
    assert "품번이 태그와 다름" in outcome.qr[0]["result"]


def test_code128_product_code_becomes_other_code():
    # 비이커 태그: Code93에 품번+사이즈 "QQ6X39EP20F"가 들어 있다(품번 칸은 비어도 기타 코드로 남는다).
    tag = {**TAG, "brand": "BEAKER", "product_code": None, "product_name": None}
    outcome, calls = _run_identify(codes=DecodedCodes(linear_codes=["QQ6X39EP20F"]), pages={}, tag=tag,
                                   search_text="")
    assert outcome.tag["other_codes"] == ["QQ6X39EP20F"]
    assert outcome.skip_reason == "no_code" and calls["search"] == 0  # 품번 칸이 비면 찾지 않는다


def test_zara_code_in_original_qr_url_counts_even_if_redirect_drops_it():
    # 2026-11-09 실제 테스트: QR 주소엔 품번이 있지만 최종 주소엔 일부만 남고, ZARA 페이지는 서버가 못 읽음.
    qr = "http://www.zara.com/qr/0024870795914"
    final = "https://www.zara.com/kr/ko/fake-fur-vest-p00248707.html"
    tag = {**TAG, "brand": "ZARA", "product_code": "0248/707/959"}
    outcome, calls = _run_identify(codes=_codes(qr), redirects={qr: final}, pages={}, tag=tag)
    assert outcome.status == "found" and outcome.match["url"] == final
    assert outcome.match["verified_by"] == "product_code" and calls["search"] == 0


def test_mall_internal_id_in_final_url_is_not_a_conflict():
    # SSF샵 최종 주소의 몰 내부 번호(GM…)를 "다른 품번"으로 오해하면 안 된다.
    qr = "http://m.ssfshop.com/public/inflow/partnerGate/serviceId/66290?nextUrl=/public/goods/detail/456X51CM86/sapView"
    final = "https://m.ssfshop.com/8-seconds/GM0026101658961/good"
    tag = {**TAG, "brand": "8seconds", "product_code": "456X51CM86"}
    outcome, _ = _run_identify(codes=_codes(qr), redirects={qr: final}, pages={}, tag=tag)
    assert outcome.status == "found" and outcome.match["url"] == final


# ── 브랜드·품번이 없는 태그(무인양품 등) ──

def test_no_brand_no_code_skips_search_and_keeps_tag_values():
    tag = {**TAG, "brand": None, "product_code": None, "other_codes": ["AA0VVA6A-014"],
           "barcode": "4550723618786", "product_name": "야크 울 리브 하프 집업 스웨터", "tag_price": 99900}
    outcome, calls = _run_identify(codes=DecodedCodes(), pages={}, tag=tag)
    assert outcome.status == "not_found" and outcome.skip_reason == "no_brand_no_code"
    assert calls["search"] == 0 and calls["render"] == []
    # 태그에서 읽은 값은 그대로 돌려준다(앱이 이걸로 직접 기록을 채운다).
    assert outcome.tag["product_name"] == "야크 울 리브 하프 집업 스웨터" and outcome.tag["tag_price"] == 99900
    assert outcome.to_dict()["skip_reason"] == "no_brand_no_code"


def test_no_brand_no_code_but_qr_page_still_asks_user():
    qr = "https://shop.example.com/item/77"
    tag = {**TAG, "brand": None, "product_code": None}
    outcome, calls = _run_identify(codes=_codes(qr), pages={}, tag=tag)
    assert outcome.status == "needs_confirm" and outcome.match["via"] == "qr"
    assert outcome.skip_reason is None and calls["search"] == 0


def test_brand_without_code_is_skipped():
    tag = {**TAG, "product_code": None}
    outcome, calls = _run_identify(codes=DecodedCodes(), pages={}, tag=tag, search_text="")
    assert calls["search"] == 0 and outcome.skip_reason == "no_code"


def test_code_without_brand_is_skipped():
    tag = {**TAG, "brand": None, "product_code": "XQ12345"}  # 품번 모양으로도 브랜드를 알 수 없음
    outcome, calls = _run_identify(codes=DecodedCodes(), pages={}, tag=tag, search_text="")
    assert calls["search"] == 0 and outcome.skip_reason == "no_brand"


def test_search_redirect_sources_are_resolved_to_real_pages():
    # 검색 출처가 구글 리다이렉트 주소뿐이던 경우(2026-11-09 PIEDPIPER) — 진짜 주소로 풀어 품번을 본다.
    redirect = "https://vertexaisearch.cloud.google.com/grounding-api-redirect/ABC"
    real = "https://www.musinsa.com/products/DV1234-100"

    async def read_tag(img, mime):
        return _ok(dict(TAG))

    async def search(t):
        return _ok({"text": "OFFICIAL_DOMAIN: 없음\n", "sources": [{"uri": redirect, "title": "musinsa.com"}]})

    async def resolve_url(url):
        return QrResolution(url, real if url == redirect else url, ok=True)

    async def render_page(url):
        return PageView(ok=False, final_url=url, raw_text="", error="차단")

    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search, render_page=render_page,
                        time_left=lambda: 20.0, resolve_url=resolve_url, verify_by_render=False))
    assert out.status == "found" and out.match["url"] == real



# ── 공식몰 사이트 검색(2026-11-10) ──

def test_official_site_search_finds_product_when_everything_else_fails():
    tag = {**TAG, "brand": "VANS", "product_code": "VN000P79EMP"}
    search_page = "https://vans.co.kr/product/search.html?keyword=VN000P79EMP"
    product = "https://vans.co.kr/product/old-skool/1234/category/1/"
    pages = {
        search_page: PageView(ok=True, final_url=search_page, raw_text="검색 결과",
                              html='<a href="/product/old-skool/1234/category/1/">올드스쿨</a>'),
        product: PageView(ok=True, final_url=product, raw_text="스타일 VN000P79EMP 89,000원 " + "설명 " * 100,
                          body_chars=900),
    }
    outcome, calls = _run_identify(codes=DecodedCodes(), pages=pages, tag=tag, search_text="", time_left=24.0)
    assert outcome.status == "found" and outcome.match["via"] == "official_search"
    assert outcome.match["url"] == product and outcome.official_domain == "vans.co.kr"
    assert calls["search"] == 1  # 구글 검색이 실패한 뒤 마지막 수단으로


def test_official_site_search_skips_malls_and_unknown_domain():
    tag = {**TAG, "brand": "처음보는브랜드", "product_code": "AB12345"}
    _, calls = _run_identify(codes=DecodedCodes(), pages={}, tag=tag, search_text="", time_left=24.0)
    assert calls["render"] == []  # 공식몰 도메인을 모르면 사이트 검색을 하지 않는다
