"""qr_codes.py 단위 테스트. 네트워크·DNS는 가짜로 바꿔 끼운다(실제 요청 없음).
QR·바코드 사진은 zxing-cpp로 그 자리에서 만든다."""
import io

import pytest

from qr_codes import (
    DecodedCodes,
    QrPayload,
    decode_codes,
    is_public_url,
    parse_qr_payload,
    resolve_qr_url,
)

zxingcpp = pytest.importorskip("zxingcpp")
Image = pytest.importorskip("PIL.Image")


def _image_bytes(*items: tuple[str, str], fmt: str = "JPEG") -> bytes:
    """(포맷 이름, 내용) 들을 가로로 이어 붙인 사진(태그에 QR과 바코드가 같이 있는 경우 흉내)."""
    tiles = []
    for name, text in items:
        bc = zxingcpp.create_barcode(text, getattr(zxingcpp.BarcodeFormat, name))
        tiles.append(Image.fromarray(zxingcpp.write_barcode_to_image(bc, scale=4)).convert("RGB"))
    pad = 40
    width = sum(t.width for t in tiles) + pad * (len(tiles) + 1)
    height = max(t.height for t in tiles) + pad * 2
    canvas = Image.new("RGB", (width, height), "white")
    x = pad
    for t in tiles:
        canvas.paste(t, (x, pad))
        x += t.width + pad
    buf = io.BytesIO()
    canvas.save(buf, fmt)
    return buf.getvalue()


# ── 디코딩 ──

def test_decode_reads_qr_and_validated_barcode_together():
    image = _image_bytes(("QRCode", "https://brand.example/product/DV1234-100"), ("EAN13", "8801234567893"))
    codes = decode_codes(image)
    assert codes.error is None
    assert codes.urls == ["https://brand.example/product/DV1234-100"]
    assert codes.barcodes == ["8801234567893"]


def test_decode_empty_photo_is_not_an_error():
    buf = io.BytesIO()
    Image.new("RGB", (200, 200), "white").save(buf, "JPEG")
    codes = decode_codes(buf.getvalue())
    assert codes.error is None and codes.qr == [] and codes.barcodes == []


def test_decode_unreadable_bytes_reports_error_instead_of_raising():
    codes = decode_codes(b"not an image")
    assert codes.error and codes.qr == []


# ── QR 내용 나누기 ──

def test_gs1_digital_link_gives_gtin_and_keeps_url():
    p = parse_qr_payload("https://id.gs1.org/01/08801234567893/21/SERIAL1")
    assert p.kind == "gs1"
    assert p.gtin == "8801234567893"  # 14자리 앞의 0을 떼어 EAN-13 모양으로
    assert p.url.startswith("https://id.gs1.org/")


def test_gs1_link_with_bad_check_digit_is_plain_url():
    p = parse_qr_payload("https://brand.example/01/08801234567890")
    assert p.kind == "url" and p.gtin is None


def test_gs1_element_string_without_url():
    p = parse_qr_payload("]d20108801234567893" + "\x1d" + "10LOT1")
    assert p.kind == "gs1" and p.gtin == "8801234567893" and p.url is None


def test_www_without_scheme_becomes_https_url():
    p = parse_qr_payload("www.brand.co.kr/item/123")
    assert p.kind == "url" and p.url == "https://www.brand.co.kr/item/123"


def test_text_qr_keeps_only_code_like_tokens():
    p = parse_qr_payload("STYLE 93251-TTL-1202 / SIZE M")
    assert p.kind == "text"
    assert "93251-TTL-1202" in p.codes
    assert "SIZE" not in p.codes and "M" not in p.codes


def test_gtins_merges_barcode_and_gs1_without_duplicates():
    codes = DecodedCodes(
        qr=[QrPayload("x", "gs1", gtin="8801234567893"), QrPayload("y", "url", url="https://a.example/p")],
        barcodes=["8801234567893"],
    )
    assert codes.gtins == ["8801234567893"]
    assert codes.urls == ["https://a.example/p"]


