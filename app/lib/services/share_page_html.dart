import '../models/models.dart';
import '../widgets/diary_widgets.dart';

/// 공개 공유 페이지가 열려 있는 기간. 그 뒤에는 S3 수명 규칙이 지운다(backend.ts, share-pages/ 28일).
const kSharePageTtl = Duration(days: 28);

String htmlEscape(String raw) {
  return raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String? safeHttpUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri.toString();
}

String formatShareExpiry(DateTime expiresAt) {
  final local = expiresAt.toLocal();
  return '${local.year}년 ${local.month}월 ${local.day}일';
}

/// Standalone HTML that mirrors [SharedWishlistScreen] for link shares.
String buildSharePageHtml({
  required SharedBasket basket,
  required DateTime expiresAt,
  String? ogImageUrl,
}) {
  final title = htmlEscape(
    basket.title.trim().isEmpty ? '살까말까 공유' : basket.title.trim(),
  );
  final owner = htmlEscape(
    basket.ownerName.trim().isEmpty ? '친구' : basket.ownerName.trim(),
  );
  final expiryLabel = htmlEscape(formatShareExpiry(expiresAt));
  final firstImage = basket.items
      .map((p) => safeHttpUrl(p.image))
      .whereType<String>()
      .firstOrNull;
  // 미리보기 이미지: 앱 로고([ogImageUrl])가 있으면 그걸, 없으면(올리기 실패 등) 첫 상품 사진.
  final logo = ogImageUrl == null ? null : safeHttpUrl(ogImageUrl);
  final ogImage = htmlEscape(logo ?? firstImage ?? '');
  final ogImageSize = logo == null
      ? ''
      : '\n  <meta property="og:image:width" content="1200">'
          '\n  <meta property="og:image:height" content="630">'
          '\n  <meta name="twitter:card" content="summary_large_image">';
  final description = htmlEscape(
    '$owner 님이 살까말까 바구니에서 상품 ${basket.items.length}개를 공유했어요',
  );

  // 목록의 카드는 상품 사이트로 바로 가지 않고, 앱의 상품 화면처럼 이 페이지 안의 상세(#item-N)를 연다.
  // 상세에서 고민하는 이유·할인을 보고 "상품 보러가기" 버튼으로 이동한다.
  final items = basket.items;
  final cards = [
    for (var i = 0; i < items.length; i++) _productCardHtml(items[i], i + 1),
  ].join('\n');
  final details = [
    for (var i = 0; i < items.length; i++) _productDetailHtml(items[i], i + 1),
  ].join('\n');
  final note = basket.memo.trim();
  final noteHtml = note.isEmpty
      ? ''
      : '<p class="note">${htmlEscape(note)}</p>\n      ';
  final body = cards.isEmpty
      ? '<p class="empty">아직 공개된 아이템이 없어요</p>'
      : '$noteHtml<h2 class="count">고민 중인 상품 ${items.length}개</h2>\n$cards';

  return '''<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>$title</title>
  <meta name="description" content="$description">
  <meta property="og:title" content="$title">
  <meta property="og:description" content="$description">
  ${ogImage.isEmpty ? '' : '<meta property="og:image" content="$ogImage">$ogImageSize'}
  <meta property="og:type" content="website">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Righteous&family=Noto+Sans+KR:wght@400;700;800&display=swap" rel="stylesheet">
  <style>
    /* 앱 디자인(2026-11, 무신사풍 흑백)과 같은 색·크기 — lib/theme/diary_theme.dart, WishlistProductCard */
    :root {
      --paper: #ffffff;
      --soft: #f3f3f3;
      --line: #e8e8e8;
      --ink: #000000;
      --muted: #3a3a3a;
      --soft-ink: #6e6e6e;
      --sale: #e0322b;
    }
    * { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; }
    body {
      margin: 0;
      background: var(--paper);
      color: var(--ink);
      font-family: "Noto Sans KR", -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif;
      padding-bottom: env(safe-area-inset-bottom, 0px);
    }
    .page { max-width: 560px; margin: 0 auto; }
    header {
      padding: calc(14px + env(safe-area-inset-top, 0px)) 16px 12px;
      border-bottom: 1px solid var(--line);
    }
    .brand {
      font-family: Righteous, "Noto Sans KR", sans-serif;
      font-size: 22px;
      line-height: 1.1;
    }
    h1 {
      margin: 12px 0 0;
      font-size: 20px;
      font-weight: 800;
      letter-spacing: -0.6px;
      line-height: 1.2;
    }
    .subtitle {
      margin: 6px 0 0;
      font-size: 13px;
      color: var(--muted);
    }
    main { padding: 12px 16px 20px; }
    .card {
      display: flex;
      gap: 14px;
      align-items: flex-start;
      min-height: 112px;
      padding: 12px;
      margin-bottom: 12px;
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 14px;
      color: inherit;
      text-decoration: none;
    }
    .thumb {
      width: 88px;
      height: 88px;
      flex: 0 0 88px;
      border-radius: 12px;
      object-fit: cover;
      background: var(--soft);
    }
    .info { min-width: 0; }
    .platform { font-size: 12px; color: var(--soft-ink); line-height: 1.35; }
    .name {
      margin-top: 2px;
      font-size: 15px;
      font-weight: 700;
      line-height: 1.3;
      display: -webkit-box;
      -webkit-line-clamp: 2;
      -webkit-box-orient: vertical;
      overflow: hidden;
    }
    .price-row { margin-top: 6px; display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px; }
    .original { font-size: 12px; color: var(--soft-ink); text-decoration: line-through; }
    .price { font-size: 17px; font-weight: 700; }
    .rate { margin-top: 2px; font-size: 13px; font-weight: 700; color: var(--sale); }
    .empty {
      text-align: center;
      color: var(--muted);
      font-size: 14px;
      padding: 48px 12px;
    }
    footer {
      text-align: center;
      color: var(--soft-ink);
      font-size: 12px;
      line-height: 1.5;
      padding: 8px 20px 32px;
    }
    footer .brand { font-size: 14px; color: var(--ink); margin-top: 6px; }
    .note {
      margin: 4px 0 14px;
      padding: 12px 14px;
      background: var(--soft);
      border-radius: 12px;
      font-size: 15px;
      line-height: 1.5;
      white-space: pre-wrap;
    }
    .count { margin: 4px 0 10px; font-size: 16px; font-weight: 700; }
    /* 상품 상세(앱 상품 화면과 같은 구성). 스크립트가 없어도 #item-N 으로 열린다. */
    .detail { display: none; padding: 12px 16px 24px; }
    .detail:target { display: block; }
    body.detail-open #list { display: none; }
    .back {
      display: inline-flex; align-items: center; gap: 4px;
      margin: 0 0 12px; color: var(--ink); font-size: 14px; text-decoration: none;
    }
    .hero {
      width: 100%; aspect-ratio: 1 / 1; object-fit: cover;
      border-radius: 14px; background: var(--soft); display: block;
    }
    .detail .platform { margin-top: 12px; }
    .detail .name { font-size: 18px; -webkit-line-clamp: unset; display: block; margin-top: 2px; }
    .detail .price-row { margin-top: 6px; }
    .detail .price { font-size: 20px; font-weight: 800; }
    .detail .original { font-size: 13px; }
    .chip {
      display: inline-block; margin-top: 8px; padding: 4px 8px;
      border-radius: 8px; background: rgba(224, 50, 43, 0.08);
      color: var(--sale); font-size: 12px; font-weight: 700;
    }
    .reason {
      margin-top: 14px; padding: 12px;
      border: 1px solid #d6d6d6; border-radius: 12px;
    }
    .reason h3 { margin: 0; font-size: 14px; font-weight: 700; }
    .reason p { margin: 6px 0 0; font-size: 14px; line-height: 1.5; white-space: pre-wrap; }
    .reason p.none { color: var(--soft-ink); font-size: 13px; }
    .go {
      display: flex; align-items: center; justify-content: center; gap: 6px;
      margin-top: 14px; height: 48px; border-radius: 12px;
      background: var(--ink); color: #fff; font-size: 15px; font-weight: 700; text-decoration: none;
    }
  </style>
</head>
<body>
  <div class="page">
    <header>
      <div class="brand">wishkit</div>
      <h1>$title</h1>
      <p class="subtitle">$owner 님이 공유한 살까말까 바구니</p>
    </header>
    <main id="list">
      $body
    </main>
$details
    <footer>
      이 페이지는 $expiryLabel까지 볼 수 있어요. 그 뒤에는 자동으로 사라집니다.
      <div class="brand">wishkit</div>
    </footer>
  </div>
  <script>
    // 상품 카드를 누르면 목록 대신 그 상품 상세만 보이게(뒤로 가기 = 목록).
    function route() {
      var id = location.hash.slice(1);
      var d = id ? document.getElementById(id) : null;
      var open = !!(d && d.classList.contains('detail'));
      document.body.classList.toggle('detail-open', open);
      window.scrollTo(0, 0);
    }
    window.addEventListener('hashchange', route);
    route();
  </script>
</body>
</html>
''';
}

