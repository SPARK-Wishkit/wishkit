import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:figmadesign/data/app_store.dart';

import 'package:figmadesign/models/models.dart';
import 'package:figmadesign/services/aws/gql_documents.dart';
import 'package:figmadesign/services/aws/gql_runner.dart';
import 'package:figmadesign/services/aws/user_data_store.dart';

import 'fake_appsync.dart';

/// 폴더 만들기는 "성공"하지만 목록에는 계속 안 보이는 서버를 흉내 낸다.
class _NeverVisibleTabs implements GqlRunner {
  _NeverVisibleTabs(this.inner);
  final FakeAppSync inner;
  int tabListCalls = 0;

  @override
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, dynamic> variables = const {},
    GqlAuth auth = GqlAuth.user,
  }) {
    if (document == Gql.listTabs) {
      tabListCalls++;
      return Future.value({
        'listWishTabs': {'items': [], 'nextToken': null},
      });
    }
    return inner.query(document, variables: variables, auth: auth);
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String document, {
    Map<String, dynamic> variables = const {},
  }) {
    if (document == Gql.createTab) return Future.value({});
    return inner.mutate(document, variables: variables);
  }
}

void main() {
  setUp(() => AwsUserDataStore.retryDelay = Duration.zero);
  tearDown(() => AwsUserDataStore.retryDelay = const Duration(seconds: 1));

  test('전체 탭을 만든 뒤에도 비어 있으면 한 번 더 읽고, 그래도 비면 실패로 처리한다', () async {
    final runner = _NeverVisibleTabs(FakeAppSync('uid-a'));
    final store = AwsUserDataStore(runner: runner, random: Random(1));

    await expectLater(store.loadTabs('uid-a'), throwsA(isA<StateError>()));
    // 처음 읽기 + 만든 뒤 읽기 + 재시도 읽기
    expect(runner.tabListCalls, 3);
  });

  test('빈 목록으로는 saveTabs 가 서버에 아무것도 쓰지 않는다', () async {
    final appsync = FakeAppSync('uid-a');
    final store = AwsUserDataStore(runner: appsync, random: Random(1));
    await store.loadTabs('uid-a'); // '전체' 탭 만들기
    final before = appsync.mutationCount;

    await store.saveTabs('uid-a', <WishlistTab>[]);

    expect(appsync.mutationCount, before);
    expect((await store.loadTabs('uid-a')).map((t) => t.id), ['all']);
  });

  test('AppStore: 폴더 목록이 비어 있어도 멈추지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(backendConfigured: false);
    await store.init();
    store.tabs = [];

    expect(store.selectedTab, isNull);
    expect(store.allTab, isNull);
    await store.reorderTabs(0, 1); // 예외 없이 지나가야 한다
    expect(store.tabs, isEmpty);
  });
}
