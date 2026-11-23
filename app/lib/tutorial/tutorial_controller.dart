import 'dart:async';

import 'package:flutter/material.dart' show Material;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/diary_scale.dart';
import 'tutorial_content.dart';
import 'tutorial_target.dart';

/// 첫 방문 튜토리얼의 진행 상태와 '봤음' 기록.
///
/// - 한 번에 한 튜토리얼만 보여 준다.
/// - '봤음'은 `shared_preferences` 에만 저장한다(기기마다 한 번, 계정별로 나누지 않음).
/// - 화면 위치를 못 찾는 단계는 조용히 건너뛴다.
class TutorialController extends ChangeNotifier {
  TutorialController({
    this.rectResolver,
  });

  /// 테스트용: 강조 대상의 화면 위치를 직접 정해 준다. null 이면 실제 위젯에서 계산한다.
  final Future<Rect?> Function(String targetId)? rectResolver;

  /// 하단 탭 하단 바 높이(디자인 기준 64) — 이 아래에 가려진 대상은 보이지 않는 것으로 본다.
  static const double _navBarHeight = 64;

  SharedPreferences? _prefs;
  Future<SharedPreferences> _p() async =>
      _prefs ??= await SharedPreferences.getInstance();

  TutorialDef? _def;
  List<TutorialStep> _steps = const [];
  int _index = -1; // -1: 아직 첫 단계를 준비하는 중(화면에 안 보임)
  Rect? _rect; // 화면(전역) 좌표
  bool _emptyMode = false; // 살까말까 '먼저 상품을 담아 주세요' 상자
  bool _shownAny = false;
  bool _busy = false;
  int _session = 0;
  bool _evaluating = false;

  final Set<String> _attempted = {};
  int? _attemptTab;

  /// HomeShell 이 연결하는 동작들.
  void Function(int innerTab)? onSelectFriendsInnerTab;
  VoidCallback? onGoWishkit;

  // ── 화면이 읽는 값 ──────────────────────────────────────────

  /// 튜토리얼이 진행 중(준비 중 포함)인가. 뒤로가기를 가로챌지 정할 때 쓴다.
  bool get isActive => _def != null || _emptyMode;

  /// 지금 화면에 어두운 배경과 상자를 그려야 하나.
  bool get isShowing => isActive && _index >= 0;

  TutorialStep? get step {
    if (!isShowing) return null;
    if (_emptyMode) return kTutSallkaEmptyStep;
    return _steps[_index];
  }

  int get stepNumber => _index + 1;
  int get stepCount => _steps.length;
  bool get isLastStep => _emptyMode || _index >= _steps.length - 1;
  bool get isEmptyMode => _emptyMode;

  /// 강조할 영역(전역 좌표). 가운데 상자 단계에서는 null.
  Rect? get targetRect => _rect;

  /// 지금 진행 중인 튜토리얼이 뜨는 하단 탭.
  int? get activeTab => _def?.tab;

  // ── '봤음' 기록 ─────────────────────────────────────────────

  Future<bool> hasSeen(String key) async =>
      (await _p()).getBool(tutorialSeenKey(key)) ?? false;

  Future<void> _markSeen(TutorialDef def) async {
    final prefs = await _p();
    await prefs.setBool(tutorialSeenKey(def.key), true);
    await prefs.setInt(tutorialVerKey(def.key), kTutorialVersion);
    await prefs.setInt(kTutorialVersionKey, kTutorialVersion);
  }

  /// 마이페이지 '사용 가이드 다시 보기': 모든 '봤음' 기록을 지운다.
  /// 바로 띄우지는 않고, 각 탭에 들어갈 때 다시 뜬다.
  Future<void> resetAll() async {
    final prefs = await _p();
    for (final k in prefs.getKeys().toList()) {
      if (k.startsWith(kTutorialSeenPrefix) || k.startsWith(kTutorialVerPrefix)) {
        await prefs.remove(k);
      }
    }
    // 지금 보고 있는 탭에서는 바로 띄우지 않는다. 다른 탭에 갔다가 다시 들어올 때 뜬다.
    final here = _attemptTab;
    _attempted.clear();
    if (here != null) {
      _attempted.addAll(kTutorials.where((d) => d.tab == here).map((d) => d.key));
    }
    _close();
  }

