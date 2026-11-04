import 'package:figmadesign/theme/diary_scale.dart';
import 'package:figmadesign/widgets/diary_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('factorForWidth matches the 390pt design on common phones', () {
    expect(DiaryScale.factorForWidth(390), 1);
    expect(DiaryScale.factorForWidth(320), closeTo(320 / 390, 0.0001));
    expect(DiaryScale.factorForWidth(430), closeTo(430 / 390, 0.0001));
  });

  test('factorForWidth clamps tablets instead of billboard-scaling', () {
    expect(DiaryScale.factorForWidth(1024), DiaryScale.maxFactor);
    expect(DiaryScale.factorForWidth(0), 1);
  });

  test('scaleInsets converts device padding into design pixels', () {
    const insets = EdgeInsets.fromLTRB(10, 47, 10, 34);
    final scaled = DiaryScale.scaleInsets(insets, 0.8);
    expect(scaled.left, 12.5);
    expect(scaled.top, closeTo(58.75, 0.001));
    expect(scaled.bottom, 42.5);
  });

  test('factorForSize shrinks short phones but leaves tall phones as before',
      () {
    // iPhone 14 (design) / 14 Pro Max / mini: same as the width ratio.
    expect(DiaryScale.factorForSize(const Size(390, 844)), 1);
    expect(
      DiaryScale.factorForSize(const Size(430, 932)),
      closeTo(430 / 390, 0.01),
    );
    expect(
      DiaryScale.factorForSize(const Size(375, 812)),
      closeTo(375 / 390, 0.01),
    );
    // iPhone SE: almost design width but much shorter → noticeably smaller.
    final se = DiaryScale.factorForSize(const Size(375, 667));
    expect(se, lessThan(0.9));
    expect(se, greaterThanOrEqualTo(DiaryScale.minFactor));
  });

  testWidgets('wrap fills a short phone edge to edge at the scaled size',
      (tester) async {
    const phone = Size(375, 667); // iPhone SE
    await tester.binding.setSurfaceSize(phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late Size innerSize;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            DiaryScale.wrap(context, child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (context) {
            innerSize = MediaQuery.sizeOf(context);
            return const SizedBox.expand();
          },
        ),
      ),
    );

    final factor = DiaryScale.factorForSize(phone);
    expect(innerSize.width, closeTo(phone.width / factor, 0.5));
    expect(innerSize.height, closeTo(phone.height / factor, 0.5));
    // Laid out wider than the design, so everything renders smaller.
    expect(innerSize.width, greaterThan(DiaryScale.designWidth));
  });

  testWidgets('OneLineText does not wrap in a narrow box', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 72,
            child: OneLineText(
              '마이페이지',
              style: TextStyle(fontSize: 16, height: 1),
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('마이페이지'));
    expect(text.maxLines, 1);
    expect(tester.getSize(find.text('마이페이지')).height, lessThan(24));
  });
}
