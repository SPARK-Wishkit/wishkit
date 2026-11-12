# iOS 출시 (App Store 제출) 체크리스트

코드는 아래 9개를 모두 반영했다. **사람이 콘솔에서 해야 하는 일**만 남아 있다 (☐).

| # | 항목 (심사 가이드라인) | 코드에서 한 일 | 남은 일 |
|---|---|---|---|
| 1 | 개인정보 매니페스트 (1.7행) | `ios/Runner/PrivacyInfo.xcprivacy`, `ios/Share Extension/PrivacyInfo.xcprivacy` (UserDefaults 사유 CA92.1 · 1C8F.1, 수집 데이터) — 두 타깃의 Resources 에 등록 | ☐ Xcode 로 한 번 열어 두 파일이 각 타깃에 들어갔는지 확인 |
| 2 | 댓글·바구니 관리: 금칙어 · 신고 · 차단 (2.2–2.4행) | 서버 금칙어 필터(`moderation.ts`), `reportContent` · `blockUser` 서버 함수, 앱의 ⋯ 메뉴(댓글 · 받은 살까말까 · 친구 화면, 친구 목록 길게 누르기), 마이페이지 → 차단한 사용자 | ☐ 처리 방법 숙지: `docs/MODERATION.md` |
| 3 | 가입 시 약관 동의 (2.6행) | 회원가입 화면에 [필수] 이용약관(불쾌한 콘텐츠 무관용 문구 포함) · 개인정보 · 만 14세 이상 체크. 안 하면 가입 버튼이 꺼진다. 동의한 약관 버전이 Cognito `custom:terms_version` 에 기록되고, 없으면 서버(pre-sign-up)가 가입을 막는다 | — |
| 4 | 고객 연락처 (2.5, 2.7행) | 마이페이지 → 고객 문의(hi.wishkit@gmail.com 메일 · 고객센터 페이지) | — |
| 5 | 개인정보처리방침 (5.1행) | `app/site/` 의 privacy · terms · support 페이지를 백엔드가 CloudFront 로 올림 → 앱 마이페이지·가입 화면에서 연결 | ☐ App Store Connect 에 URL 입력 (아래) · ☐ 내용(리전, 위탁사) 사실과 맞는지 확인 |
| 6 | 탈퇴 시 공유 콘텐츠 삭제 (5.5행) | 서버 함수 `deleteMyContent` — 내가 쓴 댓글, 친구 받은함의 내 살까말까, 내가 만든 댓글방(+댓글·투표) 삭제 → 그다음 기존 탈퇴 순서 | — |
| 7 | 추적 동의 ATT (5.7행) | 첫 화면 뒤 ATT 팝업 → 그다음 광고 SDK 시작, 거부하면 비맞춤 광고만 (`lib/ads/ads_consent.dart`) | ☐ App Store Connect "앱 개인정보"에 추적: 예(광고 데이터) |
| 8 | AdMob 실제 설정 (3.1, 5.8행) | 앱 ID는 `ios/Flutter/AdMob.xcconfig` 한 곳, 광고 단위 ID는 `--dart-define`, `SKAdNetworkItems` 50개 추가 | ☐ AdMob 에서 iOS 앱·광고 단위(네이티브, 배너) 만들기 · ☐ `AdMob.xcconfig` 에 실제 앱 ID |
| 9 | 운영 백엔드 (3.2행) | 이미 Amplify 콘솔 main(`d10l8u76nc8eda`)에 연결돼 있음. `scripts/build_ios_release.sh` 가 그 주소록으로 빌드 | — |

## 1. 운영 백엔드

> ✅ 이미 있음: Amplify 앱 `d10l8u76nc8eda`, `main` 브랜치, 서울 리전. main 에 머지하면 자동 배포된다.
> 아래는 새 환경을 처음부터 만들 때만 필요한 순서(참고용).

### (참고) 처음부터 만들 때

0. AWS 콘솔 오른쪽 위 리전을 **아시아 태평양(서울) ap-northeast-2** 로 맞춘다. 개인정보처리방침에 "서울 리전에 저장"이라고 적혀 있다.
1. AWS 콘솔 → **Amplify** → **새 앱 생성** → GitHub → `SPARK-Wishkit/SPARK_Wishkit`, 브랜치 `main`.
2. "My app is a monorepo" 체크 → 경로 `app` (환경 변수 `AMPLIFY_MONOREPO_APP_ROOT=app`). 빌드 설정은 레포의 `amplify.yml` 을 쓴다.
3. 환경 변수: 엔진 서버 값 `ENGINE_VPC_ID`, `ENGINE_PRIVATE_SUBNET_IDS`, `ENGINE_LAMBDA_SG_ID`, `ENGINE_BASE_URL` (`app/amplify/backend.ts` 주석 참고).
4. 배포가 끝나면 **hi.wishkit@gmail.com 의 SNS 구독 확인 메일에서 Confirm** (신고 메일 받기).
5. 앱 ID(`d…`)를 기억해 둔다 → 빌드할 때 `AMPLIFY_APP_ID`.

