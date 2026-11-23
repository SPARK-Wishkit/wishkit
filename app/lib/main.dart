import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'ads/ads_consent.dart';
import 'auth/amplify_setup.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_routes.dart';
import 'auth/cognito_auth_service.dart';
import 'data/app_store.dart';
import 'services/push_notification_service.dart';
import 'screens/friends/friends_screen.dart';
import 'screens/friends/notifications_screen.dart';
import 'screens/mypage/blocked_users_screen.dart';
import 'screens/mypage/follow_list_screen.dart';
import 'screens/mypage/mypage_screen.dart';
import 'screens/mypage/sent_baskets_screen.dart';
import 'screens/product/product_detail_screen.dart';
import 'screens/salkamalka/salkamalka_screen.dart';
import 'screens/share/share_intake_screen.dart';
import 'screens/shared/shared_basket_detail_screen.dart';
import 'screens/shared/shared_wishlist_screen.dart';
import 'screens/wishlist/wishlist_screen.dart';
import 'services/share_input.dart';
import 'theme/diary_scale.dart';
import 'theme/diary_theme.dart';
import 'tutorial/tutorial_content.dart';
import 'tutorial/tutorial_controller.dart';
import 'tutorial/tutorial_overlay.dart';
import 'widgets/diary_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) AWS(Amplify) 연결: 로그인 · 데이터 · 파일
  final amplifyError = await configureAmplify();

  // 2) 앱 안 알림 배너 준비 (푸시는 5단계에서)
  await PushNotificationService.instance.init();

  // 3) 저장된 로그인 복구 → 그다음 앱 데이터 준비 (순서 중요)
  final auth = AuthController(service: CognitoAuthService());
  await auth.init();
  final store = AppStore(auth: auth, backendConfigured: amplifyError == null);
  auth.hooks = store.authHooks;
  await store.init();

  // 4) 광고 SDK 준비는 첫 화면이 뜬 뒤 ATT(광고 추적 동의) 팝업 다음에 한다 → _WishlistAppState.initState

  runApp(WishlistApp(auth: auth, store: store));
}

class WishlistApp extends StatefulWidget {
  const WishlistApp({super.key, required this.auth, required this.store});

  final AuthController auth;
  final AppStore store;

  @override
  State<WishlistApp> createState() => _WishlistAppState();
}

class _WishlistAppState extends State<WishlistApp> {
  static const _nativeShareChannel = MethodChannel(
    'com.softstudio.wishlist/share',
  );

  late final GoRouter router;
  StreamSubscription? _shareSub;
  String? _lastHandledShareUrl;
  DateTime? _lastHandledShareAt;

  @override
  void initState() {
    super.initState();
    router = _buildRouter(widget.auth, widget.store);
    _listenNativeShareText();
    PushNotificationService.instance.onBannerTap = () {
      router.go('/notifications');
    };
    _listenShares();
    // 광고 추적 동의(ATT) → 광고 SDK 시작. iOS는 앱 화면이 떠 있어야 팝업을 띄운다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(AdsConsent.start());
    });
  }

  void _listenNativeShareText() {
    _nativeShareChannel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') {
        _handleSharedText(call.arguments as String?);
      }
    });
    _nativeShareChannel
        .invokeMethod<String>('takePendingShareText')
        .then(_handleSharedText, onError: (_) {});
  }

  void _listenShares() {
    // App already running
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedMedia,
      onError: (_) {},
    );

    // App launched by share
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handleSharedMedia(files);
      // Do not replay the same cold-start share on the next app launch.
      ReceiveSharingIntent.instance.reset();
    }, onError: (_) {});
  }

  void _handleSharedMedia(List<SharedMediaFile> files) {
    final candidates = files.expand<String?>((file) {
      // Some senders attach a URL as the message of an image share, while
      // text-only senders place the complete shared text in `path`.
      return [file.message, file.path];
    });
    final input = ShareInput.fromCandidates(candidates);
    _handleSharedText(input);
  }

  void _handleSharedText(String? sharedText) {
    final input = ShareInput.fromCandidates([sharedText]);
    if (input == null) return;

    final url = ShareInput.firstUrl(input)!;
    final now = DateTime.now();
    final isImmediateDuplicate =
        url == _lastHandledShareUrl &&
        _lastHandledShareAt != null &&
        now.difference(_lastHandledShareAt!) < const Duration(seconds: 2);
    if (isImmediateDuplicate) return;

    _lastHandledShareUrl = url;
    _lastHandledShareAt = now;
    widget.store.setPendingShareUrl(ShareInput.normalize(input));
    router.go('/share');
  }

  @override
  void dispose() {
    _nativeShareChannel.setMethodCallHandler(null);
    PushNotificationService.instance.onBannerTap = null;
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.auth),
        ChangeNotifierProvider.value(value: widget.store),
        // 탭별 첫 방문 튜토리얼 진행 상태 (lib/tutorial/)
        ChangeNotifierProvider(create: (_) => TutorialController()),
      ],
      child: MaterialApp.router(
        title: 'wishkit',
        debugShowCheckedModeBanner: false,
        theme: DiaryTheme.light,
        routerConfig: router,
        builder: (context, child) =>
            DiaryScale.wrap(context, child ?? const SizedBox.shrink()),
      ),
    );
  }
}

