import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ads/ad_feed.dart';
import '../../ads/ads_config.dart';
import '../../ads/native_ad_card.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import '../product/product_detail_screen.dart';
import '../wishlist/wishlist_screen.dart';

/// Read-only wishlist list UI (friend lists + shared basket URL views).
/// Matches the own-wishlist card layout (product row → detail).
class SharedWishlistScreen extends StatelessWidget {
  const SharedWishlistScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.products,
    this.accentColor,
    this.emptyMessage = '아직 공개된 아이템이 없어요',
    this.onShare,
    this.wishlistId,
    this.basketId,
    this.friendId,
    this.onMore,
  });

  final String title;
  final String subtitle;
  final List<Product> products;
  final Color? accentColor;
  final String emptyMessage;
  final VoidCallback? onShare;
  final String? wishlistId;
  final String? basketId;
  final String? friendId;

  /// 친구 wishkit: 신고·차단 메뉴. null 이면 버튼을 숨긴다.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final adFeed = AdFeed(products.length, every: AdsConfig.feedEvery);

    return Scaffold(
      backgroundColor: DiaryColors.paper,
      appBar: AppBar(
        backgroundColor: DiaryColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          title,
          style: DiaryTheme.ui(17, weight: FontWeight.w700),
        ),
        actions: [
          if (onShare != null)
            IconButton(
              tooltip: '다시 보내기',
              onPressed: onShare,
              icon: const Icon(Icons.ios_share),
            ),
          if (onMore != null)
            IconButton(
              tooltip: '신고·차단',
              onPressed: onMore,
              icon: const Icon(Icons.more_vert),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitle,
                  style: DiaryTheme.ui(13, color: DiaryColors.inkMuted),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.zero,
                child: Container(
                  decoration: const BoxDecoration(
                    color: DiaryColors.paper,
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(DiaryTheme.radius),
                    ),
                    child: DiaryGridPaper(
                      padding: EdgeInsets.zero,
                      borderRadius: 0,
                      child: products.isEmpty
                          ? Center(
                              child: Text(
                                emptyMessage,
                                style: DiaryTheme.ui(
                                  14,
                                  color: DiaryColors.inkMuted,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                              itemCount: adFeed.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                if (adFeed.isAd(i)) {
                                  return NativeAdCard(
                                    key: ValueKey('ad-${adFeed.adSlot(i)}'),
                                  );
                                }
                                final p = products[adFeed.itemIndex(i)];
                                return WishlistProductCard(
                                  product: p,
                                  onOpen: () => context.push(
                                    catalogProductLocation(
                                      p.id,
                                      wishlistId: wishlistId,
                                      basketId: basketId,
                                      friendId: friendId,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
