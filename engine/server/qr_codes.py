"""
태그 사진 속 QR·바코드를 **실제 디코더로** 읽는 함수들 — tag_identify.py가 쓴다.

왜 Gemini에게 맡기지 않나: LLM 비전은 QR 모듈 패턴을 디코딩하지 못해서, 시키면 그럴듯한 주소를 지어낼 수
있다("틀린 값보다 빈 값이 안전하다" 원칙과 정면으로 부딪힌다). 그래서 zxing-cpp로 읽고, 못 읽으면 빈 값.

- decode_codes(): 사진 → QR 내용 목록 + 검증된 바코드(EAN/UPC). 바코드는 Gemini가 숫자를 OCR한 값보다
  정확하므로, 읽히면 그 값을 쓴다(검증 숫자는 tag_codes.is_valid_gtin으로 한 번 더 본다).
- parse_qr_payload(): QR 내용을 종류별로 나눈다.
    'gs1'  — GS1 Digital Link(https://…/01/<GTIN>/…) 또는 GS1 요소 문자열(01<GTIN>…). GTIN → 바코드로 쓴다.
             Digital Link는 주소이기도 해서 url도 같이 채운다(브랜드가 상품 페이지로 보내는 경우가 많음).
    'url'  — 일반 주소. 어디로 가는지는 resolve_qr_url()로 따라가 봐야 안다.
    'text' — 주소가 아닌 글자. 5자 이상 영문·숫자 덩어리만 보조 코드(other_codes)로 쓴다.
- resolve_qr_url(): QR 주소의 리다이렉트를 따라가 최종 주소를 얻는다. **QR 내용은 아무나 인쇄할 수 있는
  신뢰할 수 없는 입력**이라, 매 홉마다 http/https인지·공개 IP인지 확인한다(SSRF 방지 — Fargate 안에서
  사설망·메타데이터 주소로 요청이 나가지 않게).

네트워크 함수(resolve_qr_url)는 동기 함수다 — main.py에서 asyncio.to_thread로 부른다.
"""
from __future__ import annotations

import io
import ipaddress
import logging
import re
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

from share_links import DESKTOP_UA, web_fallback_in
from tag_codes import is_valid_gtin

logger = logging.getLogger("extract-server")

# zxing-cpp 포맷 이름(BarcodeFormat.name) 중 2차원 코드 — 내용을 QR 내용으로 다룬다.
TWO_D_FORMATS = {"QRCode", "MicroQRCode", "RMQRCode", "DataMatrix", "Aztec"}
# 1차원 상품 바코드 — 검증 숫자가 맞으면 태그 바코드로 쓴다.
LINEAR_GTIN_FORMATS = {"EAN13", "EAN8", "UPCA", "UPCE"}
# 글자를 담는 1차원 바코드. 국내 태그는 여기에 품번을 그대로 넣는 경우가 많다(2026-11-08 오프라인 태그
# 83장: 비이커 Code93 "QQ6X39EP20F", 크림 Code128 "DW6DDWJKD87LB_F", 뉴발란스 "NBNQG41923B810501",
# 지오다노 Code39 "010569301202"). 사람이 읽는 글자보다 정확하니 보조 코드(other_codes)로 쓴다.
LINEAR_TEXT_FORMATS = {"Code128", "Code93", "Code39", "ITF", "Codabar"}

MAX_QR_PAYLOADS = 3  # 한 사진에서 볼 QR 최대 개수(태그 앞뒤가 같이 찍힌 경우 등)
MIN_TEXT_CODE_LEN = 5


@dataclass
class QrPayload:
    raw: str
    kind: str  # 'gs1' | 'url' | 'text'
    url: str | None = None
    gtin: str | None = None  # 검증된 GTIN(앞의 0 하나는 떼서 EAN-13 모양으로)
    codes: list[str] = field(default_factory=list)  # 'text'에서 뽑은 보조 코드


@dataclass
class DecodedCodes:
    qr: list[QrPayload] = field(default_factory=list)
    barcodes: list[str] = field(default_factory=list)  # 검증 숫자가 맞는 EAN/UPC
    linear_codes: list[str] = field(default_factory=list)  # Code128 등 글자 바코드 내용(품번인 경우가 많음)
    error: str | None = None  # 디코더를 못 쓴 이유(사진 형식 등). 못 찾은 건 에러가 아니다.

    @property
    def gtins(self) -> list[str]:
        """바코드 + GS1 QR의 GTIN(중복 없이, 1차원 바코드 먼저)."""
        out: list[str] = []
        for g in [*self.barcodes, *(p.gtin for p in self.qr if p.gtin)]:
            if g and g not in out:
                out.append(g)
        return out

    @property
    def urls(self) -> list[str]:
        out: list[str] = []
        for p in self.qr:
            if p.url and p.url not in out:
                out.append(p.url)
        return out


