"""
공식몰 사이트 검색 — 브랜드별 주소 규칙이 없어도, 공식몰 도메인만 알면 "그 사이트 검색창에 품번 넣기"를 한다.

쇼핑몰 검색 주소는 몇 가지 모양으로 정해져 있다(국내 자사몰 대부분이 카페24·고도몰·쇼피파이 같은 플랫폼).
그 모양들을 차례로 열어 보고, 검색 결과에서 같은 사이트의 상품 상세 링크를 골라 연 다음 **페이지 안에서 품번이
확인될 때만** 찾음으로 친다. 사이트 홈에 구조화 데이터(schema.org SearchAction)가 있으면 그 사이트가 직접 알려 주는
검색 주소를 쓴다(tools/discover_rules.py — 엔진은 시간이 빠듯해 홈은 열지 않는다).

- search_patterns(): 시도할 검색 주소 모양(이름, 주소 틀). {domain}·{code} 자리표시자.
- search_action_template(html): 홈 HTML의 SearchAction에서 검색 주소 틀.
- product_links(html, page_url, domain): 검색 결과에서 같은 사이트 상품 상세로 보이는 링크들.
"""
from __future__ import annotations

import json
import re
import urllib.parse

# 순서 = 시도 순서. 국내 자사몰에 많은 플랫폼부터.
PATTERNS: list[tuple[str, str]] = [
    ("cafe24", "https://{domain}/product/search.html?keyword={code}"),
    ("godomall", "https://{domain}/goods/goods_search.php?keyword={code}"),
    ("shopify", "https://{domain}/search?q={code}&type=product"),
    ("search_q", "https://{domain}/search?q={code}"),
    ("search_keyword", "https://{domain}/search?keyword={code}"),
]

# 상품 상세 주소로 보이는 모양(플랫폼 공통). 목록·검색·카테고리 주소는 뺀다.
_PRODUCT_PATH = re.compile(
    r"(/products?/|/goods/|/items?/|/p/|detail|goods_view|product_no=|goodsno=|productid=|prdno=|itemid=)",
    re.IGNORECASE)
# 목록·검색·장바구니 같은 페이지(상품 상세가 아님). 카페24 상세 주소엔 /category/가 뒤에 붙기도 해서 앞부분만 본다.
_NOT_PRODUCT = re.compile(
    r"(^/(search|category|list|cart|login|member|board|mypage)\b|/product/(search|list)\.html|goods_(list|search)"
    r"|/collections/[^/]+/?$)", re.IGNORECASE)
_HREF = re.compile(r"""href\s*=\s*["']([^"'#]+)["']""", re.IGNORECASE)


def _host(url: str) -> str:
    return (urllib.parse.urlsplit(url).hostname or "").lower().removeprefix("www.").removeprefix("m.")


def search_patterns(domain: str) -> list[tuple[str, str]]:
    return [(name, tpl.replace("{domain}", domain)) for name, tpl in PATTERNS]


def fill(template: str, code: str) -> str:
    return template.replace("{code}", urllib.parse.quote(code.replace(" ", "")))


def search_action_template(html: str) -> str | None:
    """schema.org WebSite.potentialAction(SearchAction).target → {code} 자리표시자가 든 검색 주소 틀."""
    for m in re.finditer(r'<script[^>]*application/ld\+json[^>]*>(.*?)</script>', html or "", re.DOTALL | re.IGNORECASE):
        try:
            data = json.loads(m.group(1))
        except ValueError:
            continue
        for node in data if isinstance(data, list) else [data]:
            actions = (node or {}).get("potentialAction") if isinstance(node, dict) else None
            for act in actions if isinstance(actions, list) else [actions]:
                if not isinstance(act, dict) or "SearchAction" not in str(act.get("@type")):
                    continue
                target = act.get("target")
                target = target.get("urlTemplate") if isinstance(target, dict) else target
                if isinstance(target, str) and "{" in target:
                    return re.sub(r"\{[^}]+\}", "{code}", target, count=1)
    return None


def product_links(html: str, page_url: str, domain: str, limit: int = 3) -> list[str]:
    """검색 결과 페이지에서 같은 사이트의 상품 상세 링크(앞에서부터)."""
    site = domain.lower().removeprefix("www.").removeprefix("m.")
    out: list[str] = []
    for href in _HREF.findall(html or ""):
        url = urllib.parse.urljoin(page_url, href.replace("&amp;", "&"))
        host = _host(url)
        if not (host == site or host.endswith("." + site)):
            continue
        path = urllib.parse.urlsplit(url).path + "?" + urllib.parse.urlsplit(url).query
        if not _PRODUCT_PATH.search(path) or _NOT_PRODUCT.search(urllib.parse.urlsplit(url).path):
            continue
        if url not in out:
            out.append(url)
        if len(out) >= limit:
            break
    return out
