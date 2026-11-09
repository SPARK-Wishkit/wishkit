import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';

/// 살까말까 상품 목록 밑의 투표 (카톡 투표처럼 여러 개 선택).
///
/// - 앱 친구에게 보낸 살까말까(댓글방이 있는 것)에서만 보인다. 참여자만 투표한다.
/// - 마감은 없다. 투표는 살까말까를 따라가서, 살까말까가 없어지면 같이 안 보인다.
/// - 투표 전: 체크 → "투표하기". 투표 후: 결과 + "다시 투표하기".
class BasketVoteSection extends StatefulWidget {
  const BasketVoteSection({super.key, required this.basket});

  final SharedBasket basket;

  @override
  State<BasketVoteSection> createState() => _BasketVoteSectionState();
}

class _BasketVoteSectionState extends State<BasketVoteSection> {
  late Stream<List<BasketVote>> _votes;
  String _threadId = '';

  /// 고르는 중인 상품. null 이면 결과 보기(이미 투표함).
  Set<int>? _draft;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant BasketVoteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 화면이 다시 그려질 때마다 새로 구독하지 않는다 — 댓글방이 바뀔 때만.
    if (widget.basket.commentThreadId != _threadId) _subscribe();
  }

  void _subscribe() {
    _threadId = widget.basket.commentThreadId;
    _votes = context.read<AppStore>().watchBasketVotes(_threadId);
    _draft = null;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final items = widget.basket.items;
    if (_threadId.isEmpty || !store.isLoggedIn || items.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<BasketVote>>(
      stream: _votes,
      builder: (context, snap) {
        final votes = snap.data ?? const <BasketVote>[];
        final mine = votes.where((v) => v.voterUid == store.uid).firstOrNull;
        final editing = _draft != null || mine == null;
        final selection = _draft ??
            {for (final p in items) if (mine?.picked(p) == true) p.id};
        final loading =
            snap.connectionState == ConnectionState.waiting && votes.isEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '투표',
                  style: DiaryTheme.body(16, weight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.basket.allowMultipleVotes ? '복수 선택' : '단일 선택'}${votes.isEmpty ? '' : '  ·  ${votes.length}명 참여'}',
                  style: DiaryTheme.body(12, color: DiaryColors.inkSoft),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: DiaryColors.white,
                borderRadius: BorderRadius.circular(DiaryTheme.radius),
                border: Border.all(color: DiaryColors.line),
              ),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in items)
                    _OptionRow(
                      product: p,
                      editing: editing,
                      checked: selection.contains(p.id),
                      voters: [for (final v in votes) if (v.picked(p)) v],
                      totalVoters: votes.length,
                      onToggle: _sending
                          ? null
                          : () => setState(() {
                                if (widget.basket.allowMultipleVotes) {
                                  final next = {...selection};
                                  if (!next.remove(p.id)) next.add(p.id);
                                  _draft = next;
                                } else {
                                  _draft = selection.contains(p.id) ? <int>{} : <int>{p.id};
                                }
                              }),
                      onShowVoters: (list) => _showVoters(p, list),
                    ),
                  const SizedBox(height: 10),
                  if (loading)
                    const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    _buttons(store, mine, editing, selection),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buttons(
    AppStore store,
    BasketVote? mine,
    bool editing,
    Set<int> selection,
  ) {
    if (!editing) {
      return _VoteButton(
        label: '다시 투표하기',
        filled: false,
        onPressed: () => setState(() => _draft = {
              for (final p in widget.basket.items)
                if (mine!.picked(p)) p.id,
            }),
      );
    }
    return _VoteButton(
      label: '투표하기',
      filled: true,
      busy: _sending,
      onPressed: _sending || (selection.isEmpty && mine == null)
          ? null
          : () => _submit(store, selection),
    );
  }

  Future<void> _submit(AppStore store, Set<int> selection) async {
    setState(() => _sending = true);
    try {
      final ok = await store.voteBasket(
        basket: widget.basket,
        productIds: selection,
      );
      if (ok && mounted) setState(() => _draft = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showVoters(Product product, List<BasketVote> voters) {
    if (voters.isEmpty) return;
    unawaited(showModalBottomSheet<void>(
      context: context,
      backgroundColor: DiaryColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(DiaryTheme.radius)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DiaryColors.grid.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DiaryTheme.ui(16, weight: FontWeight.w700),
              ),
              Text(
                '${voters.length}명이 골랐어요',
                style: DiaryTheme.body(12, color: DiaryColors.inkSoft),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final v in voters)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundImage: NetworkImage(_avatarOf(v)),
                        ),
                        title: Text(
                          v.voterName,
                          style: DiaryTheme.body(14, weight: FontWeight.w700),
                        ),
                        subtitle: v.voterHandle.isEmpty
                            ? null
                            : Text(
                                v.voterHandle,
                                style: DiaryTheme.body(
                                  12,
                                  color: DiaryColors.inkSoft,
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

String _avatarOf(BasketVote v) => v.voterAvatar.isNotEmpty
    ? v.voterAvatar
    : 'https://api.dicebear.com/7.x/thumbs/png?seed=${Uri.encodeComponent(v.voterName)}';

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.product,
    required this.editing,
    required this.checked,
    required this.voters,
    required this.totalVoters,
    required this.onToggle,
    required this.onShowVoters,
  });

  final Product product;
  final bool editing;
  final bool checked;
  final List<BasketVote> voters;
  final int totalVoters;
  final VoidCallback? onToggle;
  final void Function(List<BasketVote>) onShowVoters;

  @override
  Widget build(BuildContext context) {
    final share = totalVoters == 0 ? 0.0 : voters.length / totalVoters;
    return InkWell(
      onTap: editing ? onToggle : () => onShowVoters(voters),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (editing) ...[
              SelectBox(checked: checked, size: 20),
              const SizedBox(width: 10),
            ] else if (checked) ...[
              const Icon(Icons.check, size: 18, color: DiaryColors.ink),
              const SizedBox(width: 8),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 36,
                height: 36,
                child: product.image.isEmpty
                    ? const ColoredBox(color: DiaryColors.band)
                    : Image.network(
                        product.image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: DiaryColors.band),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DiaryTheme.body(
                      13,
                      weight: checked ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: share),
                      duration: const Duration(milliseconds: 250),
                      builder: (_, value, __) => LinearProgressIndicator(
                        value: value,
                        minHeight: 4,
                        backgroundColor: DiaryColors.band,
                        valueColor: const AlwaysStoppedAnimation(
                          DiaryColors.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: voters.isEmpty ? null : () => onShowVoters(voters),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AvatarStack(voters: voters),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${voters.length}',
                      textAlign: TextAlign.right,
                      style: DiaryTheme.body(13, weight: FontWeight.w700),
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
}

/// 고른 사람 얼굴 최대 3개를 겹쳐 보여 준다.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.voters});

  final List<BasketVote> voters;

  @override
  Widget build(BuildContext context) {
    final shown = voters.take(3).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    const size = 20.0;
    const step = 13.0;
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: const BoxDecoration(
                  color: DiaryColors.white,
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: size / 2 - 1.5,
                  backgroundImage: NetworkImage(_avatarOf(shown[i])),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.label,
    required this.filled,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final bool filled;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final child = busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: DiaryColors.white,
            ),
          )
        : Text(label, style: DiaryTheme.ui(14, weight: FontWeight.w700));
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: DiaryColors.ink,
          foregroundColor: DiaryColors.white,
          disabledBackgroundColor: DiaryColors.tabIdle,
          disabledForegroundColor: DiaryColors.inkSoft,
          minimumSize: const Size.fromHeight(44),
          shape: shape,
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: DiaryColors.ink,
        side: const BorderSide(color: DiaryColors.lineStrong),
        minimumSize: const Size.fromHeight(44),
        shape: shape,
      ),
      child: child,
    );
  }
}