/// 할인율 — 앱 카드(WishlistProductCard._discountRate)와 같은 규칙.
int? _discountRate(Product p) {
  final d = p.discount;
  if (d != null && d > 0) return d;
  final orig = p.originalPrice;
  if (orig == null || orig <= p.price || orig == 0) return null;
  return ((orig - p.price) * 100 / orig).round();
}

String _productCardHtml(Product product, int index) {
  final platform = htmlEscape(product.platform);
  final name = htmlEscape(product.name);
  final price = htmlEscape(formatWon(product.price));
  final original = product.originalPrice == null ||
          product.originalPrice! <= product.price
      ? ''
      : '<span class="original">${htmlEscape(formatWon(product.originalPrice!))}</span>';
  final rate = _discountRate(product);
  final rateHtml = rate == null ? '' : '\n        <div class="rate">$rate%</div>';
  final imageUrl = safeHttpUrl(product.image);
  final image = imageUrl == null
      ? '<div class="thumb" aria-hidden="true"></div>'
      : '<img class="thumb" src="${htmlEscape(imageUrl)}" alt="" loading="lazy">';
  return '''      <a class="card" href="#item-$index">
      $image
      <div class="info">
        <div class="platform">$platform</div>
        <div class="name">$name</div>
        <div class="price-row">$original<span class="price">$price</span></div>$rateHtml
      </div>
      </a>''';
}

