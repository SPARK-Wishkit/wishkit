import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 이용약관 · 개인정보처리방침 · 계정 삭제 안내 웹페이지 주소.
///
/// 페이지 원본은 레포의 `legal-site/legal/*.html`. 기본 주소는 GitHub Pages
/// (.github/workflows/legal-pages.yml). 다른 곳에 올렸다면 빌드할 때 바꾼다:
///
///     flutter build appbundle --dart-define=LEGAL_BASE_URL=https://example.com/legal
///
/// 같은 주소를 Play Console(개인정보처리방침, 데이터 보안 → 계정 삭제 URL)에도 넣는다.
abstract final class LegalLinks {
  /// 약관 내용이 바뀌면 올린다. 가입 시 동의한 버전으로 기록된다.
  static const termsVersion = '2026-11-09';

  static const _base = String.fromEnvironment(
    'LEGAL_BASE_URL',
    defaultValue: 'https://spark-wishkit.github.io/SPARK_Wishkit/legal',
  );

  static Uri get terms => Uri.parse('$_base/terms.html');
  static Uri get privacy => Uri.parse('$_base/privacy.html');
  static Uri get accountDeletion => Uri.parse('$_base/account-deletion.html');

  /// 외부 브라우저로 연다. 실패하면 스낵바로 알린다.
  static Future<void> open(BuildContext context, Uri url) async {
    var ok = false;
    try {
      ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('페이지를 열지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }
}
