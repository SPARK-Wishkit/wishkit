import type { PreSignUpTriggerHandler } from 'aws-lambda';

/**
 * 가입 요청이 Cognito에 저장되기 직전에 서버에서 한 번 더 검사한다.
 * 앱 쪽 검사는 우회될 수 있으므로 같은 규칙을 여기서도 강제한다.
 *
 * ⚠️ 규칙은 app/lib/auth/auth_validators.dart 와 반드시 같게 유지할 것.
 *
 * 여기서 던진 메시지는 앱에 UserLambdaValidationException 으로 전달된다.
 * 앱은 "PSU_" 로 시작하는 코드를 한국어 문구로 바꿔 보여 준다.
 */
const HANDLE_RE = /^[a-z0-9][a-z0-9._]{1,18}[a-z0-9]$/;
const NAME_MAX = 30;

export const handler: PreSignUpTriggerHandler = async (event) => {
  // 관리자 콘솔 생성 등 앱 가입이 아닌 경로는 건드리지 않는다.
  if (event.triggerSource !== 'PreSignUp_SignUp') return event;

  const attrs = event.request.userAttributes ?? {};
  const email = (attrs.email ?? '').trim();
  const name = (attrs.name ?? '').trim();
  const handle = (attrs.preferred_username ?? '')
    .trim()
    .replace(/^@/, '')
    .toLowerCase();

  if (!email) throw new Error('PSU_EMAIL_REQUIRED');
  if (!handle) throw new Error('PSU_HANDLE_REQUIRED');
  if (!HANDLE_RE.test(handle) || handle.includes('..')) {
    throw new Error('PSU_HANDLE_FORMAT');
  }
  if (name.length > NAME_MAX) throw new Error('PSU_NAME_TOO_LONG');
  // 이용약관(불쾌한 콘텐츠 무관용 포함)·개인정보 수집·만 14세 이상에 동의해야 가입할 수 있다.
  // 앱이 동의한 약관 버전을 custom:terms_version 으로 보낸다 → 동의 기록이 계정에 남는다.
  const terms = (attrs['custom:terms_version'] ?? '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(terms)) throw new Error('PSU_TERMS_REQUIRED');

  // 자동 확인/자동 인증은 절대 켜지 않는다. 반드시 이메일 코드로 인증한다.
  event.response.autoConfirmUser = false;
  event.response.autoVerifyEmail = false;
  return event;
};
