"""2026-11 가격 정책("상품 페이지에서 가장 크게 홍보하는 가격") 테스트.

- 화면 가격 후보 측정(render.measure_price_candidates): 실제 헤드리스 크롬에 만든 HTML을 띄워서
  글자 크기·취소선·숨김·첫 화면 여부를 재는지 확인한다(외부 사이트 접속 없음).
- 가장 큰 가격 판정(compare.most_prominent_prices / grounding_check)
- 프롬프트에 후보 목록이 들어가는지(prompts)
- /extract 배선: 렌더링 후보가 Gemini 호출과 그라운딩 체크까지 전달되는지(main)
"""
import asyncio

from fastapi.testclient import TestClient
from playwright.async_api import async_playwright

from compare import grounding_check, most_prominent_prices
from prompts import build_user_prompt, build_vision_user_prompt, format_price_candidates
from render import FIRST_SCREEN_PX, launch_browser, measure_price_candidates

# 에이블리·4910처럼 쿠폰적용가가 가장 크게 표시되는 상품 페이지를 흉내 낸 화면.
ABLY_LIKE_PAGE = f"""<html><body style="margin:0">
<div id="main">
  <h1 style="font-size:20px">린넨 셔츠</h1>
  <span style="font-size:14px;text-decoration:line-through">99,000원</span>
  <div><span style="font-size:14px">즉시할인가</span> <span style="font-size:18px">34,800원</span></div>
  <div><span style="font-size:12px">쿠폰적용가</span> <strong style="font-size:28px">29,800</strong><span style="font-size:20px">원</span></div>
  <del style="font-size:30px">120,000원</del>
  <span style="display:none;font-size:40px">10,000원</span>
  <span style="visibility:hidden;font-size:40px">11,000원</span>
  <p style="font-size:13px">상품번호 2026123</p>
  <p style="font-size:13px">₩45000 · 15000원</p>
</div>
<div style="height:{FIRST_SCREEN_PX + 400}px"></div>
<div style="font-size:36px">함께 본 상품 5,000원</div>
</body></html>"""


def _measure(html: str) -> list[dict]:
    async def run():
        async with async_playwright() as pw:
            browser = await launch_browser(pw)
            try:
                page = await browser.new_page(viewport={"width": 1280, "height": FIRST_SCREEN_PX})
                await page.set_content(html)
                return await measure_price_candidates(page)
            finally:
                await browser.close()

    return asyncio.run(run())


def test_measure_reads_font_size_strikethrough_and_position():
    cands = _measure(ABLY_LIKE_PAGE)
    by_value = {c["value"]: c for c in cands}

    assert by_value[29800]["font_px"] == 28
    assert "쿠폰적용가" in by_value[29800]["context"]  # 라벨이 주변 글자에 같이 들어옴
    assert by_value[29800]["first_screen"] is True and by_value[29800]["struck"] is False
    assert by_value[99000]["struck"] is True  # CSS 취소선
    assert by_value[120000]["struck"] is True  # <del>
    assert by_value[5000]["first_screen"] is False  # 스크롤 아래 추천 상품
    assert 10000 not in by_value and 11000 not in by_value  # 화면에 안 보이는 가격
    assert 2026123 not in by_value  # 콤마·원 없는 숫자는 가격이 아님
    assert 45000 in by_value and 15000 in by_value  # ₩ 표시, 한 글자 묶음 안의 두 번째 가격
    assert [c["font_px"] for c in cands] == sorted((c["font_px"] for c in cands), reverse=True)

    # 취소선(120,000원 30px)·스크롤 아래(5,000원 36px)를 빼면 쿠폰적용가가 가장 크다.
    assert most_prominent_prices(cands) == {29800}


def _cand(value, font_px, *, struck=False, first_screen=True, context=""):
    return {"value": value, "font_px": font_px, "font_weight": 400, "struck": struck,
            "top": 100, "context": context, "first_screen": first_screen}