GoRouter _buildRouter(AuthController auth, AppStore store) {
  return GoRouter(
    initialLocation: authInitialLocation(auth),
    refreshListenable: Listenable.merge([auth, store]),
    redirect: (context, state) => authRedirect(auth, state),
    // 다른 화면에서 홈으로 돌아왔을 때 튜토리얼을 다시 확인하려고(HomeShell 참고).
    observers: [tutorialRouteObserver],
    routes: [
      // /login, /verify-email, /account-recovery, /welcome
      ...authRoutes,
      GoRoute(
        path: '/share',
        builder: (context, state) =>
            ShareIntakeScreen(sharedUrl: state.uri.queryParameters['url']),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) => ProductDetailScreen(
          productId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/catalog-product/:id',
        builder: (context, state) => ProductDetailScreen(
          productId: int.parse(state.pathParameters['id']!),
          friendWishlistId: state.uri.queryParameters['wishlist'],
          sharedBasketId: state.uri.queryParameters['basket'],
          friendId: state.uri.queryParameters['friend'],
        ),
      ),
      GoRoute(
        path: '/friend-wishlist/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final store = context.read<AppStore>();
          final list = store.friendWishlistById(id);
          if (list == null) {
            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
              ),
              body: const Center(child: Text('이 wishkit을 찾을 수 없어요')),
            );
          }
          return SharedWishlistScreen(
            // 누구의 무슨 폴더인지: "ella의 shirts"
            title: '${list.friendName}의 ${list.listName}',
            subtitle: '${list.friendName} 님의 공개 wishkit · 상품 ${list.items.length}개',
            products: list.items,
            accentColor: DiaryColors.folderPink,
            wishlistId: list.id,
            safetyUserId: list.friendId,
            friendName: list.friendName,
          );
        },
      ),
      GoRoute(
        path: '/followers',
        builder: (context, state) =>
            const FollowListScreen(kind: FollowListKind.followers),
      ),
      GoRoute(
        path: '/following',
        builder: (context, state) =>
            const FollowListScreen(kind: FollowListKind.following),
      ),
      GoRoute(
        path: '/sent-baskets',
        builder: (context, state) => const SentBasketsScreen(),
      ),
      GoRoute(
        path: '/blocked-users',
        builder: (context, state) => const BlockedUsersScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/friend-salkamalka/:friendId',
        builder: (context, state) {
          final friendId = state.pathParameters['friendId']!;
          final store = context.read<AppStore>();
          final group = store.friendSalkamalkaByFriendId(friendId);
          if (group == null) {
            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
              ),
              body: const Center(child: Text('받은 살까말까를 찾을 수 없어요')),
            );
          }
          return SharedWishlistScreen(
            title: '${group.friendName}의 살까말까',
            subtitle: '${group.friendHandle} · 상품 ${group.itemCount}개',
            products: group.allProducts,
            accentColor: DiaryColors.folderPeach,
            emptyMessage: '보낸 상품이 없어요',
            friendId: friendId,
            safetyUserId: friendId,
            friendName: group.friendName,
          );
        },
      ),
      GoRoute(
        path: '/shared/:id',
        builder: (context, state) => SharedBasketDetailScreen(
          basketId: state.pathParameters['id']!,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HomeShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, __) => const WishlistScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/friends',
                builder: (_, __) => const FriendsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/basket',
                builder: (_, __) => const SalkamalkaScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => const MyPageScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// 하단 탭 하단 바의 디자인 기준 높이(+ 안전 영역). 튜토리얼 배경이 이 아래는 덮지 않는다.
const double _kNavBarHeight = 64;

/// HomeShell 이 있는 화면으로 다른 화면에서 돌아왔는지 알기 위한 관찰자.
final RouteObserver<ModalRoute<void>> tutorialRouteObserver =
    RouteObserver<ModalRoute<void>>();

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with RouteAware {
  late final TutorialController _tutorial;
  late final AppStore _store;
  ModalRoute<void>? _route;
  bool _scheduled = false;
  late int _lastIndex;

  @override
  void initState() {
    super.initState();
    _tutorial = context.read<TutorialController>();
    _store = context.read<AppStore>();
    _lastIndex = widget.navigationShell.currentIndex;
    _tutorial.onSelectFriendsInnerTab = _store.selectFriendsTab;
    _tutorial.onGoWishkit = () => widget.navigationShell.goBranch(0);
    _store.addListener(_scheduleEvaluate);
    _tutorial.addListener(_onTutorialChanged);
    _scheduleEvaluate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      tutorialRouteObserver.unsubscribe(this);
      _route = route;
      tutorialRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(HomeShell old) {
    super.didUpdateWidget(old);
    final index = widget.navigationShell.currentIndex;
    if (index != _lastIndex) {
      _lastIndex = index;
      // 튜토리얼이 떠 있는 채로 탭을 바꾸면 그 튜토리얼은 닫고 '봤음'으로 기록한다.
      _tutorial.onTabChanged(index).then((_) => _scheduleEvaluate());
    }
  }

  // 다른 화면(공유 담기·상품 상세 등)에서 홈으로 돌아왔다.
  @override
  void didPopNext() => _scheduleEvaluate();

  @override
  void dispose() {
    tutorialRouteObserver.unsubscribe(this);
    _store.removeListener(_scheduleEvaluate);
    _tutorial.removeListener(_onTutorialChanged);
    _tutorial.onSelectFriendsInnerTab = null;
    _tutorial.onGoWishkit = null;
    super.dispose();
  }

  void _onTutorialChanged() {
    // 하나가 끝나면 같은 탭에서 이어서 띄울 다음 튜토리얼이 있는지 본다(예: 위시킷 → 첫 상품 카드).
    if (!_tutorial.isActive) _scheduleEvaluate();
  }

  /// 화면이 다 그려진 뒤에 한 번만 확인한다.
  void _scheduleEvaluate() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _evaluate();
    });
  }

  void _evaluate() {
    // 다른 화면이나 시트가 위에 떠 있으면 띄우지 않는다.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (!_store.isLoggedIn) return;
    _tutorial.evaluate(
      tab: widget.navigationShell.currentIndex,
      facts: _facts(_store),
    );
  }

  TutorialFacts _facts(AppStore s) {
    bool following(String friendId) =>
        s.friendById(friendId)?.isFollowing ?? false;
    return TutorialFacts(
      hasProducts: s.products.isNotEmpty,
      hasFollowing: s.friends.any((f) => f.isFollowing),
      hasFriendWishlists:
          s.friendWishlists.any((w) => following(w.friendId)),
      hasSalkaFeed: s.salkamalkaFeed.isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final showWishlistFab = navigationShell.currentIndex == 0;
    final navInset = MediaQuery.paddingOf(context).bottom;

    return ListenableBuilder(
      listenable: _tutorial,
      builder: (context, _) => PopScope(
        // 튜토리얼이 떠 있는 동안 Android 뒤로가기는 "건너뛰기"와 같다.
        canPop: !_tutorial.isActive,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _tutorial.isActive) _tutorial.skip();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Scaffold(
              body: navigationShell,
              bottomNavigationBar: Container(
                decoration: BoxDecoration(
                  color: DiaryColors.white,
                  border: Border(
                    top: BorderSide(color: DiaryColors.ink.withValues(alpha: 0.08)),
                  ),
                ),
                child: SafeArea(
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        _NavItem(
                          index: 0,
                          label: 'wishkit',
                          icon: Icons.star_border,
                          activeIcon: Icons.star,
                          shell: navigationShell,
                        ),
                        _NavItem(
                          index: 1,
                          label: '내 친구',
                          icon: Icons.people_outline,
                          activeIcon: Icons.people,
                          shell: navigationShell,
                        ),
                        _NavItem(
                          index: 2,
                          label: '살까말까',
                          icon: Icons.chat_bubble_outline,
                          activeIcon: Icons.chat_bubble,
                          shell: navigationShell,
                        ),
                        _NavItem(
                          index: 3,
                          label: '마이페이지',
                          icon: Icons.person_outline,
                          activeIcon: Icons.person,
                          shell: navigationShell,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              floatingActionButton: showWishlistFab
                  // 기본 FAB(높이 56)는 목록을 너무 가려서 한 단계 작게(높이 44).
                  ? SizedBox(
                      height: 44,
                      child: FloatingActionButton.extended(
                        backgroundColor: DiaryColors.surfaceSoft,
                        foregroundColor: DiaryColors.ink,
                        elevation: 3,
                        highlightElevation: 5,
                        shape: const StadiumBorder(),
                        extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
                        extendedIconLabelSpacing: 6,
                        onPressed: () => context.push('/share'),
                        label: Text(
                          '상품 추가',
                          style: DiaryTheme.ui(14, weight: FontWeight.w700),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                      ),
                    )
                  : null,
              floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
            ),
            if (_tutorial.isShowing)
              // 하단 탭바는 덮지 않는다(탭을 바꾸면 튜토리얼이 닫히는 규칙).
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: _kNavBarHeight + navInset,
                child: TutorialOverlay(controller: _tutorial),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.shell,
  });

  final int index;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final active = shell.currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => shell.goBranch(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? activeIcon : icon,
              color: active
                  ? DiaryColors.ink
                  : DiaryColors.ink.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OneLineText(
                label,
                textAlign: TextAlign.center,
                style: DiaryTheme.body(
                  11,
                  weight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active
                      ? DiaryColors.ink
                      : DiaryColors.ink.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
