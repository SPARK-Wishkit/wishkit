import 'package:flutter/painting.dart' show EdgeInsets;


/// 첫 방문 튜토리얼(코치마크)의 목록·문구·키를 한곳에 모았다.
/// 문구를 고치거나 단계를 더할 때는 이 파일만 보면 된다.
///
/// 단계를 새로 추가하는 방법
///  1) 아래 [kTutorialVersion] 을 1 올린다.
///  2) 새 단계의 `sinceVersion` 에 올린 번호를 적는다.
///  → 이미 그 튜토리얼을 본 사용자에게는 새로 추가된 단계만 보인다.
const int kTutorialVersion = 1;

/// 어두운 배경 불투명도.
const double kTutorialScrimOpacity = 0.7;

/// 하단 탭 번호 (main.dart 의 HomeShell 순서와 같다).
class TutorialTab {
  static const int wishkit = 0;
  static const int friends = 1;
  static const int salkamalka = 2;
  static const int mypage = 3;
}

/// 강조할 위젯의 이름표. `TutorialTarget(id: ...)` 에 쓴다.
class TutorialTargets {
  static const addFolder = 'addFolder';
  static const firstCard = 'firstCard';
  static const friendSearch = 'friendSearch';
  static const friendWishAll = 'friendWishAll';
  static const friendSalkaFeed = 'friendSalkaFeed';
  static const basketAdd = 'basketAdd';
  static const basketShare = 'basketShare';
  static const sentBaskets = 'sentBaskets';
}

/// 튜토리얼을 띄울지 정할 때 보는 지금 앱 상태.
class TutorialFacts {
  const TutorialFacts({
    this.hasProducts = false,
    this.hasFollowing = false,
    this.hasFriendWishlists = false,
    this.hasSalkaFeed = false,
  });

  /// 내 wishkit 에 담은 상품이 1개 이상
  final bool hasProducts;

  /// 팔로우한 친구가 1명 이상
  final bool hasFollowing;

  /// 팔로우한 친구의 공개 wishkit 폴더가 1개 이상
  final bool hasFriendWishlists;

  /// 친구가 보낸 살까말까가 1개 이상
  final bool hasSalkaFeed;
}

typedef TutorialCondition = bool Function(TutorialFacts facts);

/// 설명 상자를 강조한 영역의 어느 쪽에 둘지.
enum TutorialBoxPlacement {
  /// 공간이 더 넓은 쪽(기본).
  auto,

  /// 항상 아래. 강조한 영역 위쪽 내용을 같이 보여 줘야 할 때.
  below,

  /// 항상 위.
  above,
}

class TutorialStep {
  const TutorialStep({
    required this.title,
    required this.body,
    this.target,
    this.image,
    this.sinceVersion = 1,
    this.friendsInnerTab,
    this.enabledWhen,
    this.holeRadius,
    this.holeTopOnly = false,
    this.holeToInnerMaterial = false,
    this.holeFullWidth = false,
    this.holeInsets = EdgeInsets.zero,
    this.boxPlacement = TutorialBoxPlacement.auto,
  });

  final String title;
  final String body;

  /// 강조할 위젯 이름표([TutorialTargets]). null 이면 화면 가운데 상자.
  final String? target;

  /// 가운데 상자에 넣을 그림(assets). 실제 그림은 팀이 나중에 교체한다.
  final String? image;

  /// 이 단계가 추가된 튜토리얼 버전.
  final int sinceVersion;

  /// 내 친구 화면 안쪽 탭(0 팔로잉·1 팔로워·2 wishkit·3 살까말까)을 이 단계에서 먼저 연다.
  final int? friendsInnerTab;

  /// 이 조건이 거짓이면 단계를 처음부터 뺀다(쪽수 표시도 그만큼 줄어든다).
  final TutorialCondition? enabledWhen;

  /// 강조한 위젯만 어둡지 않게 뚫는 구멍의 모서리 둥글기. 비우면 앱 기본(14).
  /// 위젯의 실제 모양과 맞춰야 모서리에 밝은 조각이 안 남는다.
  final double? holeRadius;

  /// 위쪽 모서리만 둥근 위젯(폴더 탭)일 때 true.
  final bool holeTopOnly;

  /// 버튼처럼 눈에 보이는 모양보다 터치 영역(48dp)이 큰 위젯일 때 true.
  /// 안쪽 Material(실제로 보이는 버튼 몸통) 크기에 구멍을 맞춘다.
  final bool holeToInnerMaterial;

  /// 화면 가로를 꽉 채워 보이는 칸(목록 안의 카드 등)일 때 true.
  /// 구멍을 화면 왼쪽 끝에서 오른쪽 끝까지 넓힌다.
  final bool holeFullWidth;

  /// 구멍을 이만큼 안쪽으로 줄인다(디자인 기준 dp).
  /// 위젯 바깥 여백까지 같이 잡히는 경우(예: 위쪽 margin)에 눈에 보이는 몸통에만 맞추려고 쓴다.
  final EdgeInsets holeInsets;

  /// 설명 상자 위치.
  final TutorialBoxPlacement boxPlacement;
}

class TutorialDef {
  const TutorialDef({
    required this.key,
    required this.tab,
    required this.steps,
    this.requires,
  });

  /// 저장 키 `tutorial_seen_<key>` 에 쓰는 이름.
  final String key;

  /// 이 튜토리얼이 뜨는 하단 탭.
  final int tab;
  final List<TutorialStep> steps;

  /// 이 튜토리얼을 띄우기 위한 조건(첫 상품·첫 팔로우 등).
  final TutorialCondition? requires;
}

// ─────────────────────────────────────────────────────────────
// 튜토리얼 목록
// ─────────────────────────────────────────────────────────────

