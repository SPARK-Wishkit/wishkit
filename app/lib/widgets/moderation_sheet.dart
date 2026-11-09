import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../services/aws/moderation_store.dart';
import '../theme/diary_theme.dart';

/// 무엇을 신고하는지. [targetId] 는 댓글이면 commentId, 살까말까면 받은 basketId.
class ReportTarget {
  const ReportTarget.comment({
    required String commentId,
    required String this.threadId,
  })  : type = ReportTargetType.comment,
        targetId = commentId,
        label = '댓글';

  const ReportTarget.basket({required String basketId})
      : type = ReportTargetType.basket,
        targetId = basketId,
        threadId = null,
        label = '살까말까';

  const ReportTarget.user()
      : type = ReportTargetType.user,
        targetId = null,
        threadId = null,
        label = '사용자';

  final ReportTargetType type;
  final String? targetId;
  final String? threadId;
  final String label;
}

/// 다른 사람의 댓글·살까말까·프로필에서 여는 "신고 / 차단" 메뉴 (Google Play UGC 정책).
///
/// 차단하면 true 를 돌려준다 (화면을 닫을지 정할 때 쓴다).
Future<bool> showModerationSheet(
  BuildContext context, {
  required AppStore store,
  required String targetUid,
  required String targetName,
  required ReportTarget target,
}) async {
  if (targetUid.isEmpty || targetUid == store.uid) return false;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: DiaryColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DiaryTheme.radius)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(
                '${target.label} 신고하기',
                style: DiaryTheme.ui(15, weight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
            ListTile(
              leading: Icon(Icons.block, color: DiaryColors.pin),
              title: Text(
                store.isBlocked(targetUid)
                    ? '$targetName 님 차단 해제'
                    : '$targetName 님 차단하기',
                style: DiaryTheme.ui(
                  15,
                  weight: FontWeight.w600,
                  color: DiaryColors.pin,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return false;
  if (action == 'report') {
    await _report(context, store, targetUid, target);
    return false;
  }
  if (action == 'block') {
    if (store.isBlocked(targetUid)) {
      await _run(context, () => store.unblockUser(targetUid), '차단을 해제했어요');
      return false;
    }
    return _confirmBlock(context, store, targetUid, targetName);
  }
  return false;
}

/// 차단 확인 창 → 차단. 차단했으면 true.
Future<bool> _confirmBlock(
  BuildContext context,
  AppStore store,
  String targetUid,
  String targetName,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DiaryColors.paper,
      title: Text(
        '$targetName 님을 차단할까요?',
        style: DiaryTheme.ui(17, weight: FontWeight.w700),
      ),
      content: Text(
        '서로 팔로우가 끊기고, 상대는 나에게 살까말까를 보내거나 내 살까말까에 '
        '댓글을 달 수 없어요. 상대의 댓글·살까말까·알림도 보이지 않아요. '
        '차단 사실은 상대에게 알리지 않아요.\n\n'
        '마이페이지 > 차단한 사용자에서 언제든 해제할 수 있어요.',
        style: DiaryTheme.body(13).copyWith(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            '차단',
            style: DiaryTheme.ui(14, weight: FontWeight.w700, color: DiaryColors.pin),
          ),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  return _run(context, () => store.blockUser(targetUid), '차단했어요');
}

Future<void> _report(
  BuildContext context,
  AppStore store,
  String targetUid,
  ReportTarget target,
) async {
  final detailCtrl = TextEditingController();
  ReportReason? reason;
  final submit = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: DiaryColors.paper,
        title: Text(
          '${target.label} 신고',
          style: DiaryTheme.ui(17, weight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '신고 사유를 골라 주세요. 운영팀이 확인해 약관 위반이면 '
                '콘텐츠를 지우거나 계정 이용을 정지해요.',
                style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
              ),
              const SizedBox(height: 8),
              RadioGroup<ReportReason>(
                groupValue: reason,
                onChanged: (v) => setLocal(() => reason = v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final r in ReportReason.values)
                      RadioListTile<ReportReason>(
                        value: r,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(r.label, style: DiaryTheme.body(14)),
                      ),
                  ],
                ),
              ),
              TextField(
                controller: detailCtrl,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: '자세한 내용 (선택)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: reason == null ? null : () => Navigator.pop(ctx, true),
            child: Text(
              '신고',
              style: DiaryTheme.ui(14, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
  final picked = reason;
  final detail = detailCtrl.text;
  // 닫히는 애니메이션 중에도 입력칸이 컨트롤러를 쓰므로 여기서 dispose 하지 않는다.
  if (submit != true || picked == null || !context.mounted) return;
  await _run(
    context,
    () => store.reportContent(
      type: target.type,
      targetUserId: targetUid,
      reason: picked,
      targetId: target.targetId,
      threadId: target.threadId,
      detail: detail,
    ),
    '신고가 접수됐어요. 운영팀이 확인할게요.',
  );
}

/// [job] 을 실행하고 결과를 스낵바로 알린다. 성공하면 true.
Future<bool> _run(
  BuildContext context,
  Future<void> Function() job,
  String doneMessage,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await job();
    messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
    return true;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
    return false;
  }
}
