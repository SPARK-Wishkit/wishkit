"""render 의 차단 판정 — 걸린 문구·응답 코드 남기기, 차단 페이지에서 기다리지 않기(2026-11-19 무신사 AWS 차단).

실제 Playwright 브라우저를 띄운다(test_resolve_in_browser.py 와 같이 헤드리스 크롬/크로미움이 있어야 한다).
"""
import asyncio
import http.server
import threading
import time

import pytest
from playwright.async_api import async_playwright

from render import _block_phrase, _block_reason, _looks_blocked, launch_browser, render
from share_links import strip_query

DENIED = b"<html><body><h1>Access Denied</h1><p>You don't have permission to access this server.</p></body></html>"
PRODUCT = "<html><body><h1>후드집업</h1><p>64,900원</p></body></html>".encode()


# ── 순수 함수 ────────────────────────────────────────────────


def test_block_phrase_returns_the_matched_text():
    assert _block_phrase("<h1>Access Denied</h1>") == "Access Denied"
    assert _block_phrase("<div id='cf-turnstile'></div>") == "cf-turnstile"
    assert _block_phrase("<p>잠시 후 다시 시도해 주세요. 비정상적인 접근이 감지되었습니다.</p>") == "비정상적인 접근"
    assert _block_phrase("<p>후드집업 64,900원</p>") is None
    assert _looks_blocked("<h1>Access Denied</h1>") and not _looks_blocked("<p>ok</p>")


def test_block_reason_has_phrase_and_trimmed_text_head():
    reason = _block_reason("Access Denied", "  Access   Denied \n\n You don't have " + "x" * 500)
    assert reason.startswith('"Access Denied" | Access Denied You don\'t have ')
    assert len(reason) == len('"Access Denied" | ') + 200


def test_strip_query_keeps_only_path():
    url = ("https://www.musinsa.com/products/7489748?af_referrer_customer_id=abc&shortlink=wwp934zk"
           "&af_channel=mobile_share#reviews")
    assert strip_query(url) == "https://www.musinsa.com/products/7489748"
    assert strip_query("https://a.example/p/1") == "https://a.example/p/1"
    assert strip_query("") == ""
    assert strip_query("not a url") == "not a url"


# ── 실제 브라우저 ─────────────────────────────────────────────


@pytest.fixture
def server():
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _send(self, code, body, cookie=None):
            self.send_response(code)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            if cookie:
                self.send_header("Set-Cookie", cookie)
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            warmed = "warm=1" in (self.headers.get("Cookie") or "")
            if self.path == "/":  # 홈: 쿠키를 준다(유니클로 Akamai 처럼 홈을 거치면 풀리는 경우)
                self._send(200, b"<p>home</p>", cookie="warm=1; Path=/")
            elif self.path == "/blocked":  # 홈을 거쳐도 계속 차단(무신사 AWS 의 경우)
                self._send(403, DENIED)
            elif self.path == "/needs-warmup":  # 홈 쿠키가 있어야 열림
                self._send(200, PRODUCT) if warmed else self._send(403, DENIED)
            else:
                self._send(200, PRODUCT)

    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{httpd.server_address[1]}"
    httpd.shutdown()


def _render(url):
    async def go():
        async with async_playwright() as p:
            browser = await launch_browser(p)
            try:
                t = time.monotonic()
                r = await render(browser, url, nav_timeout_ms=5000)
                return r, time.monotonic() - t
            finally:
                await browser.close()

    return asyncio.run(go())


def test_blocked_page_fails_fast_with_reason_and_status(server):
    r, elapsed = _render(f"{server}/blocked")
    assert r.error is None
    assert r.blocked and not r.ok
    assert r.status_code == 403
    assert r.block_reason.startswith('"Access Denied" | Access Denied')
    # 예전: 가격 폴링 10초 + 홈 웜업 1초 + 다시 폴링 10초 ≈ 21초. 이제 홈 웜업 1초 + 이동 몇 번.
    assert elapsed < 5.0, elapsed


def test_home_warmup_retry_still_unblocks(server):
    r, _ = _render(f"{server}/needs-warmup")
    assert r.ok and not r.blocked
    assert r.status_code == 200
    assert r.block_reason is None
    assert "64,900원" in r.raw_text


def test_normal_page_unchanged(server):
    r, elapsed = _render(f"{server}/product")
    assert r.ok and r.status_code == 200 and r.block_reason is None
    assert "64,900원" in r.raw_text
    assert elapsed < 5.0, elapsed  # 가격이 보이면 바로 끝난다
