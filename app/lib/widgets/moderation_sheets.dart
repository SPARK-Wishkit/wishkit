import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_store.dart';
import '../models/moderation.dart';
import '../theme/diary_theme.dart';
import 'top_toast.dart';

/// 신고 · 차단 화면 모음 (App Store 심사 1.2: 사용자 생성 콘텐츠).
///
/// 남이 쓴 댓글, 받은 살까말까, 친구 프로필의 "⋯" 메뉴에서 연다.
///   showSafetySheet → (신고하기 → showReportDialog → 차단도 할지 묻기) / (차단하기 → confirmBlockUser)
///
/// 반환값: 차단까지 했으면 true. 받은 살까말까 화면처럼 차단하면 내용이 사라지는 곳은 true 일 때 화면을 닫는다.
Future<bool> showSafetySheet(
  BuildContext context, {
  required ReportTarget target,
}) async {
  final store = context.read<AppStore>();
  if (target.userId.isNotEmpty && target.userId == store.uid) return false;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: DiaryColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DiaryTheme.radius),
      ),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: DiaryColors.grid.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(
                '${target.label} 신고하기',
                style: DiaryTheme.ui(15, weight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
            if (target.userId.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.block),
                title: Text(
                  store.isBlocked(target.userId)
                      ? '이미 차단한 사용자예요'
                      : '${target.userName}님 차단하기',
                  style: DiaryTheme.ui(15, weight: FontWeight.w600),
                ),
                enabled: !store.isBlocked(target.userId),
                onTap: () => Navigator.pop(ctx, 'block'),
              ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return false;
  if (action == 'report') return showReportDialog(context, target: target);
  if (action == 'block') {
    return confirmBlockUser(
      context,
      userId: target.userId,
      userName: target.userName,
    );
  }
  return false;
}

/// 신고 사유를 고르고 보낸다. 보낸 뒤 그 사람을 차단할지도 묻는다. 차단까지 했으면 true.
Future<bool> showReportDialog(
  BuildContext context, {
  required ReportTarget target,
}) async {
  final store = context.read<AppStore>();
  final detailCtrl = TextEditingController();
  ReportReason? reason;
  final sent = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      var sending = false;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
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
                  '신고 사유를 골라 주세요. 운영팀이 24시간 안에 확인하고, '
                  '규칙을 어긴 내용은 지우고 작성자의 이용을 제한해요.',
                  style: DiaryTheme.body(13, color: DiaryColors.inkMuted),
                ),
                const SizedBox(height: 8),
                for (final r in ReportReason.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      reason == r
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: DiaryColors.ink,
                    ),
                    title: Text(r.label, style: DiaryTheme.ui(14)),
                    onTap: sending ? null : () => setState(() => reason = r),
                  ),
                const SizedBox(height: 4),
                TextField(
                  controller: detailCtrl,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 3,
                  enabled: !sending,
                  decoration: const InputDecoration(
                    hintText: '자세한 내용 (선택)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: reason == null || sending
                  ? null
                  : () async {
                      setState(() => sending = true);
                      try {
                        await store.reportContent(
                          target,
                          reason: reason!,
                          detail: detailCtrl.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setState(() => sending = false);
                        showTopToast(ctx, _message(e), error: true);
                      }
                    },
              child: Text(
                '신고하기',
                style: DiaryTheme.ui(14, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    },
  );
  // 대화상자가 닫히는 애니메이션 동안에는 입력칸이 아직 그려지므로, 끝난 뒤 정리한다.
  // (바로 정리하면 "TextEditingController was used after being disposed" 오류)
  Future<void>.delayed(const Duration(milliseconds: 500), detailCtrl.dispose);
  if (sent != true || !context.mounted) return false;
  showTopToast(context, '신고가 접수됐어요. 24시간 안에 확인할게요.');
  if (target.userId.isEmpty || store.isBlocked(target.userId)) return false;
  return confirmBlockUser(
    context,
    userId: target.userId,
    userName: target.userName,
    afterReport: true,
  );
}

/// 차단할지 묻고 차단한다. 차단했으면 true.
Future<bool> confirmBlockUser(
  BuildContext context, {
  required String userId,
  required String userName,
  bool afterReport = false,
}) async {
  final store = context.read<AppStore>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DiaryColors.paper,
      title: Text(
        afterReport ? '$userName님도 차단할까요?' : '$userName님을 차단할까요?',
        style: DiaryTheme.ui(17, weight: FontWeight.w700),
      ),
      content: Text(
        '차단하면 서로 살까말까를 주고받을 수 없고, 이 사람의 살까말까·댓글·알림이 '
        '더 이상 보이지 않아요. 서로의 팔로우도 끊어져요.\n\n'
        '마이페이지 → 차단한 사용자에서 언제든 해제할 수 있어요.',
        style: DiaryTheme.body(13, color: DiaryColors.inkMuted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(afterReport ? '아니요' : '취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            '차단',
            style: DiaryTheme.ui(14, weight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await store.blockUser(userId);
  } catch (e) {
    if (context.mounted) {
      showTopToast(context, _message(e), error: true);
    }
    return false;
  }
  if (context.mounted) {
    showTopToast(context, '$userName님을 차단했어요.');
  }
  return true;
}

String _message(Object e) => e.toString().replaceFirst('Exception: ', '');
