# Google Play 출시 준비 — 사람이 할 일

체크리스트 원본: 「WishKit Android Google Play 출시 체크리스트」(Google 문서, 11/4).
코드 쪽 필수 항목은 main 에 들어가 있다 — iOS 출시 작업(#32, #33)과 공용인 것(약관 동의, 신고·차단·금칙어,
탈퇴 시 공유 콘텐츠 삭제, 처리방침·고객센터 페이지)과, 이 브랜치의 Android 전용 항목(업로드 키 서명, cleartext,
계정 삭제 요청 페이지, 차단 관계 서버 검사·투표 삭제 보강). 신고 처리 방법은 [../MODERATION.md](../MODERATION.md).

| 체크리스트 | 코드 | 남은 일 |
|---|---|---|
| 2.1 업로드 키 | `android/app/build.gradle.kts` 가 `android/key.properties` 로 release 서명 | ☐ 키 만들기 (1번) |
| 2.8 cleartext | 출시 매니페스트에서 삭제, debug 매니페스트에만 | — |
| 2.10 앱 이름 | `WishKit` | — |
| 4.1 개인정보처리방침 | `app/site/privacy.html` (+ 영어), 앱 마이페이지·가입 화면에 링크 | ☐ Play Console 에 URL |
| 4.3 웹 계정 삭제 | `app/site/account-deletion.html` | ☐ 데이터 보안 양식에 URL |
| 4.4 공유 콘텐츠 삭제 | `deleteMyContent`: 남의 방 댓글·투표, 친구 받은함의 보낸 살까말까, 내가 만든 댓글방, 차단 기록 | — |
| 4.9 공개 링크 안내 | 링크 공유 메뉴에 "누구나 28일 동안 볼 수 있어요 (상품 메모 포함)" | — |
| 5.1–5.2 약관 동의 | 회원가입 [필수] 동의 + 서버(pre-sign-up)가 동의 버전 없으면 거절 | — |
| 5.3–5.5 신고·차단·관리 | ⋯ 메뉴 신고·차단, 차단 관계면 살까말까·댓글·투표·알림·공개 위시리스트 서버에서 거부, 금칙어 필터, 신고 메일 | ☐ 담당자 (MODERATION.md) |
| 6.1 AdMob | `android/gradle.properties` 의 `admobAndroidAppId`, 광고 단위는 `--dart-define` | ☐ 실제 ID (2번) |
| 6.5 운영 백엔드 | Amplify 앱 `d10l8u76nc8eda`, main, 서울 | — |

## 1. 업로드 키 만들기 (2.1)

```bash
keytool -genkey -v -keystore ~/wishkit-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp app/android/key.properties.example app/android/key.properties   # 값 채우기 (git 에 안 올라감)
```

- `.jks` 와 비밀번호는 **레포 밖, 팀 금고**에 백업한다. 잃어버리면 Play Console 에서 업로드 키 재설정을 요청해야 한다.
- Play Console 에서 **Play 앱 서명**을 켠다 (기본값).
- `key.properties` 가 없으면 빌드 로그에 `debug 키로 서명` 경고가 뜬다. 그 .aab 는 올리지 말 것.

## 2. AdMob 실제 ID (6.1)

1. AdMob 콘솔 → 앱 추가 → Android → 앱 ID(`ca-app-pub-…~…`)를 `app/android/gradle.properties` 의 `admobAndroidAppId` 에.
2. 네이티브·배너 광고 단위를 만들어 빌드할 때 넣는다.
3. AdMob → 차단 관리 → 최대 광고 콘텐츠 등급을 앱 등급에 맞춘다.

## 3. 빌드

