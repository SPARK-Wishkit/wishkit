/// 위시리스트 목록 카드(상품 카드·광고 카드) 공통 치수.
///
/// 광고 카드가 상품 카드와 같은 크기로 보이게 두 카드가 이 값을 같이 쓴다.
abstract final class ListCardMetrics {
  /// 카드 높이. 상품 카드 = 사진 72 + 위아래 여백 12씩(상품명이 3줄이면 더 커진다).
  /// AdMob 작은 템플릿의 권장 최소 높이(90)보다 크다.
  static const height = 96.0;

  /// 모서리 둥글기.
  static const radius = 14.0;

  /// 카드 그림자 높이.
  static const elevation = 0.0;
}
