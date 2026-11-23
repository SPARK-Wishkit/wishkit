"""render.resolve_in_browser — HTTP 요청이 막힌 짧은 링크를 브라우저로 풀기(2026-11-18 onelink 403).

실제 Playwright 브라우저를 띄운다(test_main.py 와 같이 헤드리스 크롬/크로미움이 있어야 한다).
짧은 링크 호스트로 127.0.0.1 을, 쇼핑몰 호스트로 localhost 를 쓴다.
"""
import asyncio
import http.server
import threading
import time

import pytest
from playwright.async_api import async_playwright

import share_links
from render import DESKTOP_UA, launch_browser, resolve_in_browser


@pytest.fixture
def server(monkeypatch):
    seen_ua = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            port = self.server.server_address[1]
            seen_ua.append(self.headers.get("User-Agent", ""))
            if self.path == "/redirect":  # 3xx 리다이렉트
                self.send_response(302)
                self.send_header("Location", f"http://localhost:{port}/products/7")
                self.end_headers()
            elif self.path == "/js":  # 403 을 주면서 JS 로 넘기는 중간 페이지
                body = f'<script>location.replace("http://localhost:{port}/products/8")</script>'.encode()
                self.send_response(403)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(body)
            elif self.path == "/stuck":  # 어디로도 안 넘기는 페이지
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(b"<p>open the app</p>")
            else:
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(b"<p>product</p>")

    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    monkeypatch.setattr(share_links, "SHORT_LINK_SUFFIXES", ("127.0.0.1",))
    yield httpd.server_address[1], seen_ua
    httpd.shutdown()


def _run(url, timeout_s=5.0):
    async def go():
        async with async_playwright() as p:
            browser = await launch_browser(p)
            try:
                return await resolve_in_browser(browser, url, timeout_s=timeout_s)
            finally:
                await browser.close()

    return asyncio.run(go())


def test_follows_http_redirect_to_shop_url(server):
    port, seen_ua = server
    assert _run(f"http://127.0.0.1:{port}/redirect") == f"http://localhost:{port}/products/7"
    assert seen_ua[0] == DESKTOP_UA  # 휴대폰 UA 면 앱/스토어로 보내진다


def test_follows_javascript_redirect_even_on_403_page(server):
    port, _ = server
    assert _run(f"http://127.0.0.1:{port}/js") == f"http://localhost:{port}/products/8"


def test_gives_up_within_timeout_when_link_never_leaves(server):
    port, _ = server
    started = time.monotonic()
    assert _run(f"http://127.0.0.1:{port}/stuck", timeout_s=1.5) is None
    assert time.monotonic() - started < 6  # 브라우저 시작·종료 포함
