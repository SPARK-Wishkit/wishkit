/// 출시 범위를 정하는 기능 스위치.
library;

/// 태그 사진으로 온라인 상품 자동 찾기(엔진 /identify-tag 호출).
///
/// 기본값은 꺼짐 — 출시 빌드(`flutter build` / `flutter run --release`)는 아무것도 안 붙이면 꺼진 채로 나간다.
/// 꺼져 있으면 "매장에서 본 옷 직접 기록하기"에서 태그 사진은 첨부만 하고(엔진으로 보내지 않음) 이름·가격은 직접 입력한다.
/// 엔진을 개발·테스트할 때만 켠다:
///   flutter run --dart-define=TAG_AUTO_FIND=true
const bool kTagAutoFind = bool.fromEnvironment('TAG_AUTO_FIND');
