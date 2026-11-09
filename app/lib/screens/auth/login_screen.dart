import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../../auth/auth_routes.dart';
import '../../auth/auth_validators.dart';
import '../../legal/legal_links.dart';
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
  bool agreeTerms = false;
  bool agreePrivacy = false;
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
    try {
      if (isRegister) {
        await auth.register(
          email: emailCtrl.text,
          password: passwordCtrl.text,
          name: nameCtrl.text,
          handle: handleCtrl.text,
          agreedToTerms: agreeTerms && agreePrivacy,
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
      agreeTerms = false;
      agreePrivacy = false;
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
          const SizedBox(height: 12),
          _ConsentRow(
            label: '[필수] 이용약관 동의',
            value: agreeTerms,
            onChanged: loading ? null : (v) => setState(() => agreeTerms = v),
            onView: () => LegalLinks.open(context, LegalLinks.terms),
          ),
          _ConsentRow(
            label: '[필수] 개인정보 수집·이용 동의',
            value: agreePrivacy,
            onChanged: loading ? null : (v) => setState(() => agreePrivacy = v),
            onView: () => LegalLinks.open(context, LegalLinks.privacy),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              '욕설·비방·괴롭힘·음란물·스팸 등 약관을 어기는 댓글이나 계정은 '
              '신고를 받아 삭제·이용 정지될 수 있어요.',
              style: DiaryTheme.body(11, color: DiaryColors.inkMuted),
            ),
          ),
        ],
        AuthNotice(message: notice, error: error),
        const SizedBox(height: 20),
        DiaryButton(
          label: loading
              ? (isRegister ? '가입 중...' : '로그인 중...')
              : (isRegister ? '회원가입' : '로그인'),
          filled: true,
          onPressed: loading ||
                  blocked ||
                  (isRegister && !(agreeTerms && agreePrivacy))
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

/// 회원가입 동의 한 줄: 체크박스 + 문구 + "보기"(웹페이지).
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onView,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onChanged == null ? null : () => onChanged!(!value),
            child: Text(label, style: DiaryTheme.body(13)),
          ),
        ),
        TextButton(
          onPressed: onView,
          child: Text(
            '보기',
            style: DiaryTheme.body(12, color: DiaryColors.inkMuted).copyWith(
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