const String kShareGuideImage = 'assets/tutorial/share_guide.png';

const TutorialDef kTutWishkitTab = TutorialDef(
  key: 'wishkitTab',
  tab: TutorialTab.wishkit,
  steps: [
    TutorialStep(
      title: '쇼핑몰에서 바로 담아요',
      body: '상품 페이지에서 공유 → WishKit을 누르면 사진·이름·가격이 자동으로 담겨요.',
      image: kShareGuideImage,
    ),
    TutorialStep(
      target: TutorialTargets.addFolder,
      holeTopOnly: true,
      holeInsets: EdgeInsets.only(top: 6), // 폴더 탭 위쪽 margin(6)은 빼고 탭 몸통에만
      title: '폴더로 나눠 담아요',
      body: '+를 눌러 \'겨울옷\', \'선물\'처럼 폴더를 만들 수 있어요.',
    ),
  ],
);

final TutorialDef kTutFirstItem = TutorialDef(
  key: 'firstItem',
  tab: TutorialTab.wishkit,
  requires: (f) => f.hasProducts,
  steps: const [
    TutorialStep(
      target: TutorialTargets.firstCard,
      title: '카드를 눌러 보세요',
      body: '메모를 남기고, 쇼핑몰로 바로 가고, 다른 폴더로 옮길 수 있어요.',
    ),
  ],
);

const TutorialDef kTutFriendsTab = TutorialDef(
  key: 'friendsTab',
  tab: TutorialTab.friends,
  steps: [
    TutorialStep(
      target: TutorialTargets.friendSearch,
      title: '친구를 찾아 팔로우해요',
      body: '친구를 팔로우하면 친구의 wishkit을 구경할 수 있어요.',
    ),
  ],
);

final TutorialDef kTutFirstFollow = TutorialDef(
  key: 'firstFollow',
  tab: TutorialTab.friends,
  requires: (f) => f.hasFollowing,
  steps: [
    TutorialStep(
      target: TutorialTargets.friendWishAll,
      holeToInnerMaterial: true,
      boxPlacement: TutorialBoxPlacement.below, // 위쪽 친구 위시 모습이 흐리게라도 보이도록
      title: '친구 위시를 구경해요',
      body: '마음에 드는 상품은 내 wishkit에 바로 담을 수 있어요.',
      friendsInnerTab: 2,
      enabledWhen: (f) => f.hasFriendWishlists,
    ),
    TutorialStep(
      target: TutorialTargets.friendSalkaFeed,
      holeRadius: 0, // 실제 카드가 각진 네모
      holeFullWidth: true,
      title: '친구 고민에 답해 줘요',
      body: '친구가 보낸 살까말까에 댓글로 의견을 남겨요.',
      friendsInnerTab: 3,
      enabledWhen: (f) => f.hasSalkaFeed,
    ),
  ],
);

const TutorialDef kTutSallkaTab = TutorialDef(
  key: 'sallkaTab',
  tab: TutorialTab.salkamalka,
  steps: [
    TutorialStep(
      target: TutorialTargets.basketAdd,
      title: '고민되는 상품을 골라요',
      body: '담아 둔 상품 중 고민되는 것만 골라 담아요.',
    ),
    TutorialStep(
      target: TutorialTargets.basketShare,
      title: '친구에게 물어봐요',
      body: '한마디를 적어 앱 친구·카톡·링크 어디로든 보낼 수 있어요.',
    ),
  ],
);

/// 살까말까 탭인데 내 wishkit 에 상품이 하나도 없을 때 대신 보이는 상자.
/// '봤음'으로 기록하지 않아서, 상품을 담은 뒤 다시 들어오면 위 [kTutSallkaTab] 이 뜬다.
const TutorialStep kTutSallkaEmptyStep = TutorialStep(
  title: '먼저 상품을 담아 주세요',
  body: '위시킷 탭에서 상품을 담으면 살까말까로 친구에게 물어볼 수 있어요.',
);
const String kTutSallkaEmptyButton = '위시킷으로 가기';

const TutorialDef kTutMyPage = TutorialDef(
  key: 'myPage',
  tab: TutorialTab.mypage,
  steps: [
    TutorialStep(
      target: TutorialTargets.sentBaskets,
      holeRadius: 0,
      title: '보낸 살까말까는 여기 모여요',
      body: '친구의 답을 확인하고 다시 보낼 수도 있어요.',
    ),
  ],
);

/// 탭 안에서 먼저 뜨는 순서대로.
final List<TutorialDef> kTutorials = [
  kTutWishkitTab,
  kTutFirstItem,
  kTutFriendsTab,
  kTutFirstFollow,
  kTutSallkaTab,
  kTutMyPage,
];

// ─────────────────────────────────────────────────────────────
// 저장 키 (shared_preferences, 기기마다 한 번 — 계정(uid)별로 나누지 않는다)
// ─────────────────────────────────────────────────────────────

const String kTutorialSeenPrefix = 'tutorial_seen_';
const String kTutorialVerPrefix = 'tutorial_ver_';
const String kTutorialVersionKey = 'tutorial_version';

String tutorialSeenKey(String key) => '$kTutorialSeenPrefix$key';
String tutorialVerKey(String key) => '$kTutorialVerPrefix$key';

// ─────────────────────────────────────────────────────────────
// 마이페이지 '사용 가이드 다시 보기'
// ─────────────────────────────────────────────────────────────

const String kTutorialReplayLabel = '사용 가이드 다시 보기';
const String kTutorialReplayDone = '각 탭을 열면 사용 가이드가 다시 보여요.';

// 버튼 글자
const String kTutorialSkip = '건너뛰기';
const String kTutorialNext = '다음';
const String kTutorialDone = '완료';
