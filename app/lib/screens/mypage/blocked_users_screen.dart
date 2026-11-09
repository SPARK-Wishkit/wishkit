import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';

/// 마이페이지 > 차단한 사용자. 차단 해제만 할 수 있다.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<AppUser>? _users;
  String? _error;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final users = await context.read<AppStore>().loadBlockedUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '차단 목록을 불러오지 못했어요.');
    }
  }

  Future<void> _unblock(AppUser user) async {
    if (!_busy.add(user.uid)) return;
    setState(() {});
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppStore>().unblockUser(user.uid);
      if (!mounted) return;
      setState(() => _users = _users?.where((u) => u.uid != user.uid).toList());
      messenger.showSnackBar(
        SnackBar(content: Text('${user.name} 님 차단을 해제했어요')),
      );
    } catch (e) {
      messenger.showSnackBar(
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
      body: _error != null
          ? Center(child: Text(_error!, style: DiaryTheme.body(14)))
          : users == null
              ? const Center(child: CircularProgressIndicator())
              : users.isEmpty
                  ? Center(
                      child: Text(
                        '차단한 사용자가 없어요',
                        style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final u = users[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: u.avatarUrl.isNotEmpty
                                ? NetworkImage(u.avatarUrl)
                                : null,
                          ),
                          title: Text(u.name, style: DiaryTheme.body(14)),
                          subtitle: Text(
                            u.handle,
                            style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                          ),
                          trailing: TextButton(
                            onPressed:
                                _busy.contains(u.uid) ? null : () => _unblock(u),
                            child: const Text('차단 해제'),
                          ),
                        );
                      },
                    ),
    );
  }
}