# ── 디코딩 ────────────────────────────────────────────────────

def _format_name(fmt) -> str:
    name = getattr(fmt, "name", None) or str(fmt)
    return name.rsplit(".", 1)[-1]


def _read_all(img, **kwargs) -> list:
    import zxingcpp

    try:
        return [r for r in zxingcpp.read_barcodes(img, **kwargs) if getattr(r, "valid", True)]
    except Exception:  # noqa: BLE001 — 한 번의 시도가 실패해도 다른 시도는 계속한다
        return []


def _tiles(img, n: int, scale: float) -> list:
    """사진을 n×n으로(겹치게) 잘라 scale배 키운 조각들. 태그가 사진의 일부만 차지해서 QR·바코드가 작게
    찍힌 경우(앱이 1280px로 줄여 보내면 특히) 조각을 키워야 읽힌다."""
    from PIL import Image

    w, h = img.size
    tw, th = w / n * 1.5, h / n * 1.5
    out = []
    for i in range(n):
        for j in range(n):
            x = min(w - tw, max(0.0, w * i / n - tw / 6))
            y = min(h - th, max(0.0, h * j / n - th / 6))
            crop = img.crop((int(x), int(y), int(x + tw), int(y + th)))
            out.append(crop.resize((int(crop.width * scale), int(crop.height * scale)), Image.LANCZOS))
    return out


DECODE_BUDGET_S = 1.5  # 디코딩 전체 시간 상한. 태그 읽기(Gemini)와 동시에 돌아서 보통 시간 손해는 없다


def decode_codes(image: bytes, *, budget_s: float = DECODE_BUDGET_S) -> DecodedCodes:
    """사진에서 QR·바코드를 읽는다. 아무것도 없으면 빈 결과(에러 아님).

    한 번에 안 읽히는 경우가 많아서(2026-11-08 오프라인 태그 83장: 기본 한 번은 47장, 아래 단계까지 63장)
    점점 비싼 방법을 차례로 시도한다. QR을 이미 찾았으면 거기서 멈추고, 시간 상한을 넘기면 그만둔다.
      1. 원본 그대로   2. 흑백·선명하게 + 2배 확대   3. 겹치는 조각(2×2 1.5배, 3×3 2배)"""
    try:
        import zxingcpp  # noqa: F401
        from PIL import Image, ImageFilter, ImageOps
    except ImportError as exc:  # 배포 이미지에 패키지가 빠진 경우 — 태그 읽기는 계속한다
        return DecodedCodes(error=f"디코더 없음: {exc}")
    try:
        img = Image.open(io.BytesIO(image))
        img = ImageOps.exif_transpose(img).convert("RGB")  # 폰 사진의 회전 정보 반영
    except Exception as exc:  # noqa: BLE001 — HEIC 등 Pillow가 못 여는 형식
        return DecodedCodes(error=f"사진을 열 수 없음: {type(exc).__name__}")

    deadline = time.monotonic() + budget_s
    out = DecodedCodes()
    seen: set[tuple[str, str]] = set()

    def take(results: list) -> None:
        for r in results:
            text = (getattr(r, "text", "") or "").strip()
            fmt = _format_name(getattr(r, "format", ""))
            if not text or (fmt, text) in seen:
                continue
            seen.add((fmt, text))
            if fmt in LINEAR_GTIN_FORMATS:
                gtin = _normalize_gtin(text)
                if gtin and gtin not in out.barcodes:
                    out.barcodes.append(gtin)
            elif fmt in LINEAR_TEXT_FORMATS:
                code = _linear_code(text)
                if code and code not in out.linear_codes:
                    out.linear_codes.append(code)
            elif fmt in TWO_D_FORMATS and len(out.qr) < MAX_QR_PAYLOADS and all(p.raw != text for p in out.qr):
                out.qr.append(parse_qr_payload(text))

    take(_read_all(img))
    attempts = []
    gray = img.convert("L").filter(ImageFilter.UnsharpMask(radius=2, percent=150, threshold=3))
    attempts.append(lambda: [gray])
    attempts.append(lambda: [gray.resize((gray.width * 2, gray.height * 2), Image.LANCZOS)])
    attempts.append(lambda: _tiles(img, 2, 1.5))
    attempts.append(lambda: _tiles(img, 3, 2.0))
    for make in attempts:
        if out.qr or time.monotonic() >= deadline:
            break
        for piece in make():
            if time.monotonic() >= deadline:
                break
            take(_read_all(piece))
    return out


