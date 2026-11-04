import 'package:flutter/material.dart';

import 'diary_theme.dart';

/// Lays the app out at a 390pt design width (iPhone 14), then scales the
/// whole tree to the real phone width.
///
/// Flutter does not preserve design ratios by default: font sizes and paddings
/// are logical pixels, so a label that fits on 390pt wraps on 320pt. Scaling
/// the full layout (not just text) keeps spacing, type, and chrome in the
/// same proportion on every phone.
class DiaryScale {
  static const designWidth = 390.0;

  /// Smallest phone we still shrink to match (iPhone SE).
  static const minFactor = 0.80;

  /// Largest scale before wide phones / tablets stop stretching.
  static const maxFactor = 1.15;

  /// Phone "Text Size" setting is ignored (1.0) so text keeps the same ratio
  /// to cards/tabs on every phone. At 1.2 a larger system font made text wrap,
  /// pushing prices to a new line and making every card taller.
  static const maxUserTextScale = 1.0;

  /// Design height (iPhone 14). Used to size the phone frame on tablets.
  static const designHeight = 844.0;

  /// A screen whose short side is at least this wide is treated as a tablet.
  static const tabletShortestSide = 600.0;

  /// Tablet frame scale range: portrait iPads hit the top (≈1.3×),
  /// landscape iPads fall back to 1.0× (normal phone size).
  static const tabletMinFactor = 1.0;
  static const tabletMaxFactor = 1.3;

  static bool isTablet(Size size) => size.shortestSide >= tabletShortestSide;

  /// Phones: scale by width. Tablets: show the phone layout as a centered
  /// frame sized from the screen height, so it looks like a big phone.
  static double factorFor(Size size) {
    if (size.width <= 0 || size.height <= 0) return 1;
    if (isTablet(size)) {
      final byHeight = (size.height / designHeight)
          .clamp(tabletMinFactor, tabletMaxFactor);
      // Never wider than the screen (e.g. split view).
      return byHeight < size.width / designWidth
          ? byHeight
          : size.width / designWidth;
    }
    final byWidth = factorForWidth(size.width);
    // Below ~312pt the min clamp would make the app wider than the screen.
    return byWidth < size.width / designWidth
        ? byWidth
        : size.width / designWidth;
  }

  static double factorForWidth(double width) {
    if (width <= 0) return 1;
    return (width / designWidth).clamp(minFactor, maxFactor);
  }

  static double of(BuildContext context) =>
      factorFor(MediaQuery.sizeOf(context));

  static EdgeInsets scaleInsets(EdgeInsets insets, double factor) {
    if (factor == 0) return insets;
    return EdgeInsets.fromLTRB(
      insets.left / factor,
      insets.top / factor,
      insets.right / factor,
      insets.bottom / factor,
    );
  }

  static Widget wrap(BuildContext context, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mq = MediaQuery.of(context);
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : mq.size.width;
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : mq.size.height;
        if (maxW <= 0 || maxH <= 0) return child;

        final factor = factorFor(Size(maxW, maxH));
        final virtualHeight = maxH / factor;
        final frameWidth = designWidth * factor;
        // Gray sides + soft shadow only when there is space beside the app
        // (iPad, landscape phone). On a normal phone the frame fills the width.
        final framed = maxW - frameWidth > 1;
        final userScale =
            mq.textScaler.scale(1).clamp(1.0, maxUserTextScale);

        final scaled = SizedBox(
            width: frameWidth,
            height: maxH,
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: designWidth,
                height: virtualHeight,
                child: MediaQuery(
                  data: mq.copyWith(
                    size: Size(designWidth, virtualHeight),
                    padding: scaleInsets(mq.padding, factor),
                    viewPadding: scaleInsets(mq.viewPadding, factor),
                    viewInsets: scaleInsets(mq.viewInsets, factor),
                    systemGestureInsets:
                        scaleInsets(mq.systemGestureInsets, factor),
                    textScaler: TextScaler.linear(userScale),
                  ),
                  child: child,
                ),
              ),
            ),
          );

        if (!framed) {
          return Align(alignment: Alignment.topCenter, child: scaled);
        }
        return ColoredBox(
          // A shade darker than the app's own gray so the frame edge reads.
          color: DiaryColors.tabIdle,
          child: Center(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRect(child: scaled),
            ),
          ),
        );
      },
    );
  }
}
