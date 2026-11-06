import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import '../share/share_link.dart';
import 'basket_picker_sheet.dart';
import 'share_to_friends_sheet.dart';

class SalkamalkaScreen extends StatelessWidget {
  const SalkamalkaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final selected = store.basket.where((b) => b.isSelected).length;

    return Scaffold(
      backgroundColor: DiaryColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SizedBox(
                height: kMinInteractiveDimension,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('살까말까', style: DiaryTheme.display(24)),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: DiaryColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: DiaryTheme.ui(14, weight: FontWeight.w600),
                        children: [
                          const TextSpan(text: '선택한 상품 '),
                          TextSpan(
                            text: '$selected',
                            style: DiaryTheme.ui(14, weight: FontWeight.w800),
                          ),
                          TextSpan(
                            text: ' / ${store.basket.length}',
                            style:
                                DiaryTheme.ui(14, color: DiaryColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 체크한 상품을 한 번에 바구니에서 빼기.
                  TextButton.icon(
                    onPressed: selected == 0
                        ? null
                        : () => _removeSelected(context, store, selected),
                    style: TextButton.styleFrom(
                      foregroundColor: DiaryColors.ink,
                      disabledForegroundColor: DiaryColors.inkSoft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text('선택 삭제', style: DiaryTheme.ui(14)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: store.basket.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: OneLineText(
                          '고민중인 상품을 담아 친구와 공유해보세요',
                          textAlign: TextAlign.center,
                          style: DiaryTheme.body(
                            14,
                            color: DiaryColors.inkSoft,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: store.basket.length,
                      itemBuilder: (context, i) {
                        final item = store.basket[i];
                        return WhiteProductCard(
                          onTap: () =>
                              store.toggleBasketSelected(item.product.id),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 2, 12, 0),
                                child: SelectBox(checked: item.isSelected),
                              ),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  DiaryTheme.radius,
                                ),
                                child: Image.network(
                                  item.product.image,
                                  width: 76,
                                  height: 76,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 76,
                                    height: 76,
                                    color: DiaryColors.surfaceSoft,
                                    child: const Icon(
                                      Icons.checkroom_outlined,
                                      color: DiaryColors.grid,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.platform,
                                      style: DiaryTheme.product(
                                        12,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.product.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: DiaryTheme.product(
                                        13,
                                        color: DiaryColors.inkMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      formatWon(item.product.price),
                                      style: DiaryTheme.product(
                                        15,
                                        weight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    store.removeFromBasket(item.product.id),
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: DiaryColors.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: const BoxDecoration(
                color: DiaryColors.paper,
                border: Border(top: BorderSide(color: DiaryColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: DiaryButton(
                      label: '상품 추가하기',
                      icon: Icons.add,
                      onPressed: () =>
                          _openPickFromWishlistSheet(context, store),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ShareBasketButton(
                      store: store,
                      selected: selected,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeSelected(
    BuildContext context,
    AppStore store,
    int count,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DiaryColors.paper,
        title: Text(
          '선택한 상품 $count개를 뺄까요?',
          style: DiaryTheme.ui(17, weight: FontWeight.w700),
        ),
        content: Text(
          '살까말까 바구니에서만 빠지고, wishkit에는 그대로 남습니다.',
          style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '삭제',
              style: DiaryTheme.ui(
                14,
                weight: FontWeight.w700,
                color: DiaryColors.sale,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final removed = await store.removeSelectedFromBasket();
    if (!context.mounted || removed == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$removed개를 살까말까에서 뺐어요')),
    );
  }

  Future<void> _openPickFromWishlistSheet(
    BuildContext context,
    AppStore store,
  ) async {
    final picked = await showModalBottomSheet<List<Product>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => BasketPickerSheet(store: store),
    );
    if (picked == null || picked.isEmpty) return;
    await store.addManyToBasket(picked);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${picked.length}개를 담았어요')));
  }
}

class _ShareBasketButton extends StatefulWidget {
  const _ShareBasketButton({required this.store, required this.selected});

  final AppStore store;
  final int selected;

  @override
  State<_ShareBasketButton> createState() => _ShareBasketButtonState();
}

class _ShareBasketButtonState extends State<_ShareBasketButton> {
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    return DiaryButton(
      label: _sharing
          ? '보내는 중...'
          : widget.selected == 0
          ? '공유하기'
          : '공유하기 (${widget.selected})',
      filled: true,
      icon: Icons.ios_share,
      onPressed: widget.selected == 0 || _sharing ? null : _share,
    );
  }

  Future<void> _share() async {
    if (_sharing) return;
    final origin = shareOriginOf(context);
    setState(() => _sharing = true);
    try {
      final method = await pickShareMethod(context);
      if (method == null || !mounted) return;
      if (method == ShareMethod.link) {
        await shareBasketLink(
          context: context,
          publish: widget.store.publishSelectedBasketLink,
          message: '${widget.store.currentUser.name}님이 살까말까를 공유했어요. 어떤 게 나을까요?',
          origin: origin,
        );
        return;
      }
      final picked = await showShareToFriendsSheet(
        context: context,
        store: widget.store,
      );
      if (picked == null || picked.friendIds.isEmpty) return;
      final sent = await widget.store.sendBasketToFriends(
        picked.friendIds.toList(),
        memo: picked.memo,
      );
      if (!sent || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${picked.friendIds.length}명의 친구에게 살까말까를 보냈어요')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
