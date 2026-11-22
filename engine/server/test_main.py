"""
API 계층 스모크 테스트. 실제 Playwright 렌더링/Gemini 호출까지 포함하는 end-to-end 검증은
여기서 하지 않는다 — 그건 `tools/golden_regression_check.py`로 골든셋 36개를 실제 서버에
쏴서 이미 확인했다(회귀 없음, 완전 일치 22/36=61%, 그라운딩 28/36=78% — run6 대비 회귀
없음, 상세 원인 분석은 보고서 참고). 여기서는 FastAPI 앱 자체(요청 검증, lifespan으로
브라우저가 실제로 뜨는지, healthz)만 빠르게 확인한다 — 이것도 실제 Playwright 브라우저를
띄우므로(모킹하지 않음), 헤드리스 크롬이 설치돼 있어야 통과한다.
"""
from fastapi.testclient import TestClient

from main import app


def test_healthz_reports_browser_connected():
    with TestClient(app) as client:
        resp = client.get("/healthz")
        assert resp.status_code == 200
        body = resp.json()
        assert body["ok"] is True
        assert body["browser_connected"] is True


def test_extract_rejects_invalid_url():
    with TestClient(app) as client:
        resp = client.post("/extract", json={"url": "not-a-url"})
        assert resp.status_code == 422  # pydantic HttpUrl 검증에서 걸러짐 — 브라우저/Gemini 호출 전


def test_identify_tag_rejects_bad_base64():
    with TestClient(app) as client:
        resp = client.post("/identify-tag", json={"image_base64": "%%%not-base64%%%"})
        assert resp.status_code == 422


def test_identify_tag_end_to_end_with_fake_gemini(monkeypatch):
    """Gemini·실제 쇼핑몰은 가짜로 바꾸고, 엔드포인트 배선(base64 → 태그 읽기 → 검색 → 확인 → 응답
    모양)만 확인한다."""
    import base64

    import config
    import main
    from providers import ProviderResult
    from tag_identify import PageView

    monkeypatch.setattr(config, "IDENTIFY_RENDER_VERIFY", True)  # 렌더링 확인 경로를 검증하는 테스트

    url = "https://www.musinsa.com/products/4341120"
    tag = {"is_product_tag": True, "brand": "NIKE", "product_code": "801474YB2FT1000", "barcode": None,
           "product_name": "클래식 반소매 티셔츠", "color": "블랙", "size": "M", "tag_price": 105990,
           "confidence": "high"}
    monkeypatch.setattr(main, "call_gemini_tag",
                        lambda img, mime, **_: ProviderResult("t", "m", True, tag, 1))
    monkeypatch.setattr(main, "call_gemini_search",
                        lambda t, **_: ProviderResult("s", "m", True, {"text": f"URL: {url}", "sources": []}, 1))

    async def fake_render(u, budget_s):
        assert 0 < budget_s <= config.IDENTIFY_TIMEOUT_S
        return PageView(True, u, "클래식 반소매 티셔츠 - 블랙 / 801474YB2FT1000")

    monkeypatch.setattr(main, "_render_for_identify", fake_render)

    with TestClient(app) as client:
        resp = client.post("/identify-tag", json={"image_base64": base64.b64encode(b"jpeg").decode()})
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "found"
    assert body["match"] == {"url": url, "host": "musinsa.com", "source": "mall", "verified_by": "product_code",
                             "tag_price_seen": False}  # 태그 가격(105,990원)이 가짜 페이지 글자에 없음
    assert body["tag"]["tag_price"] == 105990


def test_identify_render_budget_includes_waiting_for_render_slot(monkeypatch):
    """렌더링 슬롯이 다 차 있으면, 슬롯을 기다리는 시간까지 budget_s로 끊고 '시간 초과'로 돌려준다."""
    import asyncio
    import time

    import main

    async def scenario():
        main.app.state.render_semaphore = asyncio.Semaphore(1)
        await main.app.state.render_semaphore.acquire()  # 다른 요청이 슬롯을 잡고 있는 상황
        t0 = time.monotonic()
        page = await main._render_for_identify("https://example.com/p", budget_s=1.0)
        return page, time.monotonic() - t0

    with TestClient(app):
        page, elapsed = asyncio.run(scenario())
    assert page.ok is False and page.error == "시간 초과"
    assert elapsed < 2.0


def test_identify_tag_rejects_oversized_base64_before_decoding(monkeypatch):
    import config
    import main

    monkeypatch.setattr(main, "_MAX_IMAGE_BASE64_CHARS", 8)
    with TestClient(app) as client:
        resp = client.post("/identify-tag", json={"image_base64": "A" * 12})
    assert resp.status_code == 413
    assert str(config.IDENTIFY_MAX_IMAGE_BYTES) in resp.json()["detail"]


