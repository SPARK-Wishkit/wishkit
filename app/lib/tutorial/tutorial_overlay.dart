import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/diary_theme.dart';
import 'tutorial_content.dart';
import 'tutorial_controller.dart';

/// 어두운 배경 + (강조 위젯만 어둡지 않게 뚫은 구멍) + 흰 설명 상자.
///
/// - 구멍은 강조할 위젯과 똑같은 크기·모양이다. 새 테두리나 네모를 그리지 않는다.
/// - 이 위젯이 덮은 영역의 터치는 전부 여기서 받는다(강조한 버튼도 실제로는 눌리지 않는다).
///   어두운 배경을 누르면 다음 단계로 넘어간다.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.controller});

  final TutorialController controller;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  final GlobalKey _areaKey = GlobalKey();
  late final Ticker _ticker;

  static const double _boxGap = 12; // 강조 위젯과 설명 상자 사이
  static const double _tailH = 8;
  static const double _margin = 16;
  static const double _boxRadius = 18;

  @override
  void initState() {
    super.initState();
    // 강조 대상이 움직이거나 크기가 바뀌면 구멍이 따라가도록 매 프레임 위치를 다시 읽는다.
    _ticker = createTicker((_) => widget.controller.refreshRect())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// 대상의 화면(전역) 좌표를 이 위젯 안쪽 좌표로 바꾼다.
  /// 앱 전체가 DiaryScale 로 확대·축소되어 있어서 전역 좌표를 그대로 쓰면 어긋난다.
  Rect? _toLocal(Rect? global) {
    if (global == null) return null;
    final ro = _areaKey.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return null;
    }
    return Rect.fromPoints(
      ro.globalToLocal(global.topLeft),
      ro.globalToLocal(global.bottomRight),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final step = c.step;
    if (step == null) return const SizedBox.shrink();

    // Scaffold 밖에 얹히는 위젯이라 Material 이 없으면 글자에 노란 밑줄이 생긴다.
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        key: _areaKey,
        behavior: HitTestBehavior.opaque,
        onTap: c.next,
        child: LayoutBuilder(
          builder: (context, cons) {
            final size = cons.biggest;
            final hasTarget = step.target != null && !c.isEmptyMode;
            var hole = hasTarget ? _toLocal(c.targetRect) : null;
            if (hole != null && step.holeFullWidth) {
              hole = Rect.fromLTRB(0, hole.top, size.width, hole.bottom);
            }
            if (hole != null && step.holeInsets != EdgeInsets.zero) {
              final i = step.holeInsets;
              hole = Rect.fromLTRB(
                hole.left + i.left,
                hole.top + i.top,
                hole.right - i.right,
                hole.bottom - i.bottom,
              );
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScrimPainter(
                      hole: hole,
                      radius: step.holeRadius ?? DiaryTheme.radius,
                      topOnly: step.holeTopOnly,
                    ),
                  ),
                ),
                if (!hasTarget)
                  Center(child: _centerBox(step))
                else if (hole != null)
                  _anchoredBox(step, hole, size),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── 설명 상자 ────────────────────────────────────────────────

  Widget _centerBox(TutorialStep step) {
    return _absorb(
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _margin),
          child: _BoxCard(child: _boxContent(step, withImage: true)),
        ),
      ),
    );
  }

  Widget _anchoredBox(TutorialStep step, Rect hole, Size size) {
    final above = hole.top;
    final below = size.height - hole.bottom;
    final placeBelow = switch (step.boxPlacement) {
      TutorialBoxPlacement.below => true,
      TutorialBoxPlacement.above => false,
      TutorialBoxPlacement.auto => below >= above,
    };
    final width = (size.width - _margin * 2).clamp(0.0, 340.0);
    final left = (hole.center.dx - width / 2).clamp(
      _margin,
      (size.width - width - _margin).clamp(_margin, double.infinity),
    );
    final tailX = (hole.center.dx - left).clamp(28.0, width - 28);

    final card = _absorb(
      SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (placeBelow) _Tail(x: tailX, up: true),
            _BoxCard(child: _boxContent(step)),
            if (!placeBelow) _Tail(x: tailX, up: false),
          ],
        ),
      ),
    );

    // 설명 상자는 강조한 영역을 가리지 않게, 공간이 더 넓은 쪽(위/아래)에 둔다.
    return placeBelow
        ? Positioned(left: left, top: hole.bottom + _boxGap - _tailH, child: card)
        : Positioned(
            left: left,
            bottom: size.height - hole.top + _boxGap - _tailH,
            child: card,
          );
  }

  /// 상자 안을 눌러도 배경 누르기(=다음 단계)로 번지지 않게 한다.
  Widget _absorb(Widget child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: child,
      );

  Widget _boxContent(TutorialStep step, {bool withImage = false}) {
    final c = widget.controller;
    final empty = c.isEmptyMode;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!empty) ...[
          Text(
            '${c.stepNumber} / ${c.stepCount}',
            style: DiaryTheme.ui(
              12,
              color: DiaryColors.inkSoft,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (withImage && step.image != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(DiaryTheme.radius),
            child: Image.asset(
              step.image!,
              width: double.infinity,
              // 그림 비율 그대로(위아래·좌우를 자르지 않는다).
              fit: BoxFit.fitWidth,
              // 실제 그림은 팀이 나중에 교체한다. 파일이 없어도 오류 없이 자리표시자를 보여 준다.
              errorBuilder: (_, __, ___) => Container(
                height: 140,
                width: double.infinity,
                color: DiaryColors.surfaceSoft,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.image_outlined,
                  color: DiaryColors.lineStrong,
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          step.title,
          style: DiaryTheme.ui(18, weight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          step.body,
          style: DiaryTheme.ui(14, color: DiaryColors.inkMuted).copyWith(
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        if (empty)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: _primaryButton,
              onPressed: c.goToWishkit,
              child: const Text(kTutSallkaEmptyButton),
            ),
          )
        else
          Row(
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: DiaryColors.inkSoft,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: c.skip,
                child: Text(
                  kTutorialSkip,
                  style: DiaryTheme.ui(14, weight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              FilledButton(
                style: _primaryButton,
                onPressed: c.next,
                child: Text(c.isLastStep ? kTutorialDone : kTutorialNext),
              ),
            ],
          ),
      ],
    );
  }

  static final ButtonStyle _primaryButton = FilledButton.styleFrom(
    backgroundColor: DiaryColors.ink,
    foregroundColor: DiaryColors.white,
    minimumSize: const Size(88, 42),
    shape: const StadiumBorder(),
    textStyle: DiaryTheme.ui(14, weight: FontWeight.w700),
  );
}

/// 흰 설명 상자.
class _BoxCard extends StatelessWidget {
  const _BoxCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      decoration: BoxDecoration(
        color: DiaryColors.white,
        borderRadius: BorderRadius.circular(_TutorialOverlayState._boxRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 설명 상자가 가리키는 쪽을 알려 주는 작은 꼬리(▲/▼).
class _Tail extends StatelessWidget {
  const _Tail({required this.x, required this.up});

  final double x;
  final bool up;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _TutorialOverlayState._tailH,
      width: double.infinity,
      child: CustomPaint(painter: _TailPainter(x: x, up: up)),
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter({required this.x, required this.up});

  final double x;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    const half = 9.0;
    final path = Path();
    if (up) {
      path
        ..moveTo(x - half, size.height + 1)
        ..lineTo(x, 0)
        ..lineTo(x + half, size.height + 1);
    } else {
      path
        ..moveTo(x - half, -1)
        ..lineTo(x, size.height)
        ..lineTo(x + half, -1);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = DiaryColors.white);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.x != x || old.up != up;
}

/// 화면 전체를 어둡게 칠하되, [hole] 만 위젯 모양 그대로 뚫어 원래 밝기로 보여 준다.
/// (테두리·여백을 따로 그리지 않는다)
class _ScrimPainter extends CustomPainter {
  _ScrimPainter({
    required this.hole,
    required this.radius,
    required this.topOnly,
  });

  final Rect? hole;
  final double radius;
  final bool topOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final scrim = Paint()
      ..color = Colors.black.withValues(alpha: kTutorialScrimOpacity);
    final h = hole;
    if (h == null) {
      canvas.drawPath(full, scrim);
      return;
    }
    final r = Radius.circular(radius);
    final rrect = topOnly
        ? RRect.fromRectAndCorners(h, topLeft: r, topRight: r)
        : RRect.fromRectAndRadius(h, r);
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, Path()..addRRect(rrect)),
      scrim,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.radius != radius || old.topOnly != topOnly;
}
