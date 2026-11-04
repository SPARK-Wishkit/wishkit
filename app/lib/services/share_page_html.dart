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
  final ogImage = firstImage == null ? '' : htmlEscape(firstImage);
  final description = htmlEscape(
    '$owner 님이 살까말까 바구니에서 상품 ${basket.items.length}개를 공유했어요',
  );

  final cards = basket.items.map(_productCardHtml).join('\n');
  final body = cards.isEmpty
      ? '<p class="empty">아직 공개된 아이템이 없어요</p>'
      : cards;

  return '''<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title</title>
  <meta name="description" content="$description">
  <meta property="og:title" content="$title">
  <meta property="og:description" content="$description">
  ${ogImage.isEmpty ? '' : '<meta property="og:image" content="$ogImage">'}
  <meta property="og:type" content="website">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Righteous&family=Noto+Sans+KR:wght@400;600;700&display=swap" rel="stylesheet">
  <style>
    /* Mirrors DiaryColors / ListCardMetrics in the app (lib/theme). */
    :root {
      --canvas: #f2f2f2;
      --paper: #ffffff;
      --surface-soft: #f3f3f3;
      --line: #e8e8e8;
      --ink: #000000;
      --ink-muted: #3a3a3a;
      --ink-soft: #6e6e6e;
      --sale: #e0322b;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--canvas);
      color: var(--ink);
      font-family: "Noto Sans KR", sans-serif;
      word-break: keep-all;
      overflow-wrap: anywhere;
    }
    /* Fill the screen height on every phone: sheet stretches, footer sits at the bottom. */
    .page {
      max-width: 560px;
      margin: 0 auto;
      min-height: 100vh;
      min-height: 100dvh;
      display: flex;
      flex-direction: column;
    }
    header {
      padding: 18px 20px 12px;
    }
    .logo {
      font-family: Righteous, sans-serif;
      font-size: 30px;
      line-height: 1.1;
    }
    h1 {
      margin: 14px 0 0;
      font-size: 19px;
      font-weight: 700;
    }
    .subtitle {
      margin: 4px 0 0;
      font-size: 13px;
      color: var(--ink-muted);
    }
    .sheet {
      margin: 0 12px;
      background: var(--paper);
      border-radius: 18px 18px 0 0;
      padding: 16px 16px 28px;
      flex: 1;
    }
    .card {
      display: flex;
      gap: 14px;
      align-items: flex-start;
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 12px;
      margin-bottom: 12px;
      color: inherit;
      text-decoration: none;
    }
    /* Photo scales with screen width (88px on normal phones, smaller on narrow ones). */
    .thumb {
      --thumb: clamp(64px, 22vw, 88px);
      width: var(--thumb);
      height: var(--thumb);
      border-radius: 12px;
      object-fit: cover;
      background: var(--surface-soft);
      flex: 0 0 var(--thumb);
    }
    .info { min-width: 0; line-height: 1.35; }
    .platform {
      font-size: 12px;
      color: var(--ink-soft);
    }
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
    .price-row {
      margin-top: 6px;
      display: flex;
      flex-wrap: wrap;
      align-items: baseline;
      column-gap: 6px;
    }
    .original, .price { white-space: nowrap; }
    .original {
      font-size: 12px;
      color: var(--ink-soft);
      text-decoration: line-through;
    }
    .price {
      font-size: 17px;
      font-weight: 700;
    }
    .rate {
      margin-top: 2px;
      font-size: 13px;
      font-weight: 700;
      color: var(--sale);
    }
    .empty {
      text-align: center;
      color: var(--ink-muted);
      font-size: 14px;
      padding: 48px 12px;
    }
    footer {
      text-align: center;
      color: var(--ink-soft);
      font-size: 12px;
      padding: 20px 20px 32px;
      line-height: 1.5;
    }
  </style>
</head>
<body>
  <div class="page">
    <header>
      <div class="logo">wishkit</div>
      <h1>$title</h1>
      <p class="subtitle">$owner 님이 공유한 살까말까 바구니</p>
    </header>
    <main class="sheet">
      $body
    </main>
    <footer>
      이 페이지는 $expiryLabel까지 볼 수 있어요. 그 뒤에는 자동으로 사라집니다.
    </footer>
  </div>
</body>
</html>
''';
}

String _productCardHtml(Product product) {
  final platform = htmlEscape(product.platform);
  final name = htmlEscape(product.name);
  final price = htmlEscape(formatWon(product.price));
  final orig = product.originalPrice;
  final original = (orig == null || orig <= product.price)
      ? ''
      : '<span class="original">${htmlEscape(formatWon(orig))}</span>';
  final rate = _discountRate(product);
  final rateHtml = rate == null ? '' : '\n        <div class="rate">$rate%</div>';
  final imageUrl = safeHttpUrl(product.image);
  final image = imageUrl == null
      ? '<div class="thumb" aria-hidden="true"></div>'
      : '<img class="thumb" src="${htmlEscape(imageUrl)}" alt="">';
  final href = safeHttpUrl(product.productUrl);
  final inner = '''
      $image
      <div class="info">
        <div class="platform">$platform</div>
        <div class="name">$name</div>
        <div class="price-row">$original<span class="price">$price</span></div>$rateHtml
      </div>''';
  if (href == null) {
    return '      <div class="card">$inner\n      </div>';
  }
  return '      <a class="card" href="${htmlEscape(href)}" target="_blank" rel="noopener noreferrer">$inner\n      </a>';
}

/// Same rule as WishlistProductCard._discountRate in the app.
int? _discountRate(Product product) {
  final d = product.discount;
  if (d != null && d > 0) return d;
  final orig = product.originalPrice;
  if (orig == null || orig <= product.price || orig == 0) return null;
  return ((orig - product.price) * 100 / orig).round();
}