def test_extract_blocked_logs_reason_without_share_query(monkeypatch, caplog):
    """차단 502 는 엔진 로그에도 이유(문구·status)를 남기고, 주소의 쿼리(공유자 식별값)는 빼고 남긴다."""
    import logging

    import main
    from render import RenderResult

    async def fake_render(browser, url, *, nav_timeout_ms):
        return RenderResult(final_url=url, blocked=True, status_code=403,
                            block_reason='"Access Denied" | Access Denied You don\'t have permission')

    monkeypatch.setattr(main, "render", fake_render)
    url = "https://www.musinsa.com/products/7489748?af_referrer_customer_id=abc123&shortlink=wwp934zk"
    with caplog.at_level(logging.WARNING, logger="extract-server"), TestClient(app) as client:
        resp = client.post("/extract", json={"url": url})

    assert resp.status_code == 502
    detail = resp.json()["detail"]
    assert "status=403" in detail and "final_url=https://www.musinsa.com/products/7489748)" in detail
    assert "abc123" not in detail
    lines = [r.getMessage() for r in caplog.records if "[extract] 차단" in r.getMessage()]
    assert len(lines) == 1
    assert "host=www.musinsa.com status=403" in lines[0]
    assert "Access Denied" in lines[0] and "final_url=https://www.musinsa.com/products/7489748 " in lines[0]
    assert "abc123" not in caplog.text


def test_extract_log_line_shows_the_nested_price(monkeypatch, caplog):
    """[extract] host=… price=… 줄은 응답의 price.unconditional_price 를 찍는다(예전엔 바깥에서 찾아 늘 None)."""
    import logging

    import main
    from providers import ProviderResult
    from render import RenderResult

    async def fake_render(browser, url, *, nav_timeout_ms):
        return RenderResult(final_url=url, cleaned_html="<p>후드집업 21,500원</p>", raw_text="후드집업 21,500원")

    data = {"product_name": "후드집업", "image_url": None, "ambiguous": False, "ambiguity_reason": None,
            "confidence": "high", "price": {"unconditional_price": 21500, "regular_price": None, "currency": "KRW"}}
    monkeypatch.setattr(main, "render", fake_render)
    monkeypatch.setattr(main, "call_gemini", lambda html: ProviderResult("gemini", "fake", True, data, 1))
    with caplog.at_level(logging.INFO, logger="extract-server"), TestClient(app) as client:
        resp = client.post("/extract", json={"url": "https://m.a-bly.com/goods/51469717"})

    assert resp.status_code == 200
    assert resp.json()["price"]["unconditional_price"] == 21500
    lines = [r.getMessage() for r in caplog.records if r.getMessage().startswith("[extract] host=")]
    assert len(lines) == 1 and "host=m.a-bly.com price=21500 " in lines[0]


def test_extract_success_final_url_drops_only_tracking_params(monkeypatch):
    """성공 응답의 render.final_url(앱이 상품 주소로 저장)은 공유 추적값만 빠지고 나머지 쿼리는 남는다."""
    import main
    from providers import ProviderResult
    from render import RenderResult

    rendered = "https://example.com/goods?no=123&af_referrer_customer_id=abc123&utm_source=share"

    async def fake_render(browser, url, *, nav_timeout_ms):
        return RenderResult(final_url=rendered, cleaned_html="<p>후드집업 21,500원</p>", raw_text="후드집업 21,500원")

    data = {"product_name": "후드집업", "image_url": None, "ambiguous": False, "ambiguity_reason": None,
            "confidence": "high", "price": {"unconditional_price": 21500, "regular_price": None, "currency": "KRW"}}
    monkeypatch.setattr(main, "render", fake_render)
    monkeypatch.setattr(main, "call_gemini", lambda html: ProviderResult("gemini", "fake", True, data, 1))
    with TestClient(app) as client:
        resp = client.post("/extract", json={"url": "https://example.com/goods?no=123"})

    assert resp.status_code == 200
    assert resp.json()["render"]["final_url"] == "https://example.com/goods?no=123"
    assert "abc123" not in resp.text


def test_extract_ably_coupon_price_corrected_without_vision(monkeypatch, caplog):
    """에이블리: AI 가 웹 전용 쿠폰가(29,210)를 골라도 즉시할인가(32,450)로 바로잡고, 스크린샷 폴백은 부르지 않는다."""
    import logging

    import main
    from providers import ProviderResult
    from render import RenderResult
    from test_price_rules import ABLY_77103060

    async def fake_render(browser, url, *, nav_timeout_ms):
        return RenderResult(final_url="https://mobile.a-bly.com/goods/77103060",
                            cleaned_html="<p>후드집업</p>", raw_text=ABLY_77103060, screenshot=b"jpg")

    data = {"product_name": "[컬러포인트🖤] 루이 홀스 후드집업 (5color)", "image_url": None, "ambiguous": True,
            "ambiguity_reason": "가격 후보 여러 개", "confidence": "medium",
            "price": {"unconditional_price": 29210, "regular_price": 34900, "currency": "KRW"}}

    def no_vision(*args, **kwargs):
        raise AssertionError("규칙으로 확정되면 스크린샷 폴백을 부르지 않아야 한다")

    monkeypatch.setattr(main, "render", fake_render)
    monkeypatch.setattr(main, "call_gemini", lambda html: ProviderResult("gemini", "fake", True, data, 1))
    monkeypatch.setattr(main, "call_gemini_vision", no_vision)
    with caplog.at_level(logging.INFO, logger="extract-server"), TestClient(app) as client:
        resp = client.post("/extract", json={"url": "https://m.a-bly.com/goods/77103060"})

    assert resp.status_code == 200
    body = resp.json()
    assert body["price"]["unconditional_price"] == 32450
    assert body["price"]["regular_price"] == 34900
    assert body["ambiguous"] is False and body["screenshot_fallback_used"] is False
    assert "[price-rule] host=mobile.a-bly.com 에이블리 즉시할인가로 교정: 29210 → 32450" in caplog.text