## 심사 전에 해두면 좋은 것 (체크리스트 1.14 · 1.16 · 1.17 · 5.10 · 5.12) — 반영함

- **ATS 예외 제거(1.14):** Info.plist 의 `NSAppTransportSecurity`(`NSAllowsLocalNetworking`) 삭제. 앱은 HTTPS 만 쓴다.
- **푸시 설정(1.16): 그대로 둠.** `UIBackgroundModes`(remote-notification)와 `aps-environment` 가 남아 있다. 원격 푸시는 아직 없으므로 ① 개발자 포털에서 App ID 의 Push Notifications 를 켜야 서명이 되고 ② 심사에서 "안 쓰는 백그라운드 모드"(2.5.4)로 지적받을 수 있다. 지적받으면 둘 다 지운다.
- **iPhone 전용(1.17):** `TARGETED_DEVICE_FAMILY = 1`. iPad 화면 테스트·스크린샷이 필요 없어진다.
- **링크 공유 안내(5.10):** "링크를 받은 누구나 28일 동안 볼 수 있어요 (상품 메모 포함)". 개인정보처리방침에도 같은 내용.
- **판매처 안내(5.12):** 상품 화면에 "가격과 상품 정보는 ○○ 기준이며 실제 결제 가격과 다를 수 있어요".
- 남은 다듬기: 표시 이름(wishkit / WishKit), 런치 화면(지금은 흰 화면), 영어 InfoPlist 문구(선택).

## 2. AdMob

1. AdMob → 앱 추가 → iOS → (App Store 에 아직 없음) → 앱 ID `ca-app-pub-…~…` 를 `app/ios/Flutter/AdMob.xcconfig` 에.
2. 광고 단위 2개: **네이티브 고급형**(상품 목록), **배너**(태그 찾기 대기 화면) → ID 를 빌드 명령에.
3. 출시 후 AdMob 앱 설정에서 App Store 앱과 연결. `app-ads.txt` 는 고객센터 사이트에 올릴 수 있다(`app/site/app-ads.txt`).

## 3. 빌드

```bash
AMPLIFY_APP_ID=d123abc \
ADMOB_NATIVE_IOS=ca-app-pub-XXXX/YYYY \
ADMOB_BANNER_IOS=ca-app-pub-XXXX/ZZZZ \
scripts/build_ios_release.sh
```
테스트 ID 이거나 운영 주소록을 못 받으면 빌드 전에 멈춘다. 끝나면 `app/build/ios/ipa/*.ipa` 를 Transporter 로 올린다.

## 4. App Store Connect 에 넣을 것

복사해서 붙여 넣을 글(설명, 키워드, 앱 개인정보 답, 영어 심사 메모, 데모 계정 만드는 법)은 **`docs/APP_STORE_SUBMISSION.md`** 에 있다. 요약:

- **개인정보 처리방침 URL:** `<siteBaseUrl>/privacy.html` (빌드 스크립트 마지막 줄에 주소가 나온다)
- **지원 URL:** `<siteBaseUrl>/support.html`
- **앱 개인정보(Nutrition Label):** 연락처 정보(이메일, 이름), 사용자 콘텐츠(사진, 기타), 식별자(사용자 ID, 기기 ID), 사용 데이터(광고 데이터) — 추적: 광고 데이터·기기 ID
- **연령 등급:** 사용자 생성 콘텐츠 있음 → 설문에서 "사용자 생성 콘텐츠" 표시
- **심사 메모(App Review Information):** 데모 계정 2개(서로 팔로우, 살까말까·댓글이 있는 상태)와 다음 안내:
  > 신고·차단: 살까말까 댓글의 ⋯ / 받은 살까말까 오른쪽 위 ⋯ / 친구 wishkit 오른쪽 위 ⋯ / 친구 목록에서 이름 길게 누르기.
  > 차단 해제: 마이페이지 → 차단한 사용자. 탈퇴: 마이페이지 → ⚙ → 회원 탈퇴. 문의: 마이페이지 → 고객 문의.