def _extracted(price):
    return {"product_name": "린넨 셔츠", "image_url": None,
            "price": {"unconditional_price": price, "regular_price": 99000, "currency": "KRW"}}


CANDS = [_cand(120000, 30, struck=True), _cand(29800, 28), _cand(34800, 18), _cand(5000, 36, first_screen=False)]


def test_grounding_marks_most_prominent_price():
    g = grounding_check(_extracted(29800), "99,000원 34,800원 29,800원", [], CANDS)
    assert g["most_prominent_price"] == 29800
    assert g["price_is_most_prominent"] is True


def test_grounding_flags_old_policy_price():
    # 옛 정책처럼 즉시할인가(더 작은 글자)를 고르면 원문에는 있어도(price_grounded) 정책 위반으로 표시.
    g = grounding_check(_extracted(34800), "99,000원 34,800원 29,800원", [], CANDS)
    assert g["price_grounded"] is True
    assert g["price_is_most_prominent"] is False
    assert g["all_grounded"] is False  # 이름·이미지가 없어서. 판정 자체는 all_grounded에 안 들어감


def test_grounding_prominence_unknown_without_evidence():
    assert grounding_check(_extracted(29800), "29,800원", [])["price_is_most_prominent"] is None
    assert grounding_check(_extracted(None), "29,800원", [], CANDS)["price_is_most_prominent"] is None


def test_grounding_prominence_with_tie():
    tie = [_cand(29800, 28), _cand(31800, 28)]
    g = grounding_check(_extracted(31800), "29,800원 31,800원", [], tie)
    assert g["most_prominent_price"] is None  # 같은 크기가 둘이라 대표값은 못 정함
    assert g["price_is_most_prominent"] is True  # 그중 하나를 골랐으면 정책 위반은 아님


def test_prompt_lists_candidates_with_flags():
    text = format_price_candidates([_cand(29800, 28, context="쿠폰적용가 29,800원"), _cand(99000, 14, struck=True)])
    assert "29,800원 | 글자 28px · 굵기 400 · 첫 화면 | 주변 글자: '쿠폰적용가 29,800원'" in text
    assert "99,000원 | 글자 14px · 굵기 400 · 첫 화면 · 취소선" in text
    assert "측정된 후보 없음" in format_price_candidates([])

    prompt = build_user_prompt("<div>html</div>", [_cand(29800, 28)])
    assert "화면 가격 후보" in prompt and "29,800원" in prompt and "<div>html</div>" in prompt
    assert "29,800원" in build_vision_user_prompt(["https://img/1.jpg"], [_cand(29800, 28)])


def test_extract_passes_candidates_to_gemini_and_grounding(monkeypatch):
    import main
    from providers import ProviderResult
    from render import RenderResult

    async def fake_render(browser, url, *, nav_timeout_ms):
        return RenderResult(final_url=url, cleaned_html="<div>린넨 셔츠 29,800원</div>",
                            raw_text="린넨 셔츠 99,000원 29,800원", price_candidates=CANDS)

    seen = {}

    def fake_gemini(cleaned_html, price_candidates=None, **_):
        seen["candidates"] = price_candidates
        return ProviderResult("gemini", "m", True, {**_extracted(29800), "ambiguous": False,
                                                    "ambiguity_reason": None, "confidence": "high"}, 1)

    monkeypatch.setattr(main, "render", fake_render)
    monkeypatch.setattr(main, "call_gemini", fake_gemini)
    monkeypatch.setattr(main, "resolve_share_link", lambda u: u)

    with TestClient(main.app) as client:
        resp = client.post("/extract", json={"url": "https://example.com/p/1"})
    assert resp.status_code == 200
    assert seen["candidates"] == CANDS
    body = resp.json()
    assert body["price"]["unconditional_price"] == 29800
    assert body["grounding"]["price_is_most_prominent"] is True
    assert body["grounding"]["most_prominent_price"] == 29800
