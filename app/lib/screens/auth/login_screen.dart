import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../../auth/auth_routes.dart';
import '../../auth/auth_validators.dart';
import '../../support/support_info.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import 'auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final handleCtrl = TextEditingController();
  bool isRegister = false;

  // 회원가입 필수 동의 (App Store 심사 1.2: 불쾌한 콘텐츠 무관용 약관에 동의해야 가입)
  bool agreeTerms = false;
  bool agreePrivacy = false;
  bool agreeAge = false;
  bool get _agreedAll => agreeTerms && agreePrivacy && agreeAge;
  String? error;
  String? notice;

  @override
  void initState() {
    super.initState();
    notice = context.read<AuthController>().takeNotice();
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passwordCtrl.dispose();
    nameCtrl.dispose();
    handleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    if (auth.busy) return;
    setState(() {
      error = null;
      notice = null;
    });
    if (isRegister && !_agreedAll) {
      setState(() => error = '필수 항목에 모두 동의해야 가입할 수 있어요.');
      return;
    }
    try {
      if (isRegister) {
        await auth.register(
          email: emailCtrl.text,
          password: passwordCtrl.text,
          name: nameCtrl.text,
          handle: handleCtrl.text,
        );
      } else {
        await auth.login(email: emailCtrl.text, password: passwordCtrl.text);
      }
      // 성공하면 라우터가 알아서 인증 화면이나 홈으로 보낸다.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  void _toggleMode() {
    setState(() {
      isRegister = !isRegister;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final loading = auth.busy;
    final blocked = auth.startupError != null;

    return AuthPage(
      children: [
        WishkitLogo(size: 42),
        const SizedBox(height: 4),
        Container(height: 2, width: 40, color: DiaryColors.ink),
        const SizedBox(height: 10),
        Text(
          isRegister
              ? '이메일 인증 후 계정이 만들어져요'
              : '계정으로 로그인하고 wishkit을 이어가요',
          style: DiaryTheme.body(13, color: DiaryColors.inkMuted),
        ),
        if (blocked) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DiaryColors.band,
              borderRadius: BorderRadius.circular(DiaryTheme.radius),
            ),
            child: Text(auth.startupError!, style: DiaryTheme.body(12)),
          ),
        ],
        const SizedBox(height: 24),
        if (isRegister) ...[
          TextField(
            controller: nameCtrl,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            maxLength: AuthValidators.nameMaxLength,
            decoration: authInput('이름 (선택)'),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: handleCtrl,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.newUsername],
            decoration: authInput(
              '아이디',
              helper: '영문 소문자·숫자·마침표·밑줄, 3~20자',
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          decoration: authInput('이메일'),
        ),
        const SizedBox(height: 12),
        PasswordTextField(
          controller: passwordCtrl,
          decoration: authInput(
            '비밀번호',
            helper: isRegister
                ? '${AuthValidators.passwordMinLength}자 이상, 숫자 포함'
                : null,
          ),
          textInputAction: TextInputAction.done,
          autofillHints: [
            isRegister ? AutofillHints.newPassword : AutofillHints.password,
          ],
          onSubmitted: (_) => _submit(),
        ),
        if (isRegister) ...[
          const SizedBox(height: 16),
          _TermsAgreement(
            agreeTerms: agreeTerms,
            agreePrivacy: agreePrivacy,
            agreeAge: agreeAge,
            enabled: !loading,
            onChanged: (terms, privacy, age) => setState(() {
              agreeTerms = terms;
              agreePrivacy = privacy;
              agreeAge = age;
              if (_agreedAll) error = null;
            }),
          ),
        ],
        AuthNotice(message: notice, error: error),
        const SizedBox(height: 20),
        DiaryButton(
          label: loading
              ? (isRegister ? '가입 중...' : '로그인 중...')
              : (isRegister ? '회원가입' : '로그인'),
          filled: true,
          onPressed: loading || blocked || (isRegister && !_agreedAll)
              ? null
              : _submit,
        ),
        if (!isRegister)
          Align(
            alignment: Alignment.centerRight,
            child: AuthTextLink(
              label: '이메일 / 비밀번호 찾기',
              onPressed: loading ? null : () => context.push(AuthPaths.recovery),
            ),
          ),
        const SizedBox(height: 8),
        AuthTextLink(
          label: isRegister ? '이미 계정이 있나요? 로그인' : '계정이 없나요? 회원가입',
          onPressed: loading ? null : _toggleMode,
        ),
      ],
    );
  }
}

/// 회원가입 필수 동의: 이용약관(불쾌한 콘텐츠 무관용 포함) · 개인정보 수집·이용 · 만 14세 이상.
class _TermsAgreement extends StatelessWidget {
  const _TermsAgreement({
    required this.agreeTerms,
    required this.agreePrivacy,
    required this.agreeAge,
    required this.enabled,
    required this.onChanged,
  });

  final bool agreeTerms;
  final bool agreePrivacy;
  final bool agreeAge;
  final bool enabled;
  final void Function(bool terms, bool privacy, bool age) onChanged;

  @override
  Widget build(BuildContext context) {
    final all = agreeTerms && agreePrivacy && agreeAge;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      decoration: BoxDecoration(
        color: DiaryColors.band,
        borderRadius: BorderRadius.circular(DiaryTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CheckRow(
            checked: all,
            enabled: enabled,
            label: '전체 동의',
            bold: true,
            onTap: () => onChanged(!all, !all, !all),
          ),
          const Divider(height: 1, color: DiaryColors.line),
          _CheckRow(
            checked: agreeTerms,
            enabled: enabled,
            label: '[필수] 서비스 이용약관 동의',
            onTap: () => onChanged(!agreeTerms, agreePrivacy, agreeAge),
            onView: () => openSupportPage(context, SupportInfo.termsPage),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 0, 12, 6),
            child: Text(
              'wishkit은 욕설·괴롭힘·혐오·음란 등 불쾌한 콘텐츠와 이런 행동을 하는 사용자를 '
              '허용하지 않아요. 신고되면 24시간 안에 내용을 지우고 이용을 제한해요.',
              style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
            ),
          ),
          _CheckRow(
            checked: agreePrivacy,
            enabled: enabled,
            label: '[필수] 개인정보 수집·이용 동의',
            onTap: () => onChanged(agreeTerms, !agreePrivacy, agreeAge),
            onView: () => openSupportPage(context, SupportInfo.privacyPage),
          ),
          _CheckRow(
            checked: agreeAge,
            enabled: enabled,
            label: '[필수] 만 14세 이상이에요',
            onTap: () => onChanged(agreeTerms, agreePrivacy, !agreeAge),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.checked,
    required this.enabled,
    required this.label,
    required this.onTap,
    this.onView,
    this.bold = false,
  });

  final bool checked;
  final bool enabled;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onView;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(DiaryTheme.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 22,
              color: checked ? DiaryColors.ink : DiaryColors.inkSoft,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: DiaryTheme.body(
                  13,
                  weight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (onView != null)
              TextButton(
                onPressed: onView,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: DiaryColors.inkSoft,
                ),
                child: const Text('보기'),
              ),
          ],
        ),
      ),
    );
  }
}
