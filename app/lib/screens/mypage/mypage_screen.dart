import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_validators.dart';
import '../../data/app_store.dart';
import '../../theme/avatar_presets.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/add_folder_dialog.dart';
import '../../widgets/diary_widgets.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  @override
  void initState() {
    super.initState();
    // 마이페이지를 열 때 팔로워·팔로잉 숫자를 다시 센다(다른 기기·다른 사람이 바꾼 것 반영).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppStore>().refreshSocialCounts();
    });
  }

  /// 알림 켜기/끄기 + 무엇이 달라지는지 안내.
  Future<void> _toggleNotifications(BuildContext context, AppStore store) async {
    final next = !store.notificationsEnabled;
    await store.setNotificationsEnabled(next);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Icon(
              next
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              color: DiaryColors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                next
                    ? '알림을 켰어요. 팔로우·살까말까 같은 새 소식이 휴대폰 상단 배너로 와요. '
                        '(휴대폰 설정에서 wishkit 알림이 허용돼 있어야 해요)'
                    : '알림을 껐어요. 배너로는 오지 않고, 새 소식은 앱의 알림 목록에서 볼 수 있어요.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final user = store.currentUser;
    final folders = store.tabs.where((t) => t.id != 'all').toList();

    return Scaffold(
      backgroundColor: DiaryColors.paper,
      body: SafeArea(
        child: RefreshIndicator(
          color: DiaryColors.ink,
          onRefresh: store.refreshSocialCounts,
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            Padding(
              // Same as 내 친구 / 살까말까 page titles.
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  Text('마이페이지', style: DiaryTheme.display(24)),
                  const Spacer(),
                  IconButton(
                    tooltip: '계정 설정',
                    onPressed: () => _openAccountSettings(context, store),
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: DiaryColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            // ── Profile (bigger, dark text) ───────────────────
            // 제목("마이페이지")과 프로필 사이를 띄운다.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: DiaryColors.surfaceSoft,
                    backgroundImage: NetworkImage(user.avatarUrl),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DiaryTheme.display(23),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          user.handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DiaryTheme.ui(
                            14,
                            weight: FontWeight.w500,
                            color: DiaryColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _openEditProfile(context, store),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      side: const BorderSide(color: DiaryColors.ink),
                    ),
                    child: const Text('프로필 수정'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                children: [
                  _Stat(
                    value: user.followers,
                    label: '팔로워',
                    onTap: () => context.push('/followers'),
                  ),
                  _Stat(
                    value: user.following,
                    label: '팔로잉',
                    onTap: () => context.push('/following'),
                  ),
                  _Stat(value: store.products.length, label: '아이템'),
                ],
              ),
            ),
            const SectionBand(),
            // Wishlists
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Text(
                '내 wishkit',
                style: DiaryTheme.ui(17, weight: FontWeight.w800),
              ),
            ),
            if (folders.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '아직 폴더가 없어요. + 를 눌러 첫 폴더를 만들어보세요',
                  style: DiaryTheme.body(13, color: DiaryColors.inkSoft),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              // Two equal columns (option A).
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chipWidth = (constraints.maxWidth - 12) / 2;
                  return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final tab in folders)
                    _FolderChip(
                      width: chipWidth,
                      label: tab.name,
                      count: store.countFor(tab),
                      onTap: () {
                        store.selectTab(tab.id);
                        // Switch to wishlist tab in bottom nav.
                        StatefulNavigationShell.maybeOf(context)?.goBranch(0);
                        context.go('/');
                      },
                    ),
                  _FolderChip(
                    width: chipWidth,
                    label: '폴더 추가',
                    icon: Icons.add,
                    onTap: () => showAddFolderDialog(context, store),
                  ),
                ],
                  );
                },
              ),
            ),
            const SectionBand(height: 6),
            // 메뉴 줄 높이: 예전 44의 1.5배(66).
            MenuRow(
              height: 66,
              label: '내가 보낸 살까말까',
              icon: Icons.outbox_outlined,
              onTap: () => context.push('/sent-baskets'),
            ),
            MenuRow(
              height: 66,
              label: '알림 설정',
              // 종 모양으로 지금 상태를 보여 준다: 켜짐 = 울리는 종, 꺼짐 = 빗금 친 종.
              icon: store.notificationsEnabled
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              trailing: Text(
                store.notificationsEnabled ? '켜짐' : '꺼짐',
                style: DiaryTheme.ui(
                  14,
                  weight: FontWeight.w600,
                  color: store.notificationsEnabled
                      ? DiaryColors.ink
                      : DiaryColors.inkSoft,
                ),
              ),
              onTap: () => _toggleNotifications(context, store),
            ),
            MenuRow(
              height: 66,
              label: '앱 정보',
              icon: Icons.info_outline,
              onTap: () {
                // 기본 showAboutDialog 는 "View licenses" 버튼이 붙어서 직접 만든 창을 쓴다.
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: WishkitLogo(size: 26),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '버전 1.0.0',
                          style: DiaryTheme.ui(13, color: DiaryColors.inkSoft),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '여러 쇼핑몰에 흩어진 찜한 상품을 한곳에서 관리합니다.\n'
                          '구매가 고민되는 상품은 친구에게 의견을 물을 수 있습니다.',
                          style: DiaryTheme.body(14).copyWith(height: 1.5),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('닫기'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
        ),
      ),
    );
  }

  Future<void> _openAccountSettings(
    BuildContext context,
    AppStore store,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: DiaryColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DiaryTheme.radius)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '계정 설정',
                  style: DiaryTheme.body(16, weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text('프로필 수정하기', style: DiaryTheme.body(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openEditProfile(context, store);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_outline),
                  title: Text('비밀번호 수정하기', style: DiaryTheme.body(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openChangePassword(context, store);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout),
                  title: Text('로그아웃', style: DiaryTheme.body(14)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await store.logout();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.person_off_outlined,
                    color: DiaryColors.pin,
                  ),
                  title: Text(
                    '탈퇴하기',
                    style: DiaryTheme.body(14, color: DiaryColors.pin),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openDeleteAccount(context, store);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDeleteAccount(BuildContext context, AppStore store) async {
    final passwordCtrl = TextEditingController();
    String? error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: DiaryColors.paper,
              title: Text(
                '탈퇴하기',
                style: DiaryTheme.ui(17, weight: FontWeight.w700),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '탈퇴하면 계정과 wishkit이 삭제되고 되돌릴 수 없어요.',
                      style: DiaryTheme.body(13, color: DiaryColors.inkMuted),
                    ),
                    const SizedBox(height: 12),
                    PasswordTextField(
                      controller: passwordCtrl,
                      decoration: const InputDecoration(labelText: '비밀번호 확인'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: DiaryTheme.body(12, color: DiaryColors.pin),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: () {
                    if (passwordCtrl.text.isEmpty) {
                      setLocal(() => error = '비밀번호를 입력해 주세요.');
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: Text(
                    '탈퇴',
                    style: DiaryTheme.ui(
                      14,
                      weight: FontWeight.w700,
                      color: DiaryColors.pin,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;
    try {
      await store.deleteAccount(password: passwordCtrl.text);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('탈퇴가 완료되었어요')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _openChangePassword(BuildContext context, AppStore store) async {
    final currentCtrl = TextEditingController();
    final nextCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: DiaryColors.paper,
              title: Text(
                '비밀번호 변경',
                style: DiaryTheme.ui(17, weight: FontWeight.w700),
              ),
              // 다른 앱들처럼: 칸 위에 이름표, "현재"와 "새 비밀번호" 묶음 사이는 구분선으로 띄우고,
              // 새 비밀번호 규칙과 두 칸이 같은지를 칸 바로 아래에서 알려 준다.
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    _fieldLabel('현재 비밀번호'),
                    PasswordTextField(
                      controller: currentCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: '지금 쓰는 비밀번호',
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Divider(height: 1, color: DiaryColors.line),
                    const SizedBox(height: 22),
                    _fieldLabel('새 비밀번호'),
                    PasswordTextField(
                      controller: nextCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: '새 비밀번호',
                        helperText:
                            '${AuthValidators.passwordMinLength}자 이상, 숫자 포함',
                      ),
                    ),
                    const SizedBox(height: 12),
                    PasswordTextField(
                      controller: confirmCtrl,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: '새 비밀번호 다시 입력',
                      ),
                    ),
                    // 두 칸이 같은지 바로 보여 준다.
                    ListenableBuilder(
                      listenable: Listenable.merge([nextCtrl, confirmCtrl]),
                      builder: (context, _) {
                        if (confirmCtrl.text.isEmpty) {
                          return const SizedBox(height: 8);
                        }
                        final same = nextCtrl.text == confirmCtrl.text;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8, left: 4),
                          child: Row(
                            children: [
                              Icon(
                                same ? Icons.check_circle : Icons.error_outline,
                                size: 16,
                                color: same
                                    ? DiaryColors.ink
                                    : DiaryColors.sale,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                same ? '비밀번호가 일치해요' : '비밀번호가 일치하지 않아요',
                                style: DiaryTheme.ui(
                                  12,
                                  color: same
                                      ? DiaryColors.ink
                                      : DiaryColors.sale,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: DiaryTheme.body(12, color: DiaryColors.sale),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: () {
                    if (currentCtrl.text.isEmpty) {
                      setLocal(() => error = '현재 비밀번호를 입력해 주세요.');
                      return;
                    }
                    final rule = AuthValidators.password(nextCtrl.text);
                    if (rule != null) {
                      setLocal(() => error = rule);
                      return;
                    }
                    if (nextCtrl.text != confirmCtrl.text) {
                      setLocal(() => error = '새 비밀번호가 서로 달라요.');
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: Text(
                    '변경',
                    style: DiaryTheme.ui(
                      14,
                      weight: FontWeight.w700,
                      color: DiaryColors.accent,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;
    try {
      await store.changePassword(
        currentPassword: currentCtrl.text,
        newPassword: nextCtrl.text,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('비밀번호를 변경했어요')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _openEditProfile(BuildContext context, AppStore store) async {
    final nameCtrl = TextEditingController(text: store.currentUser.name);
    final handleCtrl = TextEditingController(text: store.currentUser.handle);
    var selectedAvatarUrl = store.currentUser.avatarUrl;
    File? pendingUpload;
    var saving = false;
    String? localError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            ImageProvider preview;
            if (pendingUpload != null) {
              preview = FileImage(pendingUpload!);
            } else {
              preview = NetworkImage(selectedAvatarUrl);
            }

            return AlertDialog(
              backgroundColor: DiaryColors.paper,
              title: Text(
                '프로필 수정하기',
                style: DiaryTheme.ui(17, weight: FontWeight.w700),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: CircleAvatar(radius: 40, backgroundImage: preview),
                    ),
                    // 테두리 칸 위에 떠 있는 라벨이 위 칸과 겹치지 않게 칸 사이를 띄운다.
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '이름'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: handleCtrl,
                      decoration: const InputDecoration(
                        labelText: '아이디 (@없이 입력 가능)',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '기본 이미지',
                      style: DiaryTheme.body(13, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final url in AvatarPresets.urls)
                          GestureDetector(
                            onTap: () => setLocal(() {
                              pendingUpload = null;
                              selectedAvatarUrl = url;
                              localError = null;
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      pendingUpload == null &&
                                          selectedAvatarUrl == url
                                      ? DiaryColors.accent
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 20,
                                backgroundImage: NetworkImage(url),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '사진 파일 업로드',
                      style: DiaryTheme.body(13, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              final picker = ImagePicker();
                              final picked = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1024,
                                maxHeight: 1024,
                                imageQuality: 85,
                              );
                              if (picked == null) return;
                              setLocal(() {
                                pendingUpload = File(picked.path);
                                localError = null;
                              });
                            },
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(
                        pendingUpload == null ? '갤러리에서 선택' : '다른 사진 선택',
                        style: DiaryTheme.body(13),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DiaryColors.ink,
                        side: BorderSide(
                          color: DiaryColors.ink.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                    if (localError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        localError!,
                        style: DiaryTheme.body(12, color: DiaryColors.pin),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx, false),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setLocal(() {
                            saving = true;
                            localError = null;
                          });
                          try {
                            var avatarUrl = selectedAvatarUrl;
                            if (pendingUpload != null) {
                              avatarUrl = await store.uploadAvatarFile(
                                pendingUpload!,
                              );
                            }
                            await store.updateProfile(
                              name: nameCtrl.text,
                              handle: handleCtrl.text,
                              avatarUrl: avatarUrl,
                            );
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setLocal(() {
                              saving = false;
                              localError = e.toString().replaceFirst(
                                'Exception: ',
                                '',
                              );
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          '저장',
                          style: DiaryTheme.ui(
                            14,
                            weight: FontWeight.w700,
                            color: DiaryColors.accent,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('프로필을 저장했어요')));
    }
  }
}

/// Big dark number over a label (no box).
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Text('$value', style: DiaryTheme.display(24)),
            const SizedBox(height: 2),
            Text(
              label,
              style: DiaryTheme.ui(
                13,
                weight: FontWeight.w600,
                color: DiaryColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wishlist folder chip: white with a thin gray outline.
/// The "폴더 추가" chip (has [icon]) has no outline.
class _FolderChip extends StatelessWidget {
  const _FolderChip({
    required this.label,
    required this.onTap,
    required this.width,
    this.count,
    this.icon,
  });

  final double width;
  final String label;
  final VoidCallback onTap;
  final int? count;
  final IconData? icon;

  bool get _isAdd => icon != null;

  @override
  Widget build(BuildContext context) {
    final fg = _isAdd ? DiaryColors.inkMuted : DiaryColors.ink;
    return Material(
      color: DiaryColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DiaryTheme.radius),
        // 폴더 추가도 다른 폴더처럼 테두리를 둔다.
        side: const BorderSide(color: DiaryColors.lineStrong),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DiaryTheme.radius),
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            // Folders: name left, count right. 폴더 추가: centred.
            mainAxisAlignment: _isAdd
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DiaryTheme.ui(14, weight: FontWeight.w700, color: fg),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: DiaryTheme.ui(
                    14,
                    weight: FontWeight.w500,
                    color: DiaryColors.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


/// 입력칸 위에 붙는 작은 이름표(비밀번호 변경 등).
Widget _fieldLabel(String text) => Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        text,
        style: DiaryTheme.ui(13, weight: FontWeight.w700),
      ),
    );
