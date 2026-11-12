import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../theme/diary_theme.dart';
import 'ads_config.dart';
import 'ads_consent.dart';

/// 태그 찾기를 기다리는 동안(10~25초) 버튼 **아래에** 보여 주는 큰 배너 광고.
///
/// "인라인 적응형 배너"로 요청한다: 가로 = 화면 폭, 세로 = 최대 화면 높이의 [heightRatio].
/// 구글이 그 칸에 맞는 광고(큰 이미지·동영상)를 골라 보내고, 실제 높이는 광고마다 다를 수 있다.
/// AdMob 배너 정책에 맞춰:
/// - 입력칸·버튼 **위에 겹치지 않는다**(아래 칸에만, 화면이 길어지면 스크롤).
/// - 버튼과 충분히 떨어뜨리고, 위에 "광고" 표시를 단다.
/// - 못 불러오면 빈칸 없이 아무것도 안 그린다.
class TagSearchBannerAd extends StatefulWidget {
  const TagSearchBannerAd({super.key, this.heightRatio = 0.7});

  /// 화면 높이 중 광고 칸이 최대로 차지할 비율.
  final double heightRatio;

  @override
  State<TagSearchBannerAd> createState() => _TagSearchBannerAdState();
}

class _TagSearchBannerAdState extends State<TagSearchBannerAd> {
  BannerAd? _ad;
  AdSize? _size; // 실제로 받은 광고 크기
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested || !AdsConfig.supported) return;
    _requested = true;
    final screen = MediaQuery.sizeOf(context);
    // 추적 동의(ATT)와 광고 SDK 준비가 끝난 뒤에 불러온다 (ads_consent.dart).
    AdsConsent.ready.then((_) {
      if (mounted) _load(screen);
    });
  }

  void _load(Size screen) {
    final width = (screen.width - 40).floor(); // 화면 좌우 여백 20씩
    final maxHeight = (screen.height * widget.heightRatio).floor();
    final ad = BannerAd(
      adUnitId: AdsConfig.bannerUnitId,
      size: AdSize.getInlineAdaptiveBannerAdSize(width, maxHeight),
      request: AdsConsent.request(),
      listener: BannerAdListener(
        onAdLoaded: (loaded) async {
          // 적응형이라 실제 높이는 광고마다 다르다 — 받은 크기 그대로 칸을 잡는다.
          final size = await (loaded as BannerAd).getPlatformAdSize();
          if (!mounted) return;
          setState(() => _size = size ?? AdSize(width: width, height: maxHeight));
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[ads] 태그 찾기 배너를 못 불러옴: ${error.message}');
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    final size = _size;
    if (ad == null || size == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('광고', style: DiaryTheme.ui(12, color: DiaryColors.inkSoft)),
        const SizedBox(height: 4),
        Center(
          child: SizedBox(
            width: size.width.toDouble(),
            height: size.height.toDouble(),
            child: AdWidget(ad: ad),
          ),
        ),
      ],
    );
  }
}