/// 앱의 상품 화면과 같은 구성: 큰 사진 · 쇼핑몰 · 이름 · 가격 · 할인 · 고민하는 이유 · 상품 보러가기.
String _productDetailHtml(Product product, int index) {
  final platform = htmlEscape(product.platform);
  final name = htmlEscape(product.name);
  final price = htmlEscape(formatWon(product.price));
  final original = product.originalPrice == null ||
          product.originalPrice! <= product.price
      ? ''
      : '<span class="original">${htmlEscape(formatWon(product.originalPrice!))}</span>';
  final rate = _discountRate(product);
  final chip = rate == null ? '' : '\n    <div class="chip">$rate% 할인 중</div>';
  final imageUrl = safeHttpUrl(product.image);
  final image = imageUrl == null
      ? '<div class="hero" aria-hidden="true"></div>'
      : '<img class="hero" src="${htmlEscape(imageUrl)}" alt="">';
  final memo = (product.memo ?? '').trim();
  final reason = memo.isEmpty
      ? '<p class="none">남긴 이유가 없어요</p>'
      : '<p>${htmlEscape(memo)}</p>';
  final href = safeHttpUrl(product.productUrl);
  final go = href == null
      ? ''
      : '\n    <a class="go" href="${htmlEscape(href)}" target="_blank" rel="noopener noreferrer">상품 보러가기 ↗</a>';
  return '''  <section class="detail" id="item-$index">
    <a class="back" href="#">← 목록으로</a>
    $image
    <div class="platform">$platform</div>
    <div class="name">$name</div>
    <div class="price-row"><span class="price">$price</span>$original</div>$chip
    <div class="reason">
      <h3>고민하는 이유</h3>
      $reason
    </div>$go
  </section>''';
}
