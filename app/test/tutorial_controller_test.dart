import 'dart:ui';

import 'package:figmadesign/tutorial/tutorial_content.dart';
import 'package:figmadesign/tutorial/tutorial_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rect = Rect.fromLTWH(20, 100, 120, 48);

TutorialController _make({Set<String> missing = const {}}) => TutorialController(
      rectResolver: (id) async => missing.contains(id) ? null : _rect,
    );

Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('위시킷 탭 첫 방문: 가운데 상자 → + 버튼 순서로 2단계, 끝나면 봤음 기록', () async {
    final c = _make();
    await c.evaluate(tab: TutorialTab.wishkit, facts: const TutorialFacts());

    expect(c.isShowing, true);
    expect(c.stepCount, 2);
    expect(c.stepNumber, 1);
    expect(c.step!.target, isNull); // 가운데 상자(이미지)
    expect(c.targetRect, isNull);

    await c.next();
    expect(c.stepNumber, 2);
    expect(c.step!.target, TutorialTargets.addFolder);
    expect(c.targetRect, _rect);
    expect(c.isLastStep, true);

    await c.next(); // 완료
    expect(c.isActive, false);
    expect((await _prefs()).getBool('tutorial_seen_wishkitTab'), true);
    expect((await _prefs()).getInt('tutorial_version'), kTutorialVersion);

    // 다시 열어도 같은 튜토리얼은 안 뜬다.
    await c.evaluate(tab: TutorialTab.wishkit, facts: const TutorialFacts());
    expect(c.isActive, false);
  });

  test('건너뛰기도 봤음으로 기록한다', () async {
    final c = _make();
    await c.evaluate(tab: TutorialTab.friends, facts: const TutorialFacts());
    expect(c.step!.target, TutorialTargets.friendSearch);

    await c.skip();
    expect(c.isActive, false);
    expect((await _prefs()).getBool('tutorial_seen_friendsTab'), true);
  });

  test('첫 상품 카드 튜토리얼은 위시킷 탭 튜토리얼이 끝난 뒤에 뜬다', () async {
    final c = _make();
    const facts = TutorialFacts(hasProducts: true);

    await c.evaluate(tab: TutorialTab.wishkit, facts: facts);
    expect(c.stepCount, 2); // 아직은 wishkitTab 튜토리얼

    await c.skip();
    await c.evaluate(tab: TutorialTab.wishkit, facts: facts);
    expect(c.isShowing, true);
    expect(c.step!.target, TutorialTargets.firstCard);

    await c.next();
    expect((await _prefs()).getBool('tutorial_seen_firstItem'), true);
  });

  test('상품이 없으면 첫 상품 카드 튜토리얼은 안 뜬다', () async {
    SharedPreferences.setMockInitialValues({'tutorial_seen_wishkitTab': true});
    final c = _make();
    await c.evaluate(tab: TutorialTab.wishkit, facts: const TutorialFacts());
    expect(c.isActive, false);
  });

  test('강조 대상을 못 찾는 단계는 조용히 건너뛴다', () async {
    final c = _make(missing: {TutorialTargets.addFolder});
    await c.evaluate(tab: TutorialTab.wishkit, facts: const TutorialFacts());
    expect(c.stepNumber, 1);

    await c.next(); // 2단계는 대상이 없어서 건너뛰고 끝난다.
    expect(c.isActive, false);
    expect((await _prefs()).getBool('tutorial_seen_wishkitTab'), true);
  });

  test('보여 줄 단계가 하나도 없으면 봤음으로 기록하지 않는다', () async {
    final c = _make(missing: {TutorialTargets.friendSearch});
    await c.evaluate(tab: TutorialTab.friends, facts: const TutorialFacts());
    expect(c.isActive, false);
    expect((await _prefs()).getBool('tutorial_seen_friendsTab'), isNull);
  });

  test('첫 팔로우 튜토리얼: 조건에 맞는 단계만, 쪽수도 그만큼', () async {
    SharedPreferences.setMockInitialValues({'tutorial_seen_friendsTab': true});

    // 친구 wishkit 폴더는 없고 받은 살까말까만 있다 → 1/1 로 보인다.
    var c = _make();
    await c.evaluate(
      tab: TutorialTab.friends,
      facts: const TutorialFacts(hasFollowing: true, hasSalkaFeed: true),
    );
    expect(c.stepCount, 1);
    expect(c.step!.target, TutorialTargets.friendSalkaFeed);

    // 둘 다 없으면 아예 안 뜬다(봤음 기록도 없음).
    SharedPreferences.setMockInitialValues({'tutorial_seen_friendsTab': true});
    c = _make();
    await c.evaluate(
      tab: TutorialTab.friends,
      facts: const TutorialFacts(hasFollowing: true),
    );
    expect(c.isActive, false);
    expect((await _prefs()).getBool('tutorial_seen_firstFollow'), isNull);
  });

  test('첫 팔로우 튜토리얼 단계가 바뀔 때 친구 화면 안쪽 탭을 연다', () async {
    SharedPreferences.setMockInitialValues({'tutorial_seen_friendsTab': true});
    final opened = <int>[];
    final c = _make()..onSelectFriendsInnerTab = opened.add;
    await c.evaluate(
      tab: TutorialTab.friends,
      facts: const TutorialFacts(
        hasFollowing: true,
        hasFriendWishlists: true,
        hasSalkaFeed: true,
      ),
    );
    expect(c.stepCount, 2);
    await c.next();
    expect(opened, [2, 3]);
  });

  test('살까말까 탭: 상품이 없으면 안내 상자, 봤음으로 기록하지 않는다', () async {
    final c = _make();
    await c.evaluate(
        tab: TutorialTab.salkamalka, facts: const TutorialFacts());
    expect(c.isEmptyMode, true);
    expect(c.step!.title, '먼저 상품을 담아 주세요');

    var wentToWishkit = false;
    c.onGoWishkit = () => wentToWishkit = true;
    c.goToWishkit();
    expect(wentToWishkit, true);
    expect(c.isActive, false);
    expect((await _prefs()).getBool('tutorial_seen_sallkaTab'), isNull);

    // 상품을 담은 뒤 다시 들어오면 원래 튜토리얼 2단계가 뜬다.
    final c2 = _make();
    await c2.evaluate(
      tab: TutorialTab.salkamalka,
      facts: const TutorialFacts(hasProducts: true),
    );
    expect(c2.isEmptyMode, false);
    expect(c2.stepCount, 2);
    expect(c2.step!.target, TutorialTargets.basketAdd);
  });

  test('튜토리얼 중 탭을 바꾸면 닫고 봤음으로 기록한다', () async {
    final c = _make();
    await c.evaluate(tab: TutorialTab.friends, facts: const TutorialFacts());
    await c.onTabChanged(TutorialTab.salkamalka);
    expect(c.isActive, false);
    expect((await _prefs()).getBool('tutorial_seen_friendsTab'), true);
  });

  test('같은 탭 안에서는 닫히지 않는다', () async {
    final c = _make();
    await c.evaluate(tab: TutorialTab.friends, facts: const TutorialFacts());
    await c.onTabChanged(TutorialTab.friends);
    expect(c.isActive, true);
  });

  test('사용 가이드 다시 보기: 봤음 기록을 모두 지우고, 탭에 들어가면 다시 뜬다', () async {
    SharedPreferences.setMockInitialValues({
      'tutorial_seen_wishkitTab': true,
      'tutorial_ver_wishkitTab': 1,
      'tutorial_seen_myPage': true,
      'other_key': 'keep',
    });
    final c = _make();
    await c.resetAll();

    final prefs = await _prefs();
    expect(prefs.getBool('tutorial_seen_wishkitTab'), isNull);
    expect(prefs.getBool('tutorial_seen_myPage'), isNull);
    expect(prefs.getString('other_key'), 'keep');

    // 바로 뜨지는 않고, 탭에 들어갈 때 뜬다.
    expect(c.isActive, false);
    await c.evaluate(tab: TutorialTab.mypage, facts: const TutorialFacts());
    expect(c.step!.target, TutorialTargets.sentBaskets);
  });

  test('낮은 버전으로 본 사용자에게는 새로 추가된 단계만 보인다', () async {
    // 지금 버전보다 낮은 0 버전으로 본 것으로 저장돼 있다고 가정 → sinceVersion 1 단계가 새 단계.
    SharedPreferences.setMockInitialValues({
      'tutorial_seen_friendsTab': true,
      'tutorial_ver_friendsTab': 0,
    });
    final c = _make();
    await c.evaluate(tab: TutorialTab.friends, facts: const TutorialFacts());
    expect(c.isShowing, true);

    // 현재 버전으로 본 사용자에게는 안 뜬다.
    SharedPreferences.setMockInitialValues({
      'tutorial_seen_friendsTab': true,
      'tutorial_ver_friendsTab': kTutorialVersion,
    });
    final c2 = _make();
    await c2.evaluate(tab: TutorialTab.friends, facts: const TutorialFacts());
    expect(c2.isActive, false);
  });

  test('다시 보기를 누른 그 탭에서는 바로 뜨지 않고, 다른 탭에 갔다 오면 뜬다', () async {
    final c = _make();
    // 마이페이지 튜토리얼을 보고 끝낸 상태.
    await c.evaluate(tab: TutorialTab.mypage, facts: const TutorialFacts());
    await c.next();
    expect(c.isActive, false);

    await c.resetAll(); // 마이페이지에서 '사용 가이드 다시 보기'
    await c.evaluate(tab: TutorialTab.mypage, facts: const TutorialFacts());
    expect(c.isActive, false); // 같은 탭에서는 바로 안 뜬다

    await c.evaluate(tab: TutorialTab.friends, facts: const TutorialFacts());
    expect(c.isShowing, true); // 다른 탭에 들어가면 뜬다
    await c.skip();

    await c.evaluate(tab: TutorialTab.mypage, facts: const TutorialFacts());
    expect(c.isShowing, true); // 돌아오면 마이페이지 것도 다시 뜬다
  });
}
