import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import '../product/product_detail_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final searchCtrl = TextEditingController();
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<AppStore>();
      if (!store.backendReady || !store.isLoggedIn) return;
      setState(() => refreshing = true);
      try {
        await store.refreshFriends();
      } finally {
        if (mounted) setState(() => refreshing = false);
      }
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(String name, String handle, String q) {
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) || handle.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final q = searchCtrl.text.trim().toLowerCase();

    final followingFriends = store.friends
        .where((f) => f.isFollowing && _matchesQuery(f.name, f.username, q))
        .toList();
    // Search hits, or everyone not yet followed so 팔로우 is always available.
    final discoverFriends = store.friends
        .where((f) => !f.isFollowing && _matchesQuery(f.name, f.username, q))
        .take(40)
        .toList();
    final followers = store.followerUsers
        .where((u) => _matchesQuery(u.name, u.handle, q))
        .toList();
    final wishlistCards = store.friendWishlists.where((w) {
      final friend = store.friendById(w.friendId);
      if (friend == null || !friend.isFollowing) return false;
      return _matchesQuery(w.friendName, friend.username, q) ||
          w.listName.toLowerCase().contains(q);
    }).toList();
    final salkamalkaFeed = store.salkamalkaFeed.where((e) {
      if (q.isEmpty) return true;
      final b = e.basket;
      return _matchesQuery(b.ownerName, b.fromHandle, q) ||
          b.recipientNames.any((n) => n.toLowerCase().contains(q));
    }).toList();
    final unread = store.unreadNotificationCount;
    final tab = store.friendsTab;

    return Scaffold(
      backgroundColor: DiaryColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('내 친구', style: DiaryTheme.display(24)),
                      const Spacer(),
                      if (refreshing)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        IconButton(
                          tooltip: '친구 목록 새로고침',
                          onPressed: () async {
                            setState(() => refreshing = true);
                            try {
                              await store.refreshFriends();
                            } finally {
                              if (mounted) {
                                setState(() => refreshing = false);
                              }
                            }
                          },
                          icon: const Icon(Icons.refresh),
                        ),
                      IconButton(
                        tooltip: '알림',
                        onPressed: () => context.push('/notifications'),
                        icon: Badge(
                          isLabelVisible: unread > 0,
                          label: Text(unread > 99 ? '99+' : '$unread'),
                          child: const Icon(Icons.notifications_none),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: searchCtrl,
                        onChanged: (_) => setState(() {}),
                        style: DiaryTheme.ui(14),
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: '이름·아이디로 검색',
                          hintStyle: DiaryTheme.ui(
                            14,
                            color: DiaryColors.inkSoft,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 20,
                            color: DiaryColors.ink,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          filled: true,
                          fillColor: DiaryColors.band,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              DiaryTheme.radius,
                            ),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _UnderlineTabs(
              labels: const ['팔로잉', '팔로워', 'wishlist', '살까말까'],
              selected: tab,
              onSelect: store.selectFriendsTab,
            ),
            Expanded(
              child: SpiralNotebook(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: switch (tab) {
                    0 => _FollowingList(
                      following: followingFriends,
                      discover: discoverFriends,
                      searching: q.isNotEmpty,
                      onToggleFollow: (f) => store.toggleFollow(f.id),
                    ),
                    1 => _FollowersList(
                      followers: followers,
                      onRemove: (u) => store.removeFollower(u.uid),
                    ),
                    2 => _FriendWishlistsPane(
                      wishlists: wishlistCards,
                      followingEmpty: store.friends
                          .where((f) => f.isFollowing)
                          .isEmpty,
                    ),
                    _ => _SalkamalkaFeedPane(entries: salkamalkaFeed),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowingList extends StatelessWidget {
  const _FollowingList({
    required this.following,
    required this.discover,
    required this.searching,
    required this.onToggleFollow,
  });

  final List<Friend> following;
  final List<Friend> discover;
  final bool searching;
  final Future<bool> Function(Friend friend) onToggleFollow;

  @override
  Widget build(BuildContext context) {
    if (following.isEmpty && discover.isEmpty) {
      return Center(
        child: Text(
          searching ? '검색 결과가 없어요' : '아직 팔로잉한 친구가 없어요',
          style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
        ),
      );
    }
    return ListView(
      children: [
        for (final f in following)
          PersonRow(
            name: f.name,
            handle: f.username,
            avatarUrl: f.avatar,
            subtitle: '위시리스트 ${f.wishlistCount}  ·  아이템 ${f.itemCount}',
            trailing: _FollowButton(
              isFollowing: true,
              onPressed: () => _toggle(context, f),
            ),
          ),
        if (discover.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 4),
            child: Text(
              searching ? '검색 결과' : '친구 찾아보기',
              style: DiaryTheme.body(16, weight: FontWeight.w700),
            ),
          ),
          for (final f in discover)
            PersonRow(
              name: f.name,
              handle: f.username,
              avatarUrl: f.avatar,
              subtitle: '위시리스트 ${f.wishlistCount}  ·  아이템 ${f.itemCount}',
              trailing: _FollowButton(
                isFollowing: false,
                onPressed: () => _toggle(context, f),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _toggle(BuildContext context, Friend f) async {
    final willFollow = !f.isFollowing;
    try {
      final changed = await onToggleFollow(f);
      if (!changed || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            willFollow ? '${f.name} 님을 팔로우했어요' : '${f.name} 님 팔로우를 취소했어요',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('팔로우 실패: $e')));
    }
  }
}

class _FollowersList extends StatelessWidget {
  const _FollowersList({required this.followers, required this.onRemove});

  final List<AppUser> followers;
  final Future<void> Function(AppUser user) onRemove;

  @override
  Widget build(BuildContext context) {
    if (followers.isEmpty) {
      return Center(
        child: Text(
          '아직 팔로워가 없어요',
          style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
        ),
      );
    }
    return ListView.builder(
      itemCount: followers.length,
      itemBuilder: (context, i) {
        final u = followers[i];
        return PersonRow(
          name: u.name,
          handle: u.handle,
          avatarUrl: u.avatarUrl,
          trailing: OutlinedButton(
            onPressed: () => _confirmRemove(context, u),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(72, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('삭제'),
          ),
        );
      },
    );
  }

  Future<void> _confirmRemove(BuildContext context, AppUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DiaryColors.paper,
        title: Text(
          '팔로워 삭제',
          style: DiaryTheme.ui(17, weight: FontWeight.w700),
        ),
        content: Text(
          '${user.name} 님을 팔로워에서 삭제할까요?\n삭제하면 이 사람은 더 이상 회원님을 팔로우하지 않아요.',
          style: DiaryTheme.body(13, color: DiaryColors.inkMuted),
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
                color: DiaryColors.pin,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await onRemove(user);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${user.name} 님을 팔로워에서 삭제했어요')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }
}

/// Instagram-style: following = outlined "팔로잉", not following = filled "팔로우".
class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.isFollowing, required this.onPressed});

  final bool isFollowing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Quiet by default: outlined 팔로우, soft gray 팔로잉. No solid black.
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(72, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: isFollowing ? DiaryColors.band : DiaryColors.white,
        foregroundColor: isFollowing ? DiaryColors.inkSoft : DiaryColors.ink,
        side: BorderSide(
          color: isFollowing ? DiaryColors.band : DiaryColors.lineStrong,
        ),
      ),
      child: Text(isFollowing ? '팔로잉' : '팔로우'),
    );
  }
}

class _FriendWishlistsPane extends StatelessWidget {
  const _FriendWishlistsPane({
    required this.wishlists,
    required this.followingEmpty,
  });

  final List<FriendWishlist> wishlists;
  final bool followingEmpty;

  @override
  Widget build(BuildContext context) {
    if (followingEmpty) {
      return Center(
        child: Text(
          '팔로잉한 친구의 wishlist가 여기에 보여요',
          textAlign: TextAlign.center,
          style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
        ),
      );
    }
    if (wishlists.isEmpty) {
      return Center(
        child: Text(
          '공개된 친구 위시리스트가 없어요',
          style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
        ),
      );
    }
    return ListView(
      children: [
        for (final w in wishlists)
          WhiteProductCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.listName,
                  style: DiaryTheme.body(15, weight: FontWeight.w700),
                ),
                Text(
                  w.friendName,
                  style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: w.items
                        .map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => context.push(
                                catalogProductLocation(
                                  p.id,
                                  wishlistId: w.id,
                                ),
                              ),
                              child: Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(DiaryTheme.radius),
                                    child: Image.network(
                                      p.image,
                                      width: 72,
                                      height: 72,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 72,
                                        height: 72,
                                        color: DiaryColors.surfaceSoft,
                                        child: const Icon(Icons.image_outlined),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: 72,
                                    child: Text(
                                      p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: DiaryTheme.body(10),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.push('/friend-wishlist/${w.id}'),
                    child: const Text('위시리스트 전체보기'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SalkamalkaFeedPane extends StatelessWidget {
  const _SalkamalkaFeedPane({required this.entries});

  final List<SalkamalkaFeedEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          '아직 살까말까가 없어요',
          textAlign: TextAlign.center,
          style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
        ),
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final b = e.basket;
        return WhiteProductCard(
          backgroundColor: e.isMine ? DiaryColors.band : DiaryColors.white,
          onTap: () => context.push('/shared/${b.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(
                      e.isMine
                          ? (b.fromAvatar.isNotEmpty
                                ? b.fromAvatar
                                : 'https://api.dicebear.com/7.x/thumbs/png?seed=me')
                          : (b.fromAvatar.isNotEmpty
                                ? b.fromAvatar
                                : 'https://api.dicebear.com/7.x/thumbs/png?seed=${Uri.encodeComponent(b.ownerName)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                e.isMine
                                    ? '내가 보낸 살까말까'
                                    : '${b.ownerName}의 살까말까',
                                style: DiaryTheme.body(
                                  14,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (e.isMine) ...[
                              const SizedBox(width: 6),
                              const MineBadge(),
                            ],
                          ],
                        ),
                        Text(
                          _salkamalkaSubtitle(e),
                          style: DiaryTheme.body(
                            11,
                            color: DiaryColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _confirmHide(context, e),
                    tooltip: '목록에서 숨기기',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: DiaryColors.inkMuted,
                    ),
                  ),
                ],
              ),
              if (b.memo.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  b.memo.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DiaryTheme.body(13),
                ),
              ],
              if (b.items.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final p in b.items.take(8))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              DiaryTheme.radius,
                            ),
                            child: Image.network(
                              p.image,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 56,
                                height: 56,
                                color: DiaryColors.paper,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Hides the entry from this feed only — never deletes the basket.
  Future<void> _confirmHide(BuildContext context, SalkamalkaFeedEntry e) async {
    final store = context.read<AppStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DiaryColors.paper,
        title: Text(
          '목록에서 숨기기',
          style: DiaryTheme.ui(17, weight: FontWeight.w700),
        ),
        content: Text(
          e.isMine
              ? '이 목록에서 숨길까요? 내가 보낸 살까말까에는 남아 있어요'
              : '이 목록에서 숨길까요? 숨기면 다시 볼 수 없어요',
          style: DiaryTheme.body(13, color: DiaryColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '숨기기',
              style: DiaryTheme.ui(
                14,
                weight: FontWeight.w700,
                color: DiaryColors.pin,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.hideFromSalkamalkaFeed(e.basket.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('목록에서 숨겼어요')));
  }

  String _salkamalkaSubtitle(SalkamalkaFeedEntry e) {
    final b = e.basket;
    if (e.isMine) {
      if (b.recipientNames.isNotEmpty) {
        final names = b.recipientNames.take(2).join(', ');
        final extra = b.recipientNames.length > 2
            ? ' 외 ${b.recipientNames.length - 2}명'
            : '';
        return '$names$extra에게 보냄  ·  상품 ${b.items.length}개';
      }
      return '친구에게 보냄  ·  상품 ${b.items.length}개';
    }
    return '${b.ownerName}에게 받음  ·  상품 ${b.items.length}개';
  }
}

/// Full-width text tabs with a black underline on the active one.
class _UnderlineTabs extends StatelessWidget {
  const _UnderlineTabs({
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DiaryColors.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(i),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == selected
                            ? DiaryColors.ink
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: OneLineText(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: DiaryTheme.ui(
                      15,
                      weight: i == selected ? FontWeight.w700 : FontWeight.w500,
                      color: i == selected
                          ? DiaryColors.ink
                          : DiaryColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
