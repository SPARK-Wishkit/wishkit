import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';

const kShareMemoMaxLength = 500;

typedef ShareToFriendsResult = ({
  Set<String> friendIds,
  String memo,
  bool allowVoting,
  bool allowMultipleVotes,
});

/// Friend picker plus the memo that goes out with a 살까말까 share.
Future<ShareToFriendsResult?> showShareToFriendsSheet({
  required BuildContext context,
  required AppStore store,
  String title = '보낼 친구 선택',
  String confirmLabel = '보내기',
  String initialMemo = '',
  // 투표 설정은 처음 보낼 때만 묻는다. 다시 보내기는 처음 설정 그대로.
  bool askVoteSettings = true,
}) {
  final following = store.friends.where((f) => f.isFollowing).toList();
  if (following.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('팔로잉한 친구가 없어요. 먼저 친구를 추가해 주세요.')),
    );
    return Future.value(null);
  }

  return showModalBottomSheet<ShareToFriendsResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DiaryColors.paper,
    builder: (_) => _ShareToFriendsSheet(
      following: following,
      title: title,
      confirmLabel: confirmLabel,
      initialMemo: initialMemo,
      askVoteSettings: askVoteSettings,
    ),
  );
}

/// 메모 입력칸의 컨트롤러는 시트가 완전히 닫힐 때(이 위젯의 dispose) 정리한다.
/// 예전에는 시트가 닫히는 애니메이션 도중에 먼저 정리해서
/// "TextEditingController was used after being disposed" 오류가 났다.
class _ShareToFriendsSheet extends StatefulWidget {
  const _ShareToFriendsSheet({
    required this.following,
    required this.title,
    required this.confirmLabel,
    required this.initialMemo,
    required this.askVoteSettings,
  });

  final List<Friend> following;
  final String title;
  final String confirmLabel;
  final String initialMemo;
  final bool askVoteSettings;

  @override
  State<_ShareToFriendsSheet> createState() => _ShareToFriendsSheetState();
}

class _ShareToFriendsSheetState extends State<_ShareToFriendsSheet> {
  late final TextEditingController _memo =
      TextEditingController(text: widget.initialMemo);
  final _selected = <String>{};
  var _confirming = false;
  var _allowVoting = true;
  var _allowMultipleVotes = true;

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_selected.isEmpty || _confirming) return;
    setState(() => _confirming = true);
    Navigator.pop<ShareToFriendsResult>(context, (
      friendIds: {..._selected},
      memo: _memo.text.trim(),
      allowVoting: _allowVoting,
      allowMultipleVotes: _allowVoting && _allowMultipleVotes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 키보드가 올라오면 시트가 키보드 위 남은 공간 안에 들어가게 줄인다.
    // 메모·친구 목록은 스크롤되고, 투표 설정과 "보내기" 버튼은 항상 아래 같은 자리에 있다.
    final maxHeight = media.size.height * 0.72;
    final available =
        media.size.height - media.viewInsets.bottom - media.padding.top - 24;
    final height = available < maxHeight ? available : maxHeight;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: media.viewInsets.bottom + 16,
        ),
        child: SizedBox(
          // 버튼·투표 설정(아래 고정)과 메모칸이 들어갈 만큼은 최소로 둔다.
          height: height < 320 ? 320 : height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    Text(
                      widget.title,
                      style: DiaryTheme.body(16, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '고민되는 이유를 짧게 적어 같이 보내요',
                      style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _memo,
                      maxLines: 3,
                      maxLength: kShareMemoMaxLength,
                      decoration: InputDecoration(
                        hintText: '예: 이걸 사 말아',
                        filled: true,
                        fillColor: DiaryColors.band,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(DiaryTheme.radius),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    for (final f in widget.following)
                      CheckboxListTile(
                        value: _selected.contains(f.id),
                        onChanged: _confirming
                            ? null
                            : (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(f.id);
                                  } else {
                                    _selected.remove(f.id);
                                  }
                                }),
                        secondary: CircleAvatar(
                          backgroundImage: NetworkImage(f.avatar),
                        ),
                        title: Text(f.name),
                        subtitle: Text(f.username),
                      ),
                  ],
                ),
              ),
              // 투표 설정 두 줄은 목록 밖, 버튼 바로 위에 항상 같은 자리에 둔다.
              // "복수 선택 가능"은 숨기지 않고, 투표 보내기를 켰을 때만 누를 수 있다.
              if (widget.askVoteSettings) ...[
                const Divider(height: 1),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _allowVoting,
                  onChanged: _confirming
                      ? null
                      : (value) =>
                          setState(() => _allowVoting = value ?? false),
                  title: Text(
                    '투표 보내기',
                    style: DiaryTheme.body(14, weight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '친구들이 상품을 골라 투표할 수 있어요',
                    style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    // 투표를 끄면 체크를 비우고 흐리게 보여 준다.
                    // 다시 켜면 전에 고른 값이 그대로 돌아온다.
                    value: _allowVoting && _allowMultipleVotes,
                    onChanged: _confirming || !_allowVoting
                        ? null
                        : (value) => setState(
                              () => _allowMultipleVotes = value ?? false,
                            ),
                    title: Text(
                      '복수 선택 가능',
                      style: DiaryTheme.body(
                        14,
                        weight: FontWeight.w600,
                        color: _allowVoting
                            ? DiaryColors.ink
                            : DiaryColors.inkSoft,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _selected.isEmpty || _confirming ? null : _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: DiaryColors.ink,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text('${widget.confirmLabel} (${_selected.length})'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