  // ── 띄우기 ──────────────────────────────────────────────────

  /// 지금 [tab] 이 보이고 [facts] 상태일 때 띄울 튜토리얼이 있으면 띄운다.
  /// 화면이 다 그려진 뒤에 부른다.
  Future<void> evaluate({
    required int tab,
    required TutorialFacts facts,
  }) async {
    if (isActive || _evaluating) return;
    _evaluating = true;
    try {
      final prefs = await _p();
      if (isActive) return;
      if (_attemptTab != tab) {
        _attempted.clear();
        _attemptTab = tab;
      }
      for (final def in kTutorials) {
        if (def.tab != tab) continue;
        if (_attempted.contains(def.key)) continue;
        if (def.requires != null && !def.requires!(facts)) continue;

        final seen = prefs.getBool(tutorialSeenKey(def.key)) ?? false;
        final seenVer = seen ? (prefs.getInt(tutorialVerKey(def.key)) ?? 1) : 0;

        // 살까말까: 내 wishkit 에 상품이 없으면 원래 튜토리얼 대신 안내 상자 하나.
        if (identical(def, kTutSallkaTab) && !facts.hasProducts) {
          final unseenSteps = def.steps.any((s) => s.sinceVersion > seenVer);
          if (!unseenSteps) continue;
          _attempted.add(def.key);
          _emptyMode = true;
          _def = null;
          _steps = const [];
          _index = 0;
          _rect = null;
          _shownAny = true;
          _session++;
          notifyListeners();
          return;
        }

        final steps = def.steps
            .where((s) =>
                s.sinceVersion > seenVer && (s.enabledWhen?.call(facts) ?? true))
            .toList();
        if (steps.isEmpty) continue;

        _attempted.add(def.key);
        _def = def;
        _steps = steps;
        _index = -1;
        _rect = null;
        _emptyMode = false;
        _shownAny = false;
        _session++;
        await _showFrom(0);
        return;
      }
    } finally {
      _evaluating = false;
    }
  }

  /// [from] 번째 단계부터, 강조 대상을 찾을 수 있는 첫 단계를 보여 준다.
  Future<void> _showFrom(int from) async {
    final session = _session;
    _busy = true;
    try {
      for (var k = from; k < _steps.length; k++) {
        final s = _steps[k];
        if (s.friendsInnerTab != null) {
          onSelectFriendsInnerTab?.call(s.friendsInnerTab!);
        }
        Rect? rect;
        if (s.target != null) {
          rect = await _resolveRect(s.target!, innerMaterial: s.holeToInnerMaterial);
          if (session != _session) return; // 그 사이 닫혔다
          if (rect == null) continue; // 위치를 못 찾으면 조용히 건너뛴다
        }
        _index = k;
        _rect = rect;
        _shownAny = true;
        notifyListeners();
        return;
      }
      if (session != _session) return;
      // 더 보여 줄 단계가 없다.
      await _finish(markSeen: _shownAny);
    } finally {
      _busy = false;
    }
  }

  // ── 사용자 동작 ─────────────────────────────────────────────

  /// "다음"/"완료" 버튼, 어두운 배경 누르기.
  Future<void> next() async {
    if (!isShowing || _busy) return;
    if (_emptyMode) {
      _close(); // '봤음' 기록 없음
      return;
    }
    if (_index >= _steps.length - 1) {
      await _finish(markSeen: true);
    } else {
      await _showFrom(_index + 1);
    }
  }

  /// "건너뛰기", Android 뒤로가기. '봤음'으로 기록한다.
  Future<void> skip() async {
    if (!isActive) return;
    if (_emptyMode) {
      _close();
      return;
    }
    await _finish(markSeen: true);
  }

  /// 안내 상자 '위시킷으로 가기' 버튼.
  void goToWishkit() {
    _close(); // 상품을 담은 뒤 다시 들어오면 원래 튜토리얼이 뜨도록 '봤음' 기록 없음
    onGoWishkit?.call();
  }

