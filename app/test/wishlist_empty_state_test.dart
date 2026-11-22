// 가입 직후 "Bad state: No element" (2026-11-22 기기 확인).
// 라우터는 Cognito 로그인만 보고 바로 홈으로 보내는데, AppStore 는 그 뒤에 폴더(tabs)를 불러온다
// (새 계정은 기본 폴더도 이때 만든다). 그 사이 tabs 가 비어 있으면 홈 화면이 터지면 안 된다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:figmadesign/data/app_store.dart';
import 'package:figmadesign/models/models.dart';
import 'package:figmadesign/screens/wishlist/wishlist_screen.dart';

Future<AppStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore(backendConfigured: false);
  await store.init();
  // 테스트는 AWS 없이 돌린다(backendConfigured: false → '연결 안 됨' 안내). 여기서는 "불러오는 중"을 본다.
  store.backendError = null;
  return store;
}

Future<void> _pumpHome(WidgetTester tester, AppStore store) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: store,
      child: const MaterialApp(home: WishlistScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  test('폴더를 아직 못 불러왔으면 selectedTab 은 null (예외 없음)', () async {
    final store = await _store();
    expect(store.tabs, isEmpty);
    expect(store.selectedTab, isNull);
  });

  testWidgets('폴더가 0개인 상태로 홈을 그려도 예외 없이 로딩 표시', (tester) async {
    final store = await _store();
    expect(store.tabs, isEmpty);

    await _pumpHome(tester, store);

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('불러오기가 실패해 폴더가 없으면 빨간 화면 대신 안내 문구', (tester) async {
    final store = await _store();
    store.backendError = '데이터를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';

    await _pumpHome(tester, store);

    expect(tester.takeException(), isNull);
    expect(find.text('데이터를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('폴더가 들어오면 로딩이 사라지고 홈이 그려진다', (tester) async {
    final store = await _store();
    await _pumpHome(tester, store);

    store.tabs = [WishlistTab(id: 'all', name: '전체', isPublic: true)];
    store.notifyListeners();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('전체'), findsWidgets);
  });
}
