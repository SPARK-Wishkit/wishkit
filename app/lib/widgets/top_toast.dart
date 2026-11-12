import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/diary_theme.dart';

/// 앱 전체 안내 문구는 화면 가운데에 반투명 카드로 잠깐 띄운다.
///
/// 화면 아래는 탭 바·"공유하기" 같은 버튼·+ 버튼이 늘 있어서, 예전
/// SnackBar(아래쪽)는 다음에 누를 버튼을 가렸고, 위쪽은 제목을 가려 어색했다.
/// 가운데 안내는
/// - 1.8초(에러는 3.5초) 보였다가 사라지고,
/// - 화면을 어둡게 덮지 않고, 터치도 막지 않아 뒤 화면이 그대로 눌리며,
/// - 새 안내가 오면 이전 것을 바꿔 끼운다.
///
/// 비동기 작업 전에 미리 잡아 둬야 하면 [TopToast.of] 로 받아 두고 나중에 [TopToast.show].
void showTopToast(
  BuildContext context,
  String message, {
  bool error = false,
  IconData? icon,
  Duration? duration,
}) {
  TopToast.of(context).show(
    message,
    error: error,
    icon: icon,
    duration: duration,
  );
}

/// 에러를 안내 문구로: 'Exception: ' 접두어를 떼고 4초 동안 보여 준다.
void showTopError(BuildContext context, Object error, {String prefix = ''}) {
  showTopToast(
    context,
    '$prefix${error.toString().replaceFirst('Exception: ', '')}',
    error: true,
  );
}

class TopToast {
  TopToast._(this._overlay);

  /// 앱 맨 위 오버레이를 잡아 둔다. 화면을 옮겨 가도 안내는 그대로 보인다.
  factory TopToast.of(BuildContext context) =>
      TopToast._(Overlay.of(context, rootOverlay: true));

  final OverlayState _overlay;

  static OverlayEntry? _current;
  static GlobalKey<_ToastViewState>? _currentKey;

  void show(
    String message, {
    bool error = false,
    IconData? icon,
    Duration? duration,
  }) {
    if (!_overlay.mounted) return;
    hideNow();
    final key = GlobalKey<_ToastViewState>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        key: key,
        message: message,
        error: error,
        icon: icon ?? (error ? Icons.error_outline : null),
        duration: duration ??
            (error
                ? const Duration(milliseconds: 3500)
                : const Duration(milliseconds: 1800)),
        onDone: () {
          if (_current == entry) {
            _current = null;
            _currentKey = null;
          }
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    _currentKey = key;
    _overlay.insert(entry);
  }

  /// 떠 있는 안내를 애니메이션 없이 바로 지운다.
  static void hideNow() {
    final old = _current;
    _current = null;
    _currentKey = null;
    if (old != null && old.mounted) old.remove();
  }

  /// 떠 있는 안내를 서서히 닫는다.
  static void hide() => _currentKey?.currentState?._dismiss();
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    super.key,
    required this.message,
    required this.error,
    required this.icon,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final bool error;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _scale = Tween(
    begin: 0.92,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _anim.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _anim.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // 보통 문구("1명의 친구에게 살까말까를 보냈어요" 등)는 한 줄에 들어가게
    // 화면 폭에서 양옆 24씩만 빼고 넓게 쓴다. 아주 긴 안내·에러만 줄바꿈된다.
    final maxWidth = MediaQuery.sizeOf(context).width - 48;
    final card = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      // 뒤 화면을 살짝 흐리게(blur) 해서, 카드를 더 투명하게 해도 글자가 잘 읽히게 한다.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // 짙은 회색(#2B2B2B) 50% + 뒤 흐림 — 뒤 화면이 잘 비치는 정도.
              // 더 투명하게: alpha 를 낮추기 / 더 진하게: 높이기.
              color: const Color(0xFF2B2B2B).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: Colors.white, size: 28),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: DiaryTheme.ui(14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 화면 전체를 덮지만 터치는 통과시킨다(IgnorePointer). 카드만 보이고 배경은 그대로.
    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Semantics(
                liveRegion: true,
                container: true,
                // Material 이 있어야 글자에 기본 밑줄 같은 스타일이 섞이지 않는다.
                child: Material(
                  type: MaterialType.transparency,
                  child: FadeTransition(
                    opacity: _anim,
                    child: reduceMotion
                        ? card
                        : ScaleTransition(scale: _scale, child: card),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
