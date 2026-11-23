/// 신고 · 차단에 쓰는 값 (App Store 심사 1.2: 사용자 생성 콘텐츠).
/// 서버 규칙: amplify/functions/social-actions/logic.ts (REPORT_REASONS, REPORT_TARGETS).
library;

/// 신고 사유. [code] 는 서버와 약속된 값이다.
enum ReportReason {
  spam('spam', '스팸 · 광고'),
  abuse('abuse', '욕설 · 괴롭힘'),
  sexual('sexual', '음란 · 선정적인 내용'),
  hate('hate', '혐오 · 차별 발언'),
  other('other', '기타');

  const ReportReason(this.code, this.label);

  final String code;
  final String label;
}

/// 무엇을 신고하는지.
sealed class ReportTarget {
  const ReportTarget({required this.userId, required this.userName});

  /// 신고 대상 콘텐츠를 만든 사람(차단할 때 쓴다).
  final String userId;
  final String userName;

  String get typeCode;

  /// 신고 화면 제목에 쓰는 이름.
  String get label;
}

/// 살까말까 댓글.
class CommentReportTarget extends ReportTarget {
  const CommentReportTarget({
    required this.threadId,
    required this.commentId,
    required super.userId,
    required super.userName,
  });

  final String threadId;
  final String commentId;

  @override
  String get typeCode => 'comment';

  @override
  String get label => '댓글';
}

/// 내가 받은 살까말까.
class BasketReportTarget extends ReportTarget {
  const BasketReportTarget({
    required this.basketId,
    required super.userId,
    required super.userName,
  });

  final String basketId;

  @override
  String get typeCode => 'basket';

  @override
  String get label => '살까말까';
}

/// 사용자(프로필).
class UserReportTarget extends ReportTarget {
  const UserReportTarget({required super.userId, required super.userName});

  @override
  String get typeCode => 'user';

  @override
  String get label => '사용자';
}
