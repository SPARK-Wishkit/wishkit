"""
서버 렌더링 레이어.

`engine-ai-prototype/render.py`(유니클로 레이스 컨디션까지 고친 최종 버전)를 포팅했다. 렌더링
판단 로직(UA 선택, 차단 문구 패턴, 대기 종료 조건, HTML 정제, MAX_CLEANED_CHARS, 스크린샷)은
원본과 동일하고, 바뀐 건 브라우저 생명주기뿐이다.

원본은 호출마다 브라우저 프로세스를 새로 띄웠지만, 서버에서는 `launch_browser()`로 앱 시작 시
한 번만 띄우고(main.py lifespan) `render()` 호출마다 새 **컨텍스트**만 열고 닫는다 — 쿠키/세션은
요청 간에 섞이지 않고, 브라우저 프로세스는 재사용된다.
"""
from __future__ import annotations

import asyncio
import json
import re
import urllib.parse
from dataclasses import dataclass, field

from bs4 import BeautifulSoup
from playwright.async_api import Browser
from playwright.async_api import TimeoutError as PWTimeoutError

DESKTOP_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)

# 모바일 UA가 필요한 몰 (에이블리·무신사·지그재그). 공유용 짧은 링크(onelink.me)는 뺐다 — 휴대폰인 척하면
# 앱/스토어로 보내려다 로딩이 안 끝난다. 짧은 링크는 렌더링 전에 share_links.py 가 실제 주소로 푼다.
MOBILE_UA_HOSTS = ("a-bly.com", "musinsa.com", "zigzag.kr")
MOBILE_UA = (
    "Mozilla/5.0 (Linux; Android 13; SM-G991N) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36"
)

BLOCK_PATTERNS = re.compile(
    r"Access Denied|Powered and protected by Akamai|sec-if-cpt-container|"
    r"접근이?\s*제한|비정상적인\s*접근|일시적으로\s*차단|자동화된?\s*요청|"
    r"captcha|보안\s*확인|"
    # 에이블리에서 간헐적으로 걸리는 Cloudflare Turnstile("Just a moment...") 탐지. 우회는 안
    # 하지만, 차단됐다는 건 정확히 감지해서 결과를 신뢰하지 않도록 한다.
    r"Just a moment|cf-turnstile|challenges\.cloudflare\.com|cf_chl_opt",
    re.IGNORECASE,
)

MAX_CLEANED_CHARS = 130000  # AI 입력 토큰 비용 통제용 상한 (근거: engine-ai-prototype 17절)

VIEWPORT = {"width": 1280, "height": 1600}

# 렌더링 완료 대기 조건 (design-doc-snapshot 21절, 유니클로 레이스 컨디션 근본 수정).
# 가격 텍스트가 실제로 보이면 즉시 종료(강한 신호). ld+json 가격/본문 길이 같은 약한 신호는
# 최소 3초가 지난 뒤에만 인정한다. 최대 20회 × 0.5초 = 10초.
POLL_INTERVAL_S = 0.5
POLL_MAX_ITERATIONS = 20
MIN_WAIT_BEFORE_WEAK_SIGNAL_S = 3.0
_JS_PRICE_VISIBLE = r"() => /\d{1,3}(,\d{3})+\s*원/.test(document.body.innerText)"
_JS_WEAK_READY = r"""() => {
  const ld = document.querySelector('script[type="application/ld+json"]');
  return (!!ld && /"(price|offers)"/i.test(ld.textContent)) || document.body.innerText.length > 1500;
}"""

_STRIP_TAGS = ["script", "style", "noscript", "svg", "iframe", "link", "meta"]
_KEEP_ATTRS = {"id", "src", "href", "content", "property", "alt", "aria-label"}


@dataclass
class RenderResult:
    final_url: str = ""
    blocked: bool = False
    cleaned_html: str = ""
    raw_text: str = ""
    image_candidates: list[str] = field(default_factory=list)
    screenshot: bytes = b""
    meta_text: str = ""  # <title>·설명 메타 태그 글자. 품번이 본문엔 없고 메타에만 있는 몰이 있다(무신사)
    # 화면에 안 보이는 품번 단서(대표 이미지 주소·구조화 데이터의 sku/mpn/gtin 등). _code_hints() 참고
    code_hints: list[str] = field(default_factory=list)
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None and not self.blocked


def _pick_ua(host: str) -> str:
    return MOBILE_UA if any(h in host for h in MOBILE_UA_HOSTS) else DESKTOP_UA


def _looks_blocked(html: str) -> bool:
    return bool(BLOCK_PATTERNS.search(html))


