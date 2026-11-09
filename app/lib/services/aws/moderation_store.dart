import 'gql_documents.dart';
import 'gql_runner.dart';

/// 신고할 수 있는 대상.
enum ReportTargetType { comment, basket, user }

/// 신고 사유. 서버(amplify/functions/social-actions/logic.ts REPORT_REASONS)와 같은 값.
enum ReportReason {
  abuse('abuse', '욕설·비방'),
  harassment('harassment', '괴롭힘·따돌림'),
  sexual('sexual', '음란·선정적인 내용'),
  spam('spam', '스팸·광고'),
  other('other', '기타');

  const ReportReason(this.code, this.label);
  final String code;
  final String label;
}

/// 신고 · 차단 · 탈퇴 시 공유 콘텐츠 정리 (Google Play UGC·계정 삭제 정책).
///
/// - 차단(Block)은 내가 직접 만들고 지운다. 서버 함수가 차단 관계를 보고
///   살까말까·댓글·팔로우 알림·공개 위시리스트를 막는다.
/// - 신고(Report)는 서버 함수만 만든다. 신고 당시 내용을 서버가 함께 저장한다.
class AwsModerationStore {
  AwsModerationStore({GqlRunner? runner})
      : _gql = runner ?? const AmplifyGqlRunner();

  final GqlRunner _gql;

  static const _pageSize = 200;
  static const _maxPages = 20;

  /// 내가 차단한 사람들의 uid.
  Future<Set<String>> blockedIds(String uid) async {
    final out = <String>{};
    String? next;
    var pages = 0;
    do {
      final data = await _gql.query(Gql.listBlocks, variables: {
        'ownerId': uid,
        'limit': _pageSize,
        'nextToken': next,
      });
      final conn = data['listBlocks'];
      if (conn is! Map) break;
      for (final item in (conn['items'] as List? ?? const [])) {
        if (item is Map && item['blockedId'] is String) {
          out.add(item['blockedId'] as String);
        }
      }
      next = conn['nextToken'] as String?;
      pages++;
    } while (next != null && pages < _maxPages);
    return out;
  }

  /// 차단 / 차단 해제. 이미 그 상태면 조용히 넘어간다.
  Future<void> setBlocked({
    required String myUid,
    required String targetUid,
    required bool blocked,
  }) async {
    if (myUid == targetUid || targetUid.isEmpty) return;
    try {
      await _gql.mutate(
        blocked ? Gql.createBlock : Gql.deleteBlock,
        variables: {
          'input': {'blockerId': myUid, 'blockedId': targetUid},
        },
      );
    } on AwsDataException catch (e) {
      if (!e.isConditionalCheckFailed) rethrow;
    }
  }

  /// 신고. [targetId] 는 댓글이면 commentId, 살까말까면 내 받은함의 basketId.
  Future<void> report({
    required ReportTargetType type,
    required String targetUserId,
    required ReportReason reason,
    String? targetId,
    String? threadId,
    String? detail,
  }) async {
    try {
      await _gql.mutate(Gql.reportContent, variables: {
        'targetType': type.name,
        'targetUserId': targetUserId,
        'targetId': targetId,
        'threadId': threadId,
        'reason': reason.code,
        'detail': (detail ?? '').trim().isEmpty ? null : detail!.trim(),
      });
    } on AwsDataException catch (e) {
      final message = switch (e.serverCode) {
        'NOT_FOUND' => '신고할 내용을 찾지 못했어요. 이미 삭제됐을 수 있어요.',
        'NOT_PARTICIPANT' => '이 살까말까에 참여한 사람만 신고할 수 있어요.',
        'TOO_LONG' => '신고 내용은 500자까지 쓸 수 있어요.',
        'INVALID_INPUT' => '신고 내용을 다시 확인해 주세요.',
        _ => null,
      };
      if (message != null) throw Exception(message);
      rethrow;
    }
  }

  /// 탈퇴 직전: 다른 사람에게 보이는 내 콘텐츠(남의 댓글방에 쓴 댓글, 친구 받은함의
  /// 내가 보낸 살까말까, 내가 만든 댓글방)와 차단 기록을 서버가 지운다.
  Future<void> deleteMySharedContent() async {
    await _gql.mutate(Gql.deleteMySocialData);
  }
}
