import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/top_toast.dart';

/// 고객 문의 · 약관 · 개인정보처리방침 (App Store 심사 1.5, 5.1.1).
///
/// 웹 페이지(app/site/*.html)는 백엔드가 CloudFront 로 올리고(amplify/backend.ts 의 SiteCdn),
/// 그 주소가 amplify_outputs 의 custom.siteBaseUrl 로 들어온다(amplify_setup.dart 가 [siteBaseUrl] 에 넣음).
/// App Store Connect 의 "개인정보 처리방침 URL" · "지원 URL" 에도 같은 주소를 넣는다 (docs/RELEASE_IOS.md).
abstract final class SupportInfo {
  /// 고객 문의 · 신고 메일. 운영팀이 신고 알림을 받는 메일과 같다(amplify/backend.ts MODERATION_EMAIL).
  static const email = 'hi.wishkit@gmail.com';

  /// 약관을 바꾸면 날짜를 올린다(웹 페이지 위쪽 "시행일"과 같게).
  static const termsVersion = '2026-11-12';

  /// 예: https://dxxxxxxxx.cloudfront.net — 앱 시작 때 채워진다. 없으면(옛 설정 파일) 빈 문자열.
  static String siteBaseUrl = '';

  static const privacyPage = 'privacy.html';
  static const termsPage = 'terms.html';
  static const supportPage = 'support.html';

  static Uri? pageUri(String page) =>
      siteBaseUrl.isEmpty ? null : Uri.parse('$siteBaseUrl/$page');
}

/// 약관 · 개인정보처리방침 · 고객센터 웹 페이지를 앱 안 브라우저로 연다.
Future<void> openSupportPage(BuildContext context, String page) async {
  final uri = SupportInfo.pageUri(page);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) {
    showTopToast(
      context,
      '페이지를 열 수 없어요. 문의는 ${SupportInfo.email} 로 보내 주세요.',
      error: true,
    );
  }
}

/// 메일 앱으로 문의 메일을 쓴다. 메일 앱이 없으면 주소를 복사해 준다.
Future<void> openSupportEmail(
  BuildContext context, {
  String subject = '[wishkit 문의]',
  String body = '',
}) async {
  final uri = Uri(
    scheme: 'mailto',
    path: SupportInfo.email,
    query: _encodeQuery({'subject': subject, if (body.isNotEmpty) 'body': body}),
  );
  var ok = false;
  try {
    ok = await launchUrl(uri);
  } catch (_) {
    ok = false;
  }
  if (ok || !context.mounted) return;
  await Clipboard.setData(const ClipboardData(text: SupportInfo.email));
  if (!context.mounted) return;
  showTopToast(
    context,
    '메일 앱을 열 수 없어서 주소(${SupportInfo.email})를 복사했어요.',
    icon: Icons.mail_outline,
    duration: const Duration(seconds: 4),
  );
}

// mailto 는 공백을 '+' 가 아니라 %20 으로 써야 메일 앱이 제목을 제대로 읽는다.
String _encodeQuery(Map<String, String> params) => params.entries
    .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
    .join('&');
