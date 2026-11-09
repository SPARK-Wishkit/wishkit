import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../theme/diary_theme.dart';

const kShareMemoMaxLength = 500;

/// Friend picker plus the memo that goes out with a 살까말까 share.
///
/// [askVoteMode] shows the 투표 방식 choice (여러 개 / 하나만). It is only asked
/// on the first send — a re-send keeps the mode the basket started with.
Future<({Set<String> friendIds, String memo, bool voteMultiple})?>
    showShareToFriendsSheet({
  required BuildContext context,
  required AppStore store,
  String title = '보낼 친구 선택',
  String confirmLabel = '보내기',
  String initialMemo = '',
  bool askVoteMode = true,
}) async {
  final following = store.friends.where((f) => f.isFollowing).toList();
  if (following.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('팔로잉한 친구가 없어요. 먼저 친구를 추가해 주세요.')),
    );
    return null;
  }

  final selected = <String>{};
  var voteMultiple = true;
  final memoCtrl = TextEditingController(text: initialMemo);
  var confirming = false;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DiaryColors.paper,
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: DiaryTheme.body(16, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '고민되는 이유를 짧게 적어 같이 보내요',
                      style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: memoCtrl,
                      maxLines: 3,
                      maxLength: kShareMemoMaxLength,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        hintText: '예: 이걸 사 말아',
                        filled: true,
                        fillColor: DiaryColors.band,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(DiaryTheme.radius),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (askVoteMode) ...[
                      Text(
                        '친구들이 투표할 때',
                        style: DiaryTheme.body(13, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _VoteModeOption(
                              label: '여러 개 고르기',
                              selected: voteMultiple,
                              onTap: () =>
                                  setModalState(() => voteMultiple = true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _VoteModeOption(
                              label: '하나만 고르기',
                              selected: !voteMultiple,
                              onTap: () =>
                                  setModalState(() => voteMultiple = false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: following.length,
                        itemBuilder: (context, i) {
                          final f = following[i];
                          final checked = selected.contains(f.id);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) {
                              setModalState(() {
                                if (v == true) {
                                  selected.add(f.id);
                                } else {
                                  selected.remove(f.id);
                                }
                              });
                            },
                            secondary: CircleAvatar(
                              backgroundImage: NetworkImage(f.avatar),
                            ),
                            title: Text(f.name),
                            subtitle: Text(f.username),
                          );
                        },
                      ),
                    ),
                    FilledButton(
                      onPressed: selected.isEmpty || confirming
                          ? null
                          : () {
                              setModalState(() => confirming = true);
                              Navigator.pop(sheetCtx, true);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: DiaryColors.ink,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text('$confirmLabel (${selected.length})'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
  final memo = memoCtrl.text.trim();
  memoCtrl.dispose();
  if (confirmed != true || selected.isEmpty) return null;
  return (friendIds: selected, memo: memo, voteMultiple: voteMultiple);
}

class _VoteModeOption extends StatelessWidget {
  const _VoteModeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? DiaryColors.ink : DiaryColors.paper,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? DiaryColors.ink : DiaryColors.lineStrong,
            ),
          ),
          child: Text(
            label,
            style: DiaryTheme.ui(
              14,
              weight: FontWeight.w700,
              color: selected ? DiaryColors.white : DiaryColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
