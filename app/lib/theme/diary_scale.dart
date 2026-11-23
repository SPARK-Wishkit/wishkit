import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lays the app out at a 390×844pt design screen (iPhone 14), then scales the
/// whole tree to the real phone.
///
/// The factor looks at the height too (2026-11): phones like the iPhone SE are
/// almost as wide as the design (375pt) but much shorter (667pt), so a
/// width-only factor barely shrank anything and screens felt oversized. We use
/// the geometric mean of the width and height ratios (never more than the width
/// ratio), so short phones shrink in proportion and tall phones are unchanged.
///
/// Flutter does not preserve design ratios by default: font sizes and paddings
/// are logical pixels, so a label that fits on 390pt wraps on 320pt. Scaling
/// the full layout (not just text) keeps spacing, type, and chrome in the
/// same proportion on every phone.
class DiaryScale {
  static const designWidth = 390.0;
  static const designHeight = 844.0;

  /// Smallest phone we still shrink to match (iPhone SE).
  static const minFactor = 0.80;

  /// Largest scale before wide phones / tablets stop stretching.
  static const maxFactor = 1.15;

  static const maxUserTextScale = 1.2;

  static double factorForWidth(double width) {
    if (width <= 0) return 1;
    return (width / designWidth).clamp(minFactor, maxFactor);
  }

  /// Width ratio, pulled down on screens shorter than the design.
  static double factorForSize(Size size) {
    if (size.width <= 0 || size.height <= 0) return 1;
    final w = size.width / designWidth;
    final h = size.height / designHeight;
    final blended = math.sqrt(w * h);
    return math.min(w, blended).clamp(minFactor, maxFactor);
  }

  static double of(BuildContext context) =>
      factorForSize(MediaQuery.sizeOf(context));

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

        final factor = factorForSize(Size(maxW, maxH));
        // Lay out at real size ÷ factor so the scaled tree fills the screen
        // edge to edge (a height-driven factor would otherwise leave side gaps).
        final virtualWidth = maxW / factor;
        final virtualHeight = maxH / factor;
        final userScale =
            mq.textScaler.scale(1).clamp(1.0, maxUserTextScale);

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: maxW,
            height: maxH,
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: virtualWidth,
                height: virtualHeight,
                child: MediaQuery(
                  data: mq.copyWith(
                    size: Size(virtualWidth, virtualHeight),
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
          ),
        );
      },
    );
  }
}