def _linear_code(text: str) -> str | None:
    """글자 바코드 내용 → 보조 코드. 너무 짧거나 숫자 1~2자리 같은 건 버린다."""
    code = re.sub(r"\s+", "", text or "")
    if len(re.sub(r"[^0-9A-Za-z]", "", code)) < MIN_TEXT_CODE_LEN:
        return None
    return code[:40]


def _normalize_gtin(digits: str) -> str | None:
    """검증된 GTIN만. 14자리인데 앞이 0이면 13자리(EAN-13)로 — 국내 쇼핑몰 페이지는 13자리로 적는다.
    매장 안에서만 쓰는 번호(is_store_internal)는 버린다."""
    d = re.sub(r"\D", "", digits or "")
    if not is_valid_gtin(d):
        return None
    d = d[1:] if len(d) == 14 and d.startswith("0") else d
    return None if is_store_internal(d) else d


def is_store_internal(gtin: str) -> bool:
    """GS1이 매장 내부용으로 남겨 둔 번호대(EAN-13 접두 020~029, 040~049, 200~299). 매장 POS용 가격표 번호라
    온라인 페이지에는 없다 — 검색·확인에 쓰면 진짜 바코드를 밀어낸다(2026-11-08 오클리 태그: 진짜
    8051731168707 옆에 매장용 0200244907084, 유니클로 2000…)."""
    if len(gtin) != 13:
        return False
    prefix = int(gtin[:3])
    return 20 <= prefix <= 29 or 40 <= prefix <= 49 or 200 <= prefix <= 299


# ── QR 내용 나누기 ────────────────────────────────────────────

# GS1 Digital Link: 경로 어딘가에 /01/<8·12·13·14자리 GTIN>
_GS1_PATH_RE = re.compile(r"/(?:01|gtin)/(\d{8}|\d{12,14})(?=/|$|\?)", re.IGNORECASE)
# GS1 요소 문자열(DataMatrix·GS1 QR): 심볼 식별자(]d2 등) 뒤에 (01)<14자리>
_GS1_ELEMENT_RE = re.compile(r"^(?:\][A-Za-z]\d)?\(?01\)?(\d{14})")
_TEXT_TOKEN_RE = re.compile(r"[0-9A-Za-z][0-9A-Za-z\-_/.]*[0-9A-Za-z]")


def parse_qr_payload(text: str) -> QrPayload:
    raw = (text or "").strip()
    lowered = raw.lower()
    url = None
    if lowered.startswith(("http://", "https://")):
        url = raw
    elif lowered.startswith("www."):
        url = "https://" + raw

    if url:
        path = urllib.parse.urlsplit(url).path
        m = _GS1_PATH_RE.search(path)
        if m:
            gtin = _normalize_gtin(m.group(1))
            if gtin:
                return QrPayload(raw, "gs1", url=url, gtin=gtin)
        return QrPayload(raw, "url", url=url)

    m = _GS1_ELEMENT_RE.match(raw)
    if m:
        gtin = _normalize_gtin(m.group(1))
        if gtin:
            return QrPayload(raw, "gs1", gtin=gtin)

    codes: list[str] = []
    for tok in _TEXT_TOKEN_RE.findall(raw):
        if len(re.sub(r"[^0-9A-Za-z]", "", tok)) >= MIN_TEXT_CODE_LEN and tok not in codes:
            codes.append(tok)
    return QrPayload(raw, "text", codes=codes[:5])


# ── 주소 따라가기 (SSRF 방지) ─────────────────────────────────

MAX_HOPS = 6
TOTAL_TIMEOUT_S = 4.0


@dataclass
class QrResolution:
    url: str  # QR에 적힌 주소
    final_url: str  # 리다이렉트를 따라간 최종 주소(못 따라갔으면 마지막으로 확인한 주소)
    ok: bool  # 최종 주소까지 안전하게 도착했는지
    error: str | None = None
    unsafe: bool = False  # 사설망·이상한 스킴 등으로 막았음 — 이 주소는 렌더링하지도 않는다


