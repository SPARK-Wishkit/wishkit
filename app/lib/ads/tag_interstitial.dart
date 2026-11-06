import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_config.dart';

/// 오프라인 태그 찾기 때만, 가끔 띄우는 전면 광고(동영상 포함).
///
/// AdMob 정책·권장 사항에 맞춘 규칙:
/// - **자연스러운 쉬는 구간에만**: 사용자가 태그 사진을 고르고 "찾기"가 시작된 순간(엔진이 10~25초
///   상품을 찾는 동안). 결과가 나온 뒤나 입력 중에는 띄우지 않는다 — 예상 못 한 순간에 화면을 가리지 않게.
/// - **미리 불러 둔 광고만**: 화면을 열 때 미리 불러 두고, 준비가 안 됐으면 그냥 건너뛴다.
///   광고 때문에 찾기를 기다리게 하지 않는다.
/// - **가끔만**: [AdsConfig.tagAdChance] 확률, 한 번 띄우면 [AdsConfig.tagAdCooldown] 동안 다시 안 띄운다.
/// - 광고가 떠 있는 동안에도 찾기는 뒤에서 계속되고, 닫으면 결과가 그대로 보인다.
class TagInterstitial {
  TagInterstitial._();

  static final instance = TagInterstitial._();

  InterstitialAd? _ad;
  bool _loading = false;
  DateTime? _lastShown;
  final _random = Random();

  /// 태그 찾기 화면을 열 때 부른다. 이미 있거나 불러오는 중이면 아무것도 안 한다.
  void preload() {
    if (!AdsConfig.supported || _ad != null || _loading) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: AdsConfig.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _ad = ad;
          debugPrint('[ads] 태그 전면 광고 준비됨');
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          debugPrint('[ads] 태그 전면 광고를 못 불러옴: ${error.message}');
        },
      ),
    );
  }

  /// 태그 찾기를 시작할 때 부른다. 조건이 맞으면 광고를 띄우고 true, 아니면 false.
  /// 사진 선택 창이 완전히 닫힌 뒤에 띄운다(닫히는 중에 띄우면 iOS에서 조용히 실패한다).
  /// 찾기는 광고를 기다리지 않는다.
  Future<bool> maybeShow() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final ad = _ad;
    if (!AdsConfig.supported) return false;
    if (ad == null) {
      debugPrint('[ads] 건너뜀: 광고가 아직 준비 안 됨(${_loading ? '불러오는 중' : '불러오기 시작'})');
      preload();
      return false;
    }
    if (!AdsConfig.forceTagAds) {
      final last = _lastShown;
      if (last != null &&
          DateTime.now().difference(last) < AdsConfig.tagAdCooldown) {
        debugPrint('[ads] 건너뜀: 마지막 광고 후 ${AdsConfig.tagAdCooldown.inMinutes}분이 안 지남');
        return false;
      }
      if (_random.nextDouble() >= AdsConfig.tagAdChance) {
        debugPrint('[ads] 건너뜀: 이번엔 확률(${AdsConfig.tagAdChance})에 안 걸림');
        return false;
      }
    }

    _ad = null;
    _lastShown = DateTime.now();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preload(); // 다음 기회를 위해 미리 불러 둔다
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[ads] 광고 띄우기 실패: ${error.message}');
        ad.dispose();
        preload();
      },
    );
    debugPrint('[ads] 태그 전면 광고 띄움');
    await ad.show();
    return true;
  }
}
