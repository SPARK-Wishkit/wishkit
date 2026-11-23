"""render._meta_text — 본문에 없고 메타 태그에만 있는 품번을 읽는지."""
from render import _meta_text

MUSINSA_HEAD = """<html><head>
<title>1993스튜디오(1993STUDIO) 베이직 우먼 롱슬리브 (8colors) - 사이즈 &amp; 후기 | 무신사</title>
<meta name="description" content="브랜드 : 1993스튜디오(1993STUDIO) 제품번호 : 93251TTL1202 제품 : 베이직 우먼 롱슬리브">
<meta property="og:description" content="브랜드 : 1993스튜디오(1993STUDIO) 제품번호 : 93251TTL1202 제품 : 베이직 우먼 롱슬리브">
<meta property="product:price:normal_price" content="29900">
<meta name="viewport" content="width=device-width">
</head><body><div>베이직 우먼 롱슬리브 29,900원</div><meta name="description" content="본문 메타"></body></html>"""


def test_meta_text_reads_code_from_description():
    text = _meta_text(MUSINSA_HEAD)
    assert "93251TTL1202" in text
    assert "29900" in text            # product: 메타도 포함
    assert "width=device-width" not in text  # 관계없는 메타는 뺀다
    assert text.count("제품번호") == 1  # description·og:description 같은 문장은 한 번만


def test_meta_text_empty_when_no_meta():
    assert _meta_text("<html><body>본문만</body></html>") == ""


# ── _code_hints: 화면 밖 품번 단서 ──────────────────────────

from render import _code_hints  # noqa: E402

_HINT_PAGE = """<html><head>
<meta property="og:image" content="https://img.x.com/goods/DV1234-100_01.jpg">
<link rel="canonical" href="https://x.com/p/777">
<meta property="product:retailer_item_id" content="GM0024102812345">
<meta property="product:price:amount" content="139000">
<script type="application/ld+json">{"@context": "https://schema.org", "@graph": [
  {"@type": "Product", "name": "AF1", "sku": "DV1234-100", "gtin13": 8801234567893,
   "image": ["https://i/a.jpg", {"url": "https://i/b.jpg"}],
   "offers": {"@type": "Offer", "price": 139000, "mpn": "MPN-1"}},
  {"@type": "BreadcrumbList", "itemListElement": [{"name": "OTHER-999"}]}]}</script>
<script type="application/ld+json">이건 JSON이 아님</script>
</head><body><img src="https://img.x.com/recommend/ZZ9999-001.jpg"><p>본문</p></body></html>"""


def test_code_hints_collects_main_product_codes_only():
    hints = _code_hints(_HINT_PAGE)
    for expected in ("https://img.x.com/goods/DV1234-100_01.jpg", "https://x.com/p/777", "DV1234-100",
                     "8801234567893", "https://i/a.jpg", "https://i/b.jpg", "MPN-1", "GM0024102812345"):
        assert expected in hints
    # 가격·추천 상품 이미지·Product가 아닌 구조화 데이터는 넣지 않는다(엉뚱한 일치 방지)
    assert "139000" not in hints
    assert not any("ZZ9999" in h or "OTHER-999" in h for h in hints)


def test_code_hints_never_raises_on_broken_html():
    assert _code_hints("<html><script type='application/ld+json'>{") == []