def _clean_html(html: str) -> tuple[str, str, list[str]]:
    """스크립트/스타일 등을 제거하고 주요 속성만 남긴 '정제된 HTML', 순수 텍스트, 이미지 후보
    목록을 반환한다. ld+json 스크립트와 og:/product: 메타는 남긴다(가격·이미지 단서)."""
    soup = BeautifulSoup(html, "html.parser")

    for tag in soup(_STRIP_TAGS):
        if tag.name == "script" and tag.get("type") == "application/ld+json":
            continue
        if tag.name == "meta" and tag.get("property", "").startswith(("og:", "product:")):
            continue
        tag.decompose()

    for tag in soup.find_all(True):
        tag.attrs = {k: v for k, v in tag.attrs.items() if k in _KEEP_ATTRS or k.startswith("data-")}

    image_candidates = sorted(
        {img["src"] for img in soup.find_all("img") if img.get("src")}
        | {m["content"] for m in soup.find_all("meta", property="og:image") if m.get("content")}
    )

    cleaned_html = str(soup)
    if len(cleaned_html) > MAX_CLEANED_CHARS:
        cleaned_html = cleaned_html[:MAX_CLEANED_CHARS] + "\n<!-- truncated -->"

    return cleaned_html, soup.get_text(separator=" ", strip=True), image_candidates


# 품번·상품명이 본문 대신 여기에만 들어 있는 몰이 많다(예: 무신사 description "제품번호 : 93251TTL1202").
_META_TEXT_KEYS = {"description", "keywords", "og:title", "og:description", "twitter:title", "twitter:description"}


def _meta_text(html: str) -> str:
    """<title>과 설명용 메타 태그(content)를 한 줄 글자로 모은다. 메타는 보통 <head>에 있으니
    <head>만 파싱한다(큰 페이지를 두 번 통째로 파싱하지 않게)."""
    end = html.lower().find("</head>")
    soup = BeautifulSoup(html if end < 0 else html[:end], "html.parser")
    parts: list[str] = []
    if soup.title and soup.title.string:
        parts.append(soup.title.string.strip())
    for m in soup.find_all("meta"):
        key = (m.get("name") or m.get("property") or "").strip().lower()
        content = (m.get("content") or "").strip()
        if content and (key in _META_TEXT_KEYS or key.startswith("product:")):
            parts.append(content)
    return " ".join(dict.fromkeys(p for p in parts if p))  # 같은 문장 중복 제거(순서 유지)


# 화면에 품번이 안 보여도 페이지 안쪽 데이터에는 들어 있는 경우가 많다. 다만 페이지 안의 모든 데이터를
# 보면 추천 상품·최근 본 상품의 품번까지 섞여 엉뚱한 페이지를 맞다고 할 수 있으므로, "이 페이지의 대표
# 상품"을 가리키는 곳만 본다: 대표 이미지(og:image 등)·대표 주소(canonical·og:url)·상품 메타 태그,
# 그리고 구조화 데이터(JSON-LD) 중 Product 항목의 코드·이미지 필드.
_HINT_META_KEYS = {"og:image", "og:image:url", "og:image:secure_url", "twitter:image", "og:url"}
_LD_PRODUCT_TYPES = {"product", "productgroup", "productmodel"}
_LD_CODE_KEYS = ("sku", "mpn", "gtin", "gtin8", "gtin12", "gtin13", "gtin14", "productid", "model", "image", "url")
_LD_OFFER_CODE_KEYS = ("sku", "mpn", "gtin", "gtin8", "gtin12", "gtin13", "gtin14")
_PRICE_KEY_RE = re.compile(r"price|amount|currency|availability|condition")
MAX_CODE_HINTS = 60  # 단서가 이상하게 많은 페이지(변형 수백 개 등)에서 확인이 느려지지 않게


def _ld_strings(value) -> list[str]:
    """JSON-LD 필드 값에서 글자만 꺼낸다(문자열·숫자·목록·{"url"/"@id"/"name"} 객체)."""
    if isinstance(value, (str, int)) and not isinstance(value, bool):
        return [str(value)]
    if isinstance(value, list):
        return [s for v in value for s in _ld_strings(v)]
    if isinstance(value, dict):
        return [s for k in ("url", "@id", "contentUrl", "value") if k in value for s in _ld_strings(value[k])]
    return []


def _ld_products(node) -> list[dict]:
    """JSON-LD에서 Product 계열 객체를 모두 찾는다(@graph·목록·hasVariant·offers 안쪽 포함)."""
    found: list[dict] = []
    if isinstance(node, list):
        for v in node:
            found += _ld_products(v)
    elif isinstance(node, dict):
        types = node.get("@type")
        types = types if isinstance(types, list) else [types]
        if any(str(t).lower() in _LD_PRODUCT_TYPES for t in types if t):
            found.append(node)
        for key in ("@graph", "hasVariant", "offers", "mainEntity", "itemOffered"):
            if key in node:
                found += _ld_products(node[key])
    return found


