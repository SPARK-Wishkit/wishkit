import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:figmadesign/models/models.dart';
import 'package:figmadesign/services/aws/gql_documents.dart';
import 'package:figmadesign/services/aws/gql_runner.dart';
import 'package:figmadesign/services/aws/product_tag_store.dart';

class _FakeRunner implements GqlRunner {
  _FakeRunner(this.response);

  final Map<String, dynamic> response;
  String? lastDocument;
  Map<String, dynamic>? lastVariables;

  @override
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, dynamic> variables = const {},
    GqlAuth auth = GqlAuth.user,
  }) async {
    lastDocument = document;
    lastVariables = variables;
    return response;
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String document, {
    Map<String, dynamic> variables = const {},
  }) => throw UnimplementedError();
}

void main() {
  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]);

  test('공식몰에서 찾은 결과를 읽고, 사진은 base64로 보낸다', () async {
    final runner = _FakeRunner({
      'identifyProductTag': {
        'status': 'found',
        'brand': 'NIKE',
        'productCode': 'DV1234-100',
        'productName': "에어 포스 1 '07",
        'color': 'WHITE',
        'tagPrice': 139000,
        'officialDomain': 'nike.com',
        'matchUrl': 'https://www.nike.com/kr/t/af1/DV1234-100',
        'matchHost': 'nike.com',
        'matchSource': 'official',
        'verifiedBy': 'product_code',
        'note': null,
      },
    });
    final store = AwsProductTagStore(runner: runner);

    final r = await store.identify(jpeg, 'image/jpeg');

    expect(runner.lastDocument, Gql.identifyProductTag);
    expect(runner.lastVariables, {
      'imageBase64': base64Encode(jpeg),
      'mimeType': 'image/jpeg',
    });
    expect(r.status, TagIdentifyStatus.found);
    expect(r.foundOnOfficialSite, isTrue);
    expect(r.needsUserCheck, isFalse);
    expect(r.matchUrl, 'https://www.nike.com/kr/t/af1/DV1234-100');
    expect(r.suggestedName, "NIKE 에어 포스 1 '07 (WHITE)");
    expect(r.tagPrice, 139000);
  });

  test('확인 필요(needs_confirm) — 링크는 있지만 사용자 확인이 필요하다', () {
    final r = TagIdentifyResult.fromJson({
      'status': 'needs_confirm',
      'brand': 'BEAKER',
      'productCode': 'QQ6X39EP20',
      'matchUrl': 'https://www.ssfshop.com/BEAKER/GM0026101660266/good',
      'matchHost': 'ssfshop.com',
      'matchSource': 'mall',
      'verifiedBy': 'search',
      'note': '검색으로 찾았지만 페이지를 열어 품번을 확인하지는 못했어요',
    });
    expect(r.status, TagIdentifyStatus.needsConfirm);
    expect(r.hasMatch, isTrue);
    expect(r.matchHost, 'ssfshop.com');
    expect(r.verifiedBy, 'search');
  });

  test('needs_confirm인데 URL이 없으면 못 찾은 것으로 본다', () {
    final r = TagIdentifyResult.fromJson({'status': 'needs_confirm'});
    expect(r.status, TagIdentifyStatus.notFound);
    expect(r.hasMatch, isFalse);
  });

  test('찾은 페이지에서 읽은 상품명·가격·사진을 받는다', () {
    final r = TagIdentifyResult.fromJson({
      'status': 'found',
      'brand': 'BEAKER',
      'productCode': 'QQ6X39EP20',
      'matchUrl': 'https://www.ssfshop.com/BEAKER/GM0026101660266/good',
      'matchHost': 'ssfshop.com',
      'matchSource': 'mall',
      'verifiedBy': 'product_code_base',
      'matchName': '[BEAKER] EPINGLER Laced Hoodie - Oatmeal',
      'matchPrice': 269100,
      'matchRegularPrice': 299000,
      'matchImage': 'https://img.ssfshop.com/goods/QQ6X39EP20_01.jpg',
    });
    expect(r.hasMatchDetails, isTrue);
    expect(r.matchPrice, 269100);
    expect(r.matchRegularPrice, 299000);
  });

  test('이상한 사진 주소·0원은 버린다', () {
    final r = TagIdentifyResult.fromJson({
      'status': 'found',
      'matchUrl': 'https://x.com/p/1',
      'matchName': '후디',
      'matchPrice': 0,
      'matchImage': 'javascript:alert(1)',
    });
    expect(r.matchPrice, isNull);
    expect(r.matchImage, isNull);
    expect(r.hasMatchDetails, isFalse);
  });

  test('태그 정보만으로 만든 이름 — 상품명이 없으면 품번을 넣는다', () {
    const noName = TagIdentifyResult(
      status: TagIdentifyStatus.notFound,
      brand: 'BEAKER',
      productCode: 'QQ6X39EP20',
    );
    expect(noName.tagOnlyName, 'BEAKER QQ6X39EP20');
    const withName = TagIdentifyResult(
      status: TagIdentifyStatus.notFound,
      brand: 'NIKE',
      productName: '에어 포스 1',
      productCode: 'DV1234-100',
    );
    expect(withName.tagOnlyName, 'NIKE 에어 포스 1 (DV1234-100)');
  });

  test('found인데 URL이 없으면 못 찾은 것으로 본다', () {
    final r = TagIdentifyResult.fromJson({'status': 'found', 'matchUrl': ''});
    expect(r.status, TagIdentifyStatus.notFound);
  });

  test('태그가 아닌 사진', () {
    final r = TagIdentifyResult.fromJson({'status': 'not_a_tag'});
    expect(r.status, TagIdentifyStatus.notATag);
    expect(r.suggestedName, '');
  });

  test('이름으로만 찾은 경우 사용자 확인이 필요하다', () {
    final r = TagIdentifyResult.fromJson({
      'status': 'found',
      'matchUrl': 'https://www.musinsa.com/products/1',
      'matchSource': 'mall',
      'verifiedBy': 'name',
    });
    expect(r.foundOnOfficialSite, isFalse);
    expect(r.needsUserCheck, isTrue);
  });

  test('빈 사진은 서버로 보내지 않는다', () async {
    final runner = _FakeRunner({});
    final store = AwsProductTagStore(runner: runner);
    expect(
      () => store.identify(Uint8List(0), 'image/jpeg'),
      throwsArgumentError,
    );
    expect(runner.lastDocument, isNull);
  });

  test('태그 사진 주소는 친구에게 보내는 JSON(살까말까)에 들어가지 않는다', () {
    final p = Product(
      id: 1,
      listId: 'a',
      name: '니트',
      price: 1000,
      image: '',
      platform: '',
      tagImageUrl: 'https://cdn/tag-photos/me/x.jpg',
    );
    expect(p.toJson().containsKey('tagImageUrl'), isFalse);
    expect(p.copyWith(price: 2000).tagImageUrl, 'https://cdn/tag-photos/me/x.jpg');
  });
}
