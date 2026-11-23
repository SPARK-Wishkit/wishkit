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

  static String get nativeUnitId =>
      Platform.isIOS ? _nativeIos : _nativeAndroid;

  // ── 태그 찾기 중 큰 배너(화면 높이 최대 70%, 동영상 포함) ─────────────
  //
  // 화면을 덮는 전면 광고 대신, 태그 찾기를 기다리는 동안 버튼 아래에 큰 배너(인라인 적응형,
  // 최대 화면 높이의 70%)를 보여 준다. 이미지·동영상 광고가 모두 나온다. 아래는 구글 공식 **테스트** 배너 단위 ID.
  // 출시 빌드에서는 AdMob에서 "배너" 광고 단위를 만들고 실제 ID를 넣는다:
  //   --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-XXXX/YYYY
  //   --dart-define=ADMOB_BANNER_IOS=ca-app-pub-XXXX/ZZZZ
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';

  static const _bannerAndroid = String.fromEnvironment(
    'ADMOB_BANNER_ANDROID',
    defaultValue: _testBannerAndroid,
  );
  static const _bannerIos = String.fromEnvironment(
    'ADMOB_BANNER_IOS',
    defaultValue: _testBannerIos,
  );

  static String get bannerUnitId => Platform.isIOS ? _bannerIos : _bannerAndroid;
}