def _code_hints(html: str) -> list[str]:
    """화면에 안 보이는 품번 단서를 모은다. 실패해도 빈 목록(확인 흐름을 막지 않음)."""
    try:
        soup = BeautifulSoup(html, "html.parser")
        hints: list[str] = []
        for m in soup.find_all("meta"):
            key = (m.get("property") or m.get("name") or "").strip().lower()
            content = (m.get("content") or "").strip()
            # product:price:amount 같은 가격·통화 값은 뺀다(숫자 품번과 우연히 같을 수 있음)
            if content and (key in _HINT_META_KEYS or (key.startswith("product:") and not _PRICE_KEY_RE.search(key))):
                hints.append(content)
        for link in soup.find_all("link", rel="canonical"):
            if link.get("href"):
                hints.append(link["href"].strip())
        for script in soup.find_all("script", type="application/ld+json"):
            try:
                data = json.loads(script.string or "")
            except (ValueError, TypeError):
                continue
            for product in _ld_products(data):
                for key, value in product.items():
                    if key.lower() in _LD_CODE_KEYS:
                        hints += _ld_strings(value)
                offers = product.get("offers")
                for offer in offers if isinstance(offers, list) else [offers]:
                    if isinstance(offer, dict):
                        hints += [s for k in _LD_OFFER_CODE_KEYS for s in _ld_strings(offer.get(k))]
        return list(dict.fromkeys(h for h in hints if h))[:MAX_CODE_HINTS]
    except Exception:  # noqa: BLE001
        return []


async def _goto_and_wait(page, url: str, nav_timeout_ms: int) -> None:
    await page.goto(url, timeout=nav_timeout_ms, wait_until="domcontentloaded")
    for i in range(POLL_MAX_ITERATIONS):
        if await page.evaluate(_JS_PRICE_VISIBLE):
            return
        if i * POLL_INTERVAL_S >= MIN_WAIT_BEFORE_WEAK_SIGNAL_S and await page.evaluate(_JS_WEAK_READY):
            return
        await asyncio.sleep(POLL_INTERVAL_S)


async def render(browser: Browser, url: str, *, nav_timeout_ms: int = 20000) -> RenderResult:
    """공유 브라우저에서 새 컨텍스트를 열어 렌더링하고, 끝나면 그 컨텍스트만 닫는다.
    실패는 예외를 던지지 않고 `RenderResult.error`로 표현한다."""
    parsed = urllib.parse.urlparse(url)
    context = await browser.new_context(user_agent=_pick_ua(parsed.netloc), viewport=VIEWPORT)
    try:
        page = await context.new_page()
        await _goto_and_wait(page, url, nav_timeout_ms)
        html = await page.content()

        if _looks_blocked(html):
            # 홈 웜업 후 1회 재시도
            try:
                await page.goto(f"{parsed.scheme}://{parsed.netloc}/",
                                timeout=nav_timeout_ms, wait_until="domcontentloaded")
                await asyncio.sleep(1.0)
                await _goto_and_wait(page, url, nav_timeout_ms)
                html = await page.content()
            except PWTimeoutError:
                pass

        cleaned_html, raw_text, images = _clean_html(html)
        try:
            screenshot = await page.screenshot(type="jpeg", quality=70)
        except Exception:  # noqa: BLE001 — 스크린샷 실패는 텍스트 추출 흐름을 막지 않음
            screenshot = b""

        return RenderResult(
            final_url=page.url,
            blocked=_looks_blocked(html),
            cleaned_html=cleaned_html,
            raw_text=raw_text,
            image_candidates=images,
            screenshot=screenshot,
            meta_text=_meta_text(html),
            code_hints=_code_hints(html),
        )
    except Exception as exc:  # noqa: BLE001
        return RenderResult(error=f"{type(exc).__name__}: {exc}")
    finally:
        await context.close()


async def launch_browser(playwright) -> Browser:
    """앱 시작 시 1회만 호출 — 이후 모든 요청이 이 브라우저 프로세스를 공유한다.
    설치된 Chrome을 우선 쓰고, 없으면 Playwright 번들 Chromium으로 폴백한다."""
    try:
        return await playwright.chromium.launch(channel="chrome", headless=True)
    except Exception:  # noqa: BLE001
        return await playwright.chromium.launch(headless=True)
