import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// 광고 설정.
///
/// 광고 단위 ID는 빌드할 때 넣는다. 안 넣으면 **구글 공식 테스트 광고**가 나온다.
/// (개발 중에 실제 광고를 직접 누르면 AdMob 계정이 정지될 수 있으니, 출시 빌드에서만 실제 ID 사용)
///
///   flutter build appbundle \
///     --dart-define=ADMOB_NATIVE_ANDROID=ca-app-pub-XXXX/YYYY
///   flutter build ipa \
///     --dart-define=ADMOB_NATIVE_IOS=ca-app-pub-XXXX/ZZZZ
///
/// ⚠️ 앱 ID(광고 단위 ID와 다름)는 AndroidManifest.xml / Info.plist 에 있다 — 출시 전에 둘 다
///    실제 AdMob 앱 ID로 바꿔야 한다. 지금 들어 있는 값은 구글 테스트 앱 ID.
abstract final class AdsConfig {
  /// 상품 카드 몇 개마다 광고 1개를 넣을지.
  static const every = 6;

  // 구글 공식 테스트용 네이티브 광고 단위 ID (google_mobile_ads 예제와 같은 값).
  static const _testNativeAndroid = 'ca-app-pub-3940256099942544/2247696110';
  static const _testNativeIos = 'ca-app-pub-3940256099942544/3986624511';

  static const _nativeAndroid = String.fromEnvironment(
    'ADMOB_NATIVE_ANDROID',
    defaultValue: _testNativeAndroid,
  );
  static const _nativeIos = String.fromEnvironment(
    'ADMOB_NATIVE_IOS',
    defaultValue: _testNativeIos,
  );

  /// 광고 SDK가 동작하는 플랫폼인지. 웹·데스크톱·`flutter test`(호스트 OS)에서는 false라서
  /// 광고 칸 자체를 만들지 않는다(빈 칸이 생기지 않게).
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 목록에 실제로 적용할 간격. 광고를 못 쓰는 곳에서는 0(광고 없음).
  static int get feedEvery => supported ? every : 0;

  /// 테스트용: `--dart-define=ADS_TAG_ALWAYS=true`로 실행하면 태그 찾기 광고를 확률·간격 없이
  /// 매번 띄운다(광고가 준비돼 있을 때). 출시 빌드에는 절대 넣지 않는다.
  static const forceTagAds = bool.fromEnvironment('ADS_TAG_ALWAYS');

  static String get nativeUnitId =>
      Platform.isIOS ? _nativeIos : _nativeAndroid;

  // ── 태그 찾기 전면 광고(동영상 포함) ─────────────────────────────
  //
  // 구글 공식 테스트용 "동영상 전면 광고" 단위 ID. 출시 빌드에서는 실제 ID를 넣는다:
  //   --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-XXXX/YYYY
  //   --dart-define=ADMOB_INTERSTITIAL_IOS=ca-app-pub-XXXX/ZZZZ
  // AdMob에서 "전면 광고" 단위를 만들고 광고 유형에 동영상을 켜 두면 동영상이 나온다.
  static const _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/8691691433';
  static const _testInterstitialIos = 'ca-app-pub-3940256099942544/5135589807';

  static const _interstitialAndroid = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ANDROID',
    defaultValue: _testInterstitialAndroid,
  );
  static const _interstitialIos = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_IOS',
    defaultValue: _testInterstitialIos,
  );

  static String get interstitialUnitId =>
      Platform.isIOS ? _interstitialIos : _interstitialAndroid;

  /// 태그 찾기를 시작할 때 광고를 띄울 확률(항상 띄우지 않는다).
  static const tagAdChance = 0.67; // 약 3번에 2번

  /// 광고를 한 번 띄운 뒤 다음 광고까지 최소 간격(연달아 뜨지 않게).
  static const tagAdCooldown = Duration(minutes: 3);
}
