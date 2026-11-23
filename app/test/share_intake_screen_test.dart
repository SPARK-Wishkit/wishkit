import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:figmadesign/data/app_store.dart';
import 'package:figmadesign/screens/share/share_intake_screen.dart';
import 'package:figmadesign/services/aws/gql_runner.dart';
import 'package:figmadesign/services/parsing_bridge.dart';

import 'fake_extract_gql.dart';

const _ably = 'https://applink.a-bly.com/n2ac4ga';
const _musinsa = 'https://musinsa.onelink.me/PvkC/8rwkorkj';

/// 요청마다 Completer 를 만들어, 테스트가 원하는 때에 응답을 돌려준다(읽는 중 상태를 만들려고).
class _HeldGql implements GqlRunner {
  final calls = <String, Completer<Map<String, dynamic>>>{};

  @override
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, dynamic> variables = const {},
    GqlAuth auth = GqlAuth.user,
  }) {
    final c = Completer<Map<String, dynamic>>();
    calls[variables['url'] as String] = c;
    return c.future;
  }

  // 사진 주소는 비운다(위젯 테스트에서 네트워크 이미지를 받지 않게).
  void answer(String url, String name, int price) => calls[url]!.complete({
    'extractProduct': extracted(
      productUrl: url,
      name: name,
      price: price,
      image: null,
    ),
  });

  @override
  Future<Map<String, dynamic>> mutate(
    String document, {
    Map<String, dynamic> variables = const {},
  }) => throw UnsupportedError('mutate');
}

String _linkField(WidgetTester tester) => tester
    .widget<TextField>(find.widgetWithText(TextField, '상품 링크'))
    .controller!
    .text;

Future<(AppStore, _HeldGql)> _open(
  WidgetTester tester, {
  String? pending,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore(backendConfigured: false);
  await store.init();
  if (pending != null) store.setPendingShareUrl(pending);
  final gql = _HeldGql();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        home: ShareIntakeScreen(bridge: ParsingBridge(runner: gql)),
      ),
    ),
  );
  await tester.pump(); // initState 뒤 첫 프레임에 읽기 시작
  return (store, gql);
}

void main() {
  testWidgets('화면을 열면 공유 주소를 읽고, 꺼낸 주소는 비운다', (tester) async {
    final (store, gql) = await _open(tester, pending: _ably);

    expect(_linkField(tester), _ably);
    expect(gql.calls.keys, [_ably]);
    expect(store.pendingShareUrl, isNull); // 다음에 다시 열 때 예전 공유를 또 읽지 않는다
  });

  testWidgets('화면이 열린 채로 다시 공유하면 새 주소로 바뀌고, 앞 결과는 버린다', (tester) async {
    final (store, gql) = await _open(tester, pending: _ably);

    store.setPendingShareUrl(_musinsa); // 에이블리를 읽는 중에 무신사에서 공유
    await tester.pump();
    await tester.pump();

    expect(_linkField(tester), _musinsa);
    expect(gql.calls.keys, [_ably, _musinsa]);
    expect(store.pendingShareUrl, isNull);

    gql.answer(_ably, '에이블리 원피스', 39000); // 늦게 온 앞 결과
    await tester.pump();
    expect(find.text('에이블리 원피스'), findsNothing);
    expect(find.text('불러오기 취소'), findsOneWidget); // 무신사는 아직 읽는 중

    gql.answer(_musinsa, '와플 후드집업', 64900);
    await tester.pumpAndSettle();
    expect(find.text('불러오기 취소'), findsNothing);
    expect(find.text('와플 후드집업'), findsWidgets);
  });

  testWidgets('읽는 중에 취소하면 바로 입력 상태로 돌아가고, 늦게 온 결과는 쓰지 않는다', (tester) async {
    final (_, gql) = await _open(tester, pending: _musinsa);
    expect(find.text('불러오기 취소'), findsOneWidget);

    await tester.tap(find.text('불러오기 취소'));
    await tester.pump();
    expect(find.text('불러오기 취소'), findsNothing);
    expect(find.text('상품 불러오기'), findsOneWidget);
    expect(_linkField(tester), _musinsa); // 주소는 남겨 둔다(고쳐서 다시 읽을 수 있게)

    gql.answer(_musinsa, '와플 후드집업', 64900);
    await tester.pumpAndSettle();
    expect(find.text('와플 후드집업'), findsNothing);
  });
}
