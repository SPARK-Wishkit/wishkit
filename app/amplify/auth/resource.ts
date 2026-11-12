import { defineAuth } from '@aws-amplify/backend';
import { preSignUp } from './pre-sign-up/resource';

/**
 * wishkit 로그인(Cognito) 설정.
 *
 * - 이메일 + 비밀번호로 로그인
 * - 이메일 인증은 6자리 코드
 * - 가입 때 받은 이름/아이디는 Cognito 속성(name, preferred_username)에
 *   "가입 초안"으로만 담아 둔다. 아이디 중복 검사와 최종 원본은
 *   앱 데이터 쪽 프로필이 맡는다. → docs/TEAM_CONTRACT.md 참고
 * - 비밀번호 규칙과 토큰 수명은 ../backend.ts 에서 덮어쓴다.
 */
export const auth = defineAuth({
  loginWith: {
    email: {
      verificationEmailStyle: 'CODE',
      verificationEmailSubject: '[wishkit] 이메일 인증 코드',
      verificationEmailBody: (createCode) =>
        `wishkit 인증 코드는 ${createCode()} 입니다. 앱에 입력해 주세요.`,
    },
  },
  userAttributes: {
    fullname: { required: false, mutable: true },
    preferredUsername: { required: false, mutable: true },
    // 가입할 때 동의한 이용약관·개인정보처리방침 버전(예: '2026-11-12'). 동의 시각은 계정 생성 시각.
    // 앱이 가입 요청에 넣고, pre-sign-up 이 없으면 가입을 막는다 (App Store 1.2 · 개인정보 보호법 동의 기록).
    // 약관을 바꾸면 앱의 SupportInfo.termsVersion 을 올리고, 다시 동의받을 때 이 값을 고친다.
    'custom:terms_version': { dataType: 'String', mutable: true, maxLen: 32 },
  },
  accountRecovery: 'EMAIL_ONLY',
  triggers: {
    preSignUp,
  },
});
