import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../models/models.dart';

/// "폴더 추가" 대화상자 — 마이페이지와 공유 담기(파싱) 화면이 같이 쓴다.
/// 만들면 새 폴더를, 취소하거나 실패하면 null을 돌려준다.
Future<WishlistTab?> showAddFolderDialog(
  BuildContext context,
  AppStore store,
) async {
  final ctrl = TextEditingController();
  var submitting = false;
  WishlistTab? created;
  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setLocal) => AlertDialog(
        title: const Text('폴더 추가'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '폴더 이름'),
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: submitting
                ? null
                : () async {
                    final name = ctrl.text.trim();
                    if (name.isEmpty) return;
                    setLocal(() => submitting = true);
                    final before = store.tabs.map((t) => t.id).toSet();
                    final ok = await store.addTab(name);
                    if (!dialogCtx.mounted) return;
                    if (ok) {
                      created = store.tabs
                          .where((t) => !before.contains(t.id))
                          .firstOrNull;
                      Navigator.pop(dialogCtx);
                      return;
                    }
                    setLocal(() => submitting = false);
                  },
            child: Text(submitting ? '추가하는 중...' : '추가'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return created;
}