def _resolve_ips(host: str) -> list[str]:
    infos = socket.getaddrinfo(host, None, proto=socket.IPPROTO_TCP)
    return [info[4][0] for info in infos]


def is_public_url(url: str, *, resolve_ips=_resolve_ips) -> bool:
    """http/https이고, 호스트가 가리키는 모든 IP가 공개 주소일 때만 True.

    ⚠️ DNS 결과가 확인과 실제 요청 사이에 바뀌는 경우(DNS rebinding)까지 막지는 못한다 — 이 함수는
    '대부분의 실수와 단순한 공격'을 막는 1차 방어다. 엔진 태스크의 보안 그룹·VPC에서 사설망 송신을 막는 게
    근본 대책이다."""
    parts = urllib.parse.urlsplit(url or "")
    if parts.scheme not in ("http", "https") or not parts.hostname:
        return False
    if parts.username or parts.password:
        return False
    host = parts.hostname
    try:
        ips = [host] if _is_ip_literal(host) else resolve_ips(host)
    except (OSError, UnicodeError):
        return False
    if not ips:
        return False
    for ip in ips:
        try:
            addr = ipaddress.ip_address(ip.split("%", 1)[0])
        except ValueError:
            return False
        if not addr.is_global:
            return False
    return True


def _is_ip_literal(host: str) -> bool:
    try:
        ipaddress.ip_address(host.strip("[]"))
        return True
    except ValueError:
        return False


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):  # 홉마다 안전한지 직접 확인하려고 자동 리다이렉트를 끈다
        return None


_opener = urllib.request.build_opener(_NoRedirect)


def _fetch_location(url: str, timeout: float) -> str | None:
    """한 번 요청해서 리다이렉트 목적지(없으면 None)를 돌려준다. 본문은 읽지 않는다."""
    req = urllib.request.Request(url, headers={"User-Agent": DESKTOP_UA, "Accept": "text/html"})
    try:
        with _opener.open(req, timeout=timeout):
            return None
    except urllib.error.HTTPError as exc:
        if 300 <= exc.code < 400:
            location = exc.headers.get("Location")
            return urllib.parse.urljoin(url, location) if location else None
        if exc.code in (403, 405, 429):
            return None  # 봇 차단·HEAD 거부 등 — 주소 자체는 최종 주소로 보고 렌더링 단계에 맡긴다
        raise


def resolve_qr_url(
    url: str,
    *,
    fetch=_fetch_location,
    resolve_ips=_resolve_ips,
    total_timeout: float = TOTAL_TIMEOUT_S,
) -> QrResolution:
    """QR 주소의 리다이렉트를 끝까지 따라간다. 홉마다 공개 주소인지 확인하고, 아니면 거기서 멈춘다.
    앱으로 보내는 주소(intent://, 커스텀 스킴)가 나오면 그 안의 웹 대체 주소를 꺼낸다."""
    if not is_public_url(url, resolve_ips=resolve_ips):
        return QrResolution(url, url, ok=False, error="공개 웹 주소가 아님", unsafe=True)
    current = url
    deadline = time.monotonic() + total_timeout
    per_hop = max(0.5, total_timeout / 3)
    try:
        for _ in range(MAX_HOPS):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return QrResolution(url, current, ok=False, error="시간 초과")
            nxt = fetch(current, min(per_hop, remaining))
            if nxt is None:
                return QrResolution(url, current, ok=True)
            scheme = urllib.parse.urlsplit(nxt).scheme
            if scheme not in ("http", "https"):
                fallback = web_fallback_in(nxt) or web_fallback_in(current)
                if fallback and is_public_url(fallback, resolve_ips=resolve_ips):
                    return QrResolution(url, fallback, ok=True)
                return QrResolution(url, current, ok=False, error=f"앱 주소로 이동({scheme})")
            if not is_public_url(nxt, resolve_ips=resolve_ips):
                return QrResolution(url, current, ok=False, error="공개 웹 주소가 아닌 곳으로 이동", unsafe=True)
            current = nxt
        return QrResolution(url, current, ok=False, error="리다이렉트가 너무 많음")
    except Exception as exc:  # noqa: BLE001 — 못 따라가도 엔진 전체는 계속한다
        logger.warning("[identify] QR 주소 따라가기 실패(%s): %s", url, exc)
        return QrResolution(url, current, ok=False, error=type(exc).__name__)
