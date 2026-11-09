import 'dart:convert';
import 'dart:typed_data';

import '../../models/models.dart';
import 'gql_documents.dart';
import 'gql_runner.dart';

/// 태그 사진으로 상품 페이지 찾기 — 서버 함수(parsing-proxy → 엔진 POST /identify-tag).
///
/// 로그인 사용자만 부를 수 있다. 사진은 base64로 보내므로, 부르기 전에 작게 줄여서 보낸다
/// (화면에서 ImagePicker maxWidth 1280 · JPEG 75%).
class AwsProductTagStore {
  AwsProductTagStore({GqlRunner? runner})
    : _gql = runner ?? const AmplifyGqlRunner();

  final GqlRunner _gql;

  /// 서버가 받는 최대 크기(엔진 IDENTIFY_MAX_IMAGE_BYTES와 같음).
  static const maxImageBytes = 4 * 1024 * 1024;

  Future<TagIdentifyResult> identify(Uint8List image, String mimeType) async {
    if (image.isEmpty) {
      throw ArgumentError('사진이 비어 있어요');
    }
    if (image.length > maxImageBytes) {
      throw ArgumentError('사진이 너무 커요');
    }
    final data = await _gql.query(
      Gql.identifyProductTag,
      variables: {'imageBase64': base64Encode(image), 'mimeType': mimeType},
    );
    final raw = data['identifyProductTag'];
    if (raw is! Map) {
      return const TagIdentifyResult(status: TagIdentifyStatus.notFound);
    }
    return TagIdentifyResult.fromJson(raw.cast<String, dynamic>());
  }

  /// 태그 찾기 결과에 대한 반응을 익명으로 남긴다. 누가 보냈는지·사진·가격은 보내지 않고,
  /// 엔진이 무엇을 찾았는지와 사용자의 답만 보낸다(빈 값은 아예 안 보냄).
  Future<void> sendFeedback(TagFeedbackAnswer answer, TagIdentifyResult r) async {
    final input = <String, dynamic>{
      'answer': answer.wire,
      'engineStatus': switch (r.status) {
        TagIdentifyStatus.found => 'found',
        TagIdentifyStatus.needsConfirm => 'needs_confirm',
        TagIdentifyStatus.notFound => 'not_found',
        TagIdentifyStatus.notATag => 'not_a_tag',
      },
      'brand': r.brand,
      'productCode': r.productCode,
      'matchUrl': r.matchUrl,
      'matchHost': r.matchHost,
      'matchVia': r.matchVia,
      'verifiedBy': r.verifiedBy,
    }..removeWhere((_, v) => v == null || (v is String && v.trim().isEmpty));
    await _gql.mutate(Gql.createTagFeedback, variables: {'input': input});
  }
}