```bash
cd app
npx ampx generate outputs --app-id d10l8u76nc8eda --branch main --format dart --out-dir lib   # 운영 백엔드 주소록
flutter build appbundle --release \
  --build-number="$(git rev-list --count HEAD)" \
  --dart-define=ADMOB_NATIVE_ANDROID=ca-app-pub-…/… \
  --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-…/…
# → build/app/outputs/bundle/release/app-release.aab
```
버전 코드(빌드 번호)는 git 커밋 수로 정해서 업로드마다 저절로 커진다 — `pubspec.yaml` 의 `+N` 은 안 고쳐도 된다.
같은 커밋으로 다시 올려야 하면 `--build-number` 에 이전보다 큰 숫자를 직접 넣는다.

## 4. Play Console 입력

`<SITE>` = `https://dliv74foj7pc9.cloudfront.net` (lib/amplify_outputs.dart 의 `siteBaseUrl`)

- **앱 콘텐츠 → 개인정보처리방침:** `<SITE>/privacy.html`
- **데이터 보안 → 계정 삭제 URL:** `<SITE>/account-deletion.html`
- **데이터 보안 양식** (처리방침과 같게):
  - 수집: 이메일, 이름, 사용자 ID, 사진(프로필·태그·직접 찍은 옷 사진), 기타 사용자 콘텐츠(위시리스트·댓글·메모·상품 URL), 기기 ID·광고 ID(AdMob), 앱 상호작용, 대략적인 위치(AdMob)
  - 공유: 기기 ID·광고 데이터 → Google AdMob(광고)
  - 전송 중 암호화 **예**, 삭제 요청 가능 **예**
- **광고 ID:** "예, 광고용" · **광고 포함:** 예
- **콘텐츠 등급(IARC):** 사용자 간 상호작용·사용자 생성 콘텐츠 **예**
- **타겟층:** 만 14세 이상 (가입 조건과 같게, 만 13세 미만 포함하지 않기)
- **앱 액세스:** 심사용 계정 (iOS 와 같은 데모 계정 — `docs/APP_STORE_SUBMISSION.md`)
- **국가:** 한국 (EU 를 넣으면 Google UMP 동의 팝업이 필요하다 — 체크리스트 4.7)
- **스토어 등록정보:** 이름 WishKit, 간단한 설명(80자)·자세한 설명은 `docs/APP_STORE_SUBMISSION.md` 의 설명을 쓰되 iOS·App Store 언급과 쇼핑몰 이름은 빼기. 아이콘 512×512, 그래픽 이미지 1024×500, 스크린샷 2장 이상.

## 5. 계정 종류와 테스트 기간

- **조직 계정**으로 등록한다(사업자등록 → D-U-N-S 번호). 조직 계정은 비공개 테스트 14일 의무가 없다.
- **개인 계정**이면 테스터 12명 이상이 14일 연속 참여한 비공개 테스트 후에야 프로덕션 신청 가능 (체크리스트 1.2) — 지금 바로 시작.
- 어느 쪽이든 내부 테스트 트랙에서 실제 폰으로: 쇼핑 앱 → 공유 → WishKit 담기, 신고·차단, 탈퇴.

## 6. 기기에서 확인할 것

계정 2개(A, B)를 서로 팔로우하고 A 가 B 에게 살까말까를 보낸 상태에서:
1. **가입 동의** — 체크 안 하면 가입 버튼이 꺼진다. "보기"를 누르면 페이지가 열린다.
2. **댓글 신고** — B 의 댓글 ⋯ → 신고 → hi.wishkit@gmail.com 에 신고 메일, DynamoDB `ContentReport-…` 에 행.
3. **차단** — A 가 B 차단 → B 의 살까말까·댓글·투표·알림이 A 화면에서 사라지고 팔로우가 끊긴다.
   B 로 A 의 댓글방에 댓글·투표하면 거부되고, B 에게 A 의 공개 위시리스트가 안 보인다.
4. **차단 해제** — 마이페이지 → 차단한 사용자 → 해제.
5. **탈퇴** — B 탈퇴 → A 의 댓글방에서 B 의 댓글·투표가 사라지고, A 받은함의 B 살까말까도 사라진다.
