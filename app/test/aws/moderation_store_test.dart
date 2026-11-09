import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/models/models.dart';
import 'package:figmadesign/services/aws/basket_store.dart';
import 'package:figmadesign/services/aws/gql_runner.dart';
import 'package:figmadesign/services/aws/moderation_store.dart';
import 'package:figmadesign/services/aws/polling.dart';
import 'package:figmadesign/services/aws/user_data_store.dart';

import 'fake_appsync.dart';

void main() {
  late FakeAppSync appsync;
  late AwsUserDataStore data;
  late AwsBasketStore baskets;
  late AwsModerationStore moderation;

  Future<void> signUp(String uid) async {
    appsync.caller = uid;
    await data.ensureProfile(uid: uid, email: '$uid@x.com', name: uid, handle: uid);
  }

  Product product(int id) => Product(
        id: id,
        listId: 'all',
        name: '상품$id',
        price: 1000,
        image: '',
        platform: '무신사',
      );

  setUp(() async {
    appsync = FakeAppSync('');
    data = AwsUserDataStore(runner: appsync);
    baskets = AwsBasketStore(
      runner: appsync,
      hub: RefreshHub(),
      inboxInterval: const Duration(hours: 1),
      commentsInterval: const Duration(hours: 1),
    );
    moderation = AwsModerationStore(runner: appsync);
    await signUp('amy');
    await signUp('bob');
    appsync.caller = 'amy';
  });

  group('차단', () {
    test('차단 · 해제는 내 목록에만 반영된다', () async {
      appsync.caller = 'bob';
      await moderation.setBlocked(myUid: 'bob', targetUid: 'amy', blocked: true);
      // 연타해도 오류 없이 넘어간다
      await moderation.setBlocked(myUid: 'bob', targetUid: 'amy', blocked: true);
      expect(await moderation.blockedIds('bob'), {'amy'});

      await moderation.setBlocked(myUid: 'bob', targetUid: 'amy', blocked: false);
      expect(await moderation.blockedIds('bob'), isEmpty);
    });

    test('남의 이름으로 차단을 만들 수 없다', () async {
      appsync.caller = 'amy';
      expect(
        moderation.setBlocked(myUid: 'bob', targetUid: 'amy', blocked: true),
        throwsA(isA<AwsDataException>()),
      );
    });
  });

  group('신고', () {
    test('받은 살까말까 신고: 보낸 사람이 신고 대상으로 저장된다', () async {
      await baskets.sendBasket(recipientUids: ['bob'], items: [product(1)], threadId: 'sb-1');
      appsync.caller = 'bob';
      final received = await baskets.loadReceivedBaskets('bob');
      await moderation.report(
        type: ReportTargetType.basket,
        targetUserId: 'amy',
        targetId: received.single.id,
        reason: ReportReason.spam,
      );
      final reports = appsync.table('Report').values.toList();
      expect(reports, hasLength(1));
      expect(reports.single['targetUserId'], 'amy');
      expect(reports.single['status'], 'open');
    });

    test('없는 댓글은 신고할 수 없다', () async {
      appsync.caller = 'bob';
      expect(
        moderation.report(
          type: ReportTargetType.comment,
          targetUserId: 'amy',
          targetId: 'nope',
          threadId: 'sb-1',
          reason: ReportReason.abuse,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  test('탈퇴 정리: 친구 받은함의 내 살까말까와 내 댓글이 지워진다', () async {
    await baskets.sendBasket(recipientUids: ['bob'], items: [product(1)], threadId: 'sb-1');
    appsync.caller = 'bob';
    await baskets.sendBasket(recipientUids: ['amy'], items: [product(2)], threadId: 'sb-2');
    appsync.caller = 'amy';
    await baskets.addComment(threadId: 'sb-2', text: '좋아요');

    await moderation.deleteMySharedContent();

    appsync.caller = 'bob';
    expect(await baskets.loadReceivedBaskets('bob'), isEmpty);
    expect(await baskets.loadComments('sb-2'), isEmpty);
  });

  test('탈퇴 정리: 남의 댓글방에 남긴 내 투표와 내 댓글방의 투표가 지워진다', () async {
    // amy → bob (amy 의 댓글방 sb-1), bob → amy (bob 의 댓글방 sb-2)
    await baskets.sendBasket(recipientUids: ['bob'], items: [product(1)], threadId: 'sb-1');
    appsync.caller = 'bob';
    await baskets.sendBasket(recipientUids: ['amy'], items: [product(2)], threadId: 'sb-2');
    await baskets.vote(threadId: 'sb-1', productIds: ['1']);
    appsync.caller = 'amy';
    await baskets.vote(threadId: 'sb-2', productIds: ['2']);

    await moderation.deleteMySharedContent();

    appsync.caller = 'bob';
    expect(await baskets.loadVotes('sb-2'), isEmpty);
    expect(appsync.table('BasketVote'), isEmpty);
  });
}
