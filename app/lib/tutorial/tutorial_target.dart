import 'package:flutter/widgets.dart';

/// 튜토리얼이 강조할 위젯의 위치를 찾기 위한 등록부.
///
/// 전역 `static GlobalKey` 를 화면마다 두면, 로그아웃 후 다시 로그인할 때처럼 같은 화면이
/// 잠깐 두 개 생기는 순간에 "Duplicate GlobalKey" 오류가 날 수 있다. 그래서 [TutorialTarget]
/// 위젯이 자기 키를 직접 만들고, 화면에 있는 동안만 이름표(id)로 여기에 등록한다.
class TutorialRegistry {
  TutorialRegistry._();

  static final Map<String, GlobalKey> _keys = {};

  static void register(String id, GlobalKey key) => _keys[id] = key;

  static void unregister(String id, GlobalKey key) {
    if (identical(_keys[id], key)) _keys.remove(id);
  }

  static GlobalKey? keyFor(String id) => _keys[id];

  /// 테스트용: 등록부 비우기.
  static void clearForTest() => _keys.clear();
}

/// 감싼 위젯을 튜토리얼 강조 대상으로 등록한다. 모양과 동작은 그대로다.
///
/// [enabled] 가 false 이면 등록만 하지 않는다(예: 목록에서 첫 번째 카드만 대상으로 할 때).
class TutorialTarget extends StatefulWidget {
  const TutorialTarget({
    super.key,
    required this.id,
    required this.child,
    this.enabled = true,
  });

  final String id;
  final bool enabled;
  final Widget child;

  @override
  State<TutorialTarget> createState() => _TutorialTargetState();
}

class _TutorialTargetState extends State<TutorialTarget> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.enabled) TutorialRegistry.register(widget.id, _key);
  }

  @override
  void didUpdateWidget(TutorialTarget old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.enabled != widget.enabled) {
      if (old.enabled) TutorialRegistry.unregister(old.id, _key);
      if (widget.enabled) TutorialRegistry.register(widget.id, _key);
    }
  }

  @override
  void dispose() {
    if (widget.enabled) TutorialRegistry.unregister(widget.id, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}
