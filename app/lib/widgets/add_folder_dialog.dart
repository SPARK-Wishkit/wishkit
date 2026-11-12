import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';

/// "폴더 추가" 대화상자 — 마이페이지와 공유 담기(파싱) 화면이 같이 쓴다.
/// 만들면 새 폴더를, 취소하거나 실패하면 null을 돌려준다.
Future<WishlistTab?> showAddFolderDialog(
  BuildContext context,
  AppStore store,
) {
  return showDialog<WishlistTab>(
    context: context,
    builder: (_) => _AddFolderDialog(store: store),
  );
}

/// 입력창 controller 를 대화상자 안에서 만들고 정리한다.
/// (밖에서 dispose 하면 닫히는 애니메이션 중에 이미 정리된 controller 를 쓰게 된다)
class _AddFolderDialog extends StatefulWidget {
  const _AddFolderDialog({required this.store});

  final AppStore store;

  @override
  State<_AddFolderDialog> createState() => _AddFolderDialogState();
}

class _AddFolderDialogState extends State<_AddFolderDialog> {
  late final TextEditingController _ctrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    final store = widget.store;
    setState(() => _submitting = true);
    final before = store.tabs.map((t) => t.id).toSet();
    final ok = await store.addTab(name);
    if (!mounted) return;
    if (ok) {
      final created =
          store.tabs.where((t) => !before.contains(t.id)).firstOrNull;
      Navigator.pop(context, created);
      return;
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('폴더 추가'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: '폴더 이름'),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? '추가하는 중...' : '추가'),
        ),
      ],
    );
  }
}