  /// 튜토리얼이 떠 있는 상태에서 하단 탭이 바뀌었다.
  Future<void> onTabChanged(int newTab) async {
    if (!isActive) return;
    if (_emptyMode) {
      _close();
      return;
    }
    if (_def != null && _def!.tab != newTab) {
      await _finish(markSeen: true);
    }
  }

  // ── 내부 ────────────────────────────────────────────────────

  Future<void> _finish({required bool markSeen}) async {
    final def = _def;
    if (def != null && markSeen) await _markSeen(def);
    _close();
  }

  void _close() {
    _session++;
    _def = null;
    _steps = const [];
    _index = -1;
    _rect = null;
    _emptyMode = false;
    _shownAny = false;
    notifyListeners();
  }

  /// 튜토리얼이 떠 있는 동안 강조 대상의 위치가 바뀌면(스크롤·애니메이션·레이아웃 변화) 따라간다.
  void refreshRect() {
    final id = step?.target;
    if (!isShowing || _emptyMode || id == null || rectResolver != null) return;
    final ctx = TutorialRegistry.keyFor(id)?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final r = _globalRect(ctx, innerMaterial: step?.holeToInnerMaterial ?? false);
    if (r == null) return;
    final old = _rect;
    if (old == null ||
        (old.left - r.left).abs() > 0.5 ||
        (old.top - r.top).abs() > 0.5 ||
        (old.right - r.right).abs() > 0.5 ||
        (old.bottom - r.bottom).abs() > 0.5) {
      _rect = r;
      notifyListeners();
    }
  }

  Future<void> _nextFrame() => WidgetsBinding.instance.endOfFrame;

  /// 강조 대상의 화면 위치. 없거나 화면 밖이면 null.
  Future<Rect?> _resolveRect(String id, {bool innerMaterial = false}) async {
    final resolver = rectResolver;
    if (resolver != null) return resolver(id);

    for (var attempt = 0; attempt < 4; attempt++) {
      await _nextFrame();
      final ctx = TutorialRegistry.keyFor(id)?.currentContext;
      if (ctx != null && ctx.mounted) {
        try {
          // 스크롤 목록 안에 있으면 화면 안으로 가져온다.
          await Scrollable.ensureVisible(
            ctx,
            alignment: 0.35,
            duration: Duration.zero,
          );
        } catch (_) {}
        await _nextFrame();
        if (!ctx.mounted) continue;
        final rect = _globalRect(ctx, innerMaterial: innerMaterial);
        if (rect != null && _isVisible(rect)) return rect;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return null;
  }

  /// 버튼 같은 위젯은 터치 영역이 눈에 보이는 몸통보다 크다. 안쪽 Material 의 크기를 찾는다.
  RenderBox? _innerMaterialBox(BuildContext ctx) {
    RenderBox? found;
    void visit(Element e) {
      if (found != null) return;
      if (e.widget is Material) {
        final ro = e.renderObject;
        if (ro is RenderBox && ro.attached && ro.hasSize) {
          found = ro;
          return;
        }
      }
      e.visitChildren(visit);
    }

    (ctx as Element).visitChildren(visit);
    return found;
  }

  Rect? _globalRect(BuildContext ctx, {bool innerMaterial = false}) {
    try {
      var ro = ctx.findRenderObject();
      if (innerMaterial) ro = _innerMaterialBox(ctx) ?? ro;
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
      // 앱 전체가 DiaryScale 로 확대·축소돼서 size 만 쓰면 어긋난다. 네 모서리를 화면 좌표로 바꿔 계산한다.
      final r = MatrixUtils.transformRect(
        ro.getTransformTo(null),
        Offset.zero & ro.size,
      );
      if (r.width <= 0 || r.height <= 0) return null;
      return r;
    } catch (_) {
      return null;
    }
  }

  bool _isVisible(Rect r) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return true;
    final view = views.first;
    final dpr = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
    final size = view.physicalSize / dpr;
    final factor = DiaryScale.factorForSize(size);
    final bottomLimit =
        size.height - _navBarHeight * factor - view.padding.bottom / dpr;
    return r.bottom > 0 &&
        r.top < bottomLimit &&
        r.right > 0 &&
        r.left < size.width;
  }
}
