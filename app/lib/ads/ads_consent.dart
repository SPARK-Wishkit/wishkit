import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_config.dart';

/// 광고 추적 동의(ATT)와 광고 SDK 시작 순서를 맡는다.
///
/// App Store 심사(5.1.2): 광고 SDK가 기기 광고 ID(IDFA)를 읽기 **전에** ATT 팝업으로 동의를 받아야 한다.
/// 그래서 순서는 항상
///   1) 첫 화면이 뜬 뒤 ATT 팝업(iOS, 아직 안 물어봤을 때만)
///   2) 그다음 MobileAds.initialize()
///   3) 광고는 [ready] 가 끝난 뒤에 불러온다(native_ad_card.dart, tag_search_banner.dart).
/// 동의하지 않으면(거부·제한) 맞춤이 아닌 광고만 요청한다([request]).
/// 안드로이드는 ATT가 없으므로 바로 2)로 간다.
abstract final class AdsConsent {
  static final Completer<void> _ready = Completer<void>();
  static bool _started = false;
  static bool _personalized = false;

  /// 광고 SDK 시작이 끝나면 완료된다. 광고를 만들기 전에 기다린다.
  static Future<void> get ready => _ready.future;

  /// 첫 프레임이 그려진 뒤 한 번 부른다(그 전에는 iOS가 ATT 팝업을 띄우지 않는다).
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    if (!AdsConfig.supported) {
      _ready.complete();
      return;
    }
    try {
      if (Platform.isIOS) {
        var status = await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          // 앱이 막 켜진 직후엔 팝업이 무시되는 경우가 있어 아주 잠깐 기다린다.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          status = await AppTrackingTransparency.requestTrackingAuthorization();
        }
        _personalized = status == TrackingStatus.authorized;
      } else {
        _personalized = true; // 안드로이드: 사용자는 기기 설정에서 광고 ID를 끌 수 있다.
      }
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('[ads] 광고 준비 실패: $e');
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  /// 광고 요청. 추적 동의가 없으면 맞춤이 아닌 광고(npa)만 요청한다.
  static AdRequest request() => AdRequest(nonPersonalizedAds: !_personalized);
}
