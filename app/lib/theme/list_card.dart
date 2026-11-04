import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'diary_theme.dart';

/// 위시리스트 목록 카드(상품 카드·광고 카드) 공통 치수.
///
/// 상품 카드와 광고 카드가 **항상 같은 높이**가 되게, 두 카드 모두 [heightOf]를 쓴다.
/// 상품 카드는 상품명 줄 수와 상관없이 이 높이로 고정된다(상품명은 최대 2줄).
abstract final class ListCardMetrics {
  /// 카드 안 위아래 여백.
  static const verticalPadding = 12.0;

  /// 상품 사진 크기.
  static const thumbSize = 72.0;

  /// 카드 글자 크기와 줄 높이 — 상품 카드가 이 값으로 그리고, [heightOf]가 같은 값으로 높이를 센다.
  static const platformSize = 12.0;
  static const nameSize = 13.0;
  static const priceSize = 15.0;
  static const lineHeight = 1.3;
  static const nameMaxLines = 2;

  /// 쇼핑몰·상품명·가격 사이 간격 합.
  static const _textGaps = 2.0 + 4.0;

  /// 글자 크기 1배일 때 높이(= [heightOf]의 기본값). AdMob 작은 템플릿 권장 최소(90)보다 크다.
  static const height = 100.0;

  /// 휴대폰 글자 크기 설정까지 반영한 카드 높이.
  static double heightOf(BuildContext context) {
    final ts = MediaQuery.textScalerOf(context);
    final text = ts.scale(platformSize) * lineHeight +
        ts.scale(nameSize) * lineHeight * nameMaxLines +
        ts.scale(priceSize) * lineHeight +
        _textGaps;
    final content = math.max(thumbSize, text);
    return math.max(height, (content + verticalPadding * 2).ceilToDouble());
  }

  /// 모서리 둥글기.
  static const radius = DiaryTheme.radius;

  /// 카드 그림자 높이.
  static const elevation = 0.0;
}
