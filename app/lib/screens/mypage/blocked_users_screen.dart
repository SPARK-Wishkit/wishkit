import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';

/// 마이페이지 → 차단한 사용자. 차단 해제만 할 수 있다 (App Store 심사 1.2).
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<AppUser>? _users;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _error = null);
    try {
      final users = await context.read<AppStore>().loadBlockedUsers();
      if (!mounted) return;
      setState(() => _users = users);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '차단 목록을 불러오지 못했어요.');
    }
  }

  Future<void> _unblock(AppUser user) async {
    if (!_busy.add(user.uid)) return;
    setState(() {});
    try {
      await context.read<AppStore>().unblockUser(user.uid);
      if (!mounted) return;
      setState(() => _users = _users?.where((u) => u.uid != user.uid).toList());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.name}님 차단을 해제했어요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      _busy.remove(user.uid);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
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
          '차단한 사용자',
          style: DiaryTheme.ui(17, weight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
                ),
              )
            : users == null
                ? const Center(child: CircularProgressIndicator())
                : users.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '차단한 사용자가 없어요.\n친구 화면이나 댓글의 ⋯ 메뉴에서 차단할 수 있어요.',
                            textAlign: TextAlign.center,
                            style: DiaryTheme.body(
                              14,
                              color: DiaryColors.inkMuted,
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '차단한 사람과는 서로 살까말까를 주고받을 수 없고, '
                              '그 사람의 살까말까·댓글·알림이 보이지 않아요.',
                              style: DiaryTheme.body(
                                13,
                                color: DiaryColors.inkMuted,
                              ),
                            ),
                          ),
                          for (final u in users)
                            PersonRow(
                              name: u.name,
                              handle: u.handle,
                              avatarUrl: u.avatarUrl,
                              trailing: OutlinedButton(
                                onPressed: _busy.contains(u.uid)
                                    ? null
                                    : () => _unblock(u),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(72, 34),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                                child: const Text('해제'),
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }
}
