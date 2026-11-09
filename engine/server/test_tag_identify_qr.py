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
    assert calls["render"] == []
    assert outcome.qr[0]["result"].startswith("막음")


def test_qr_to_instagram_is_ignored_and_not_used_as_official_domain():
    qr = "https://www.instagram.com/nike"
    outcome, calls = _run_identify(codes=_codes(qr), pages={}, search_text="")
    assert calls["render"] == [] and outcome.official_domain is None


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
    # 비이커 태그: Code93에 품번+사이즈 "QQ6X39EP20F"가 들어 있다.
    tag = {**TAG, "brand": "BEAKER", "product_code": None, "product_name": None}
    _, calls = _run_identify(codes=DecodedCodes(linear_codes=["QQ6X39EP20F"]), pages={}, tag=tag,
                             search_text="")
    assert calls["search_tag"]["other_codes"] == ["QQ6X39EP20F"]