# ── 공개 주소 확인 (SSRF 방지) ──

def _dns(mapping):
    def resolve(host):
        if host not in mapping:
            raise OSError("NXDOMAIN")
        return mapping[host]
    return resolve


@pytest.mark.parametrize("url", [
    "http://169.254.169.254/latest/meta-data/",  # 클라우드 메타데이터
    "http://127.0.0.1:8000/healthz",
    "http://[::1]/",
    "http://10.0.0.5/",
    "file:///etc/passwd",
    "javascript:alert(1)",
    "https://user:pw@brand.example/",
])
def test_non_public_urls_are_rejected(url):
    assert not is_public_url(url, resolve_ips=_dns({"brand.example": ["93.184.216.34"]}))


def test_hostname_pointing_to_private_ip_is_rejected():
    resolve = _dns({"evil.example": ["93.184.216.34", "192.168.0.10"]})  # 하나라도 사설이면 거절
    assert not is_public_url("https://evil.example/p", resolve_ips=resolve)


def test_public_hostname_is_allowed():
    assert is_public_url("https://brand.example/p", resolve_ips=_dns({"brand.example": ["93.184.216.34"]}))


# ── 주소 따라가기 ──

PUBLIC = {"qr.brand.example": ["93.184.216.34"], "brand.example": ["93.184.216.34"],
          "internal.example": ["10.1.2.3"]}


def test_resolve_follows_redirects_to_final_page():
    hops = {"https://qr.brand.example/a": "https://brand.example/product/DV1234-100"}
    res = resolve_qr_url("https://qr.brand.example/a", fetch=lambda u, t: hops.get(u),
                         resolve_ips=_dns(PUBLIC))
    assert res.ok and res.final_url == "https://brand.example/product/DV1234-100"


def test_resolve_stops_before_redirect_into_private_network():
    calls = []

    def fetch(url, timeout):
        calls.append(url)
        return "http://internal.example/admin"

    res = resolve_qr_url("https://qr.brand.example/a", fetch=fetch, resolve_ips=_dns(PUBLIC))
    assert res.unsafe and not res.ok
    assert calls == ["https://qr.brand.example/a"]  # 사설 주소로는 요청을 보내지 않았다


def test_resolve_rejects_private_start_without_any_request():
    def fetch(url, timeout):
        raise AssertionError("요청하면 안 됨")

    res = resolve_qr_url("http://169.254.169.254/", fetch=fetch, resolve_ips=_dns(PUBLIC))
    assert res.unsafe


def test_resolve_app_scheme_uses_web_fallback():
    app_url = "brandapp://item?id=1&af_web_dp=https%3A%2F%2Fbrand.example%2Fproduct%2F1"
    res = resolve_qr_url("https://qr.brand.example/a", fetch=lambda u, t: app_url, resolve_ips=_dns(PUBLIC))
    assert res.ok and res.final_url == "https://brand.example/product/1"


def test_resolve_network_error_keeps_last_safe_url():
    def fetch(url, timeout):
        raise TimeoutError("느림")

    res = resolve_qr_url("https://qr.brand.example/a", fetch=fetch, resolve_ips=_dns(PUBLIC))
    assert not res.ok and not res.unsafe and res.final_url == "https://qr.brand.example/a"


def test_decode_keeps_text_barcode_content_as_code():
    # 국내 태그는 Code128/93/39에 품번을 그대로 넣는 경우가 많다(비이커·크림·뉴발란스·지오다노).
    codes = decode_codes(_image_bytes(("Code128", "KW6DKNCAE08NY_002")))
    assert codes.linear_codes == ["KW6DKNCAE08NY_002"]
    assert codes.barcodes == []


def test_store_internal_barcode_is_dropped_but_real_one_kept():
    # 오클리 태그: 진짜 EAN 8051731168707과 매장용 0200244907084가 같이 있다.
    codes = decode_codes(_image_bytes(("EAN13", "0200244907084"), ("EAN13", "8051731168707")))
    assert codes.barcodes == ["8051731168707"]
