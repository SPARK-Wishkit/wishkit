# App Store Connect 입력할 내용 (복사해서 붙여 넣기)

`<SITE>` = 빌드 스크립트 마지막 줄에 나오는 `https://xxxx.cloudfront.net` (lib/amplify_outputs.dart 의 `siteBaseUrl`).

## 1. 앱 정보

| 칸 | 값 |
|---|---|
| 이름 | wishkit |
| 부제(30자) | 흩어진 찜 목록을 한곳에, 살까 말까는 친구에게 |
| 카테고리 | 기본: 쇼핑 · 보조: 소셜 네트워킹 |
| 개인정보 처리방침 URL | `<SITE>/privacy.html` |
| 지원 URL | `<SITE>/support.html` |
| 마케팅 URL (선택) | `<SITE>/` |
| 저작권 | 2026 wishkit 팀 |
| 연령 등급 | 설문에서 **사용자 생성 콘텐츠: 예**, 그 밖의 항목은 모두 "없음" → 보통 12+ (UGC 앱의 일반적인 결과) |

### 프로모션 텍스트(170자)
쇼핑몰마다 흩어진 찜 목록, 이제 wishkit 하나로 모아 보세요. 고민되는 상품은 친구에게 보내 투표받고 결정해요.

### 설명
```
여러 쇼핑몰에 흩어진 찜한 상품, 한곳에서 관리하세요.

■ 링크 하나로 담기
쇼핑몰 앱에서 공유 버튼 → wishkit 을 누르면 상품 이름·가격·사진을 알아서 읽어 와요.
옷 태그 사진을 찍어도 공식몰 상품 페이지를 찾아 줘요.

■ 폴더로 정리
셔츠, 바지, 신발… 원하는 대로 폴더를 만들고, 공개할 폴더만 친구에게 보여 줄 수 있어요.

■ 살까 말까, 친구에게 물어보기
고민되는 상품을 골라 친구에게 보내면 친구가 투표하고 댓글로 의견을 남겨요.
앱이 없는 친구에게는 링크로도 보낼 수 있어요.

■ 가격 확인
담아 둔 상품의 가격을 새로고침해서 할인 여부를 확인할 수 있어요.

문의: hi.wishkit@gmail.com
```

### 키워드(100자, 쉼표로 구분, 띄어쓰기 없이)
```
위시리스트,찜,장바구니,쇼핑,패션,옷,가격비교,할인,투표,친구,무신사,쇼핑몰,위시,살까말까
```
> ⚠️ "무신사" 같은 다른 회사 이름은 상표 문제로 거절될 수 있다. 거절되면 빼고 다시 낸다.

## 2. 앱 개인정보 (App Privacy · "영양 성분표")

"데이터를 수집합니까?" → **예**. 아래처럼 고른다 (`app/site/privacy.html`, `ios/Runner/PrivacyInfo.xcprivacy` 와 같음).

| 데이터 종류 | 용도 | 사용자와 연결 | 추적에 사용 |
|---|---|---|---|
| 연락처 정보 → 이메일 주소 | 앱 기능 | 예 | 아니요 |
| 연락처 정보 → 이름 | 앱 기능 | 예 | 아니요 |
| 사용자 콘텐츠 → 사진 또는 비디오 | 앱 기능 | 예 | 아니요 |
| 사용자 콘텐츠 → 기타 사용자 콘텐츠 (위시리스트·댓글·메모) | 앱 기능 | 예 | 아니요 |
| 식별자 → 사용자 ID | 앱 기능 | 예 | 아니요 |
| 식별자 → 기기 ID (광고 ID) | 타사 광고 | 아니요 | **예** |
| 사용 데이터 → 광고 데이터 | 타사 광고 | 아니요 | **예** |
| 진단 → 충돌 데이터 | 앱 기능 | 아니요 | 아니요 |

> 기기 ID·광고 데이터는 AdMob SDK 가 모은다. ATT 에서 허용한 사람만 추적되지만, Apple 은 "추적할 수 있으면 예"로 신고하라고 한다.

## 3. 심사 정보 (App Review Information)

### 데모 계정 만들기 (제출 전에 운영 백엔드에서)
1. 앱에서 계정 2개 가입: `review1@…`, `review2@…` (실제로 메일을 받을 수 있는 주소 — 인증 코드가 필요). 아이디 `applereview1`, `applereview2`.
2. 서로 팔로우한다.
3. review1 로 상품 3개 담기 → 폴더 하나 공개 → review2 에게 살까말까 보내기(투표 켜기).
4. review2 로 그 살까말까에 댓글 하나, 투표 하나.
5. review1 의 이메일·비밀번호를 아래 메모에 적는다. (review2 는 신고·차단 대상으로 쓰인다)

### 메모 (영어로 — 그대로 붙여 넣기)
```
Demo account: <review1 email> / <password>
This account follows "applereview2", who has sent it a "살까말까" (ask-friends) post with a comment and a vote.

User-generated content safeguards (Guideline 1.2):
- Terms: Sign-up requires agreeing to the Terms of Use, which state zero tolerance for objectionable content and abusive users. The agreed version is stored on the account.
- Filtering: Comments and post memos are checked on the server against a list of objectionable words and rejected.
- Report: Tap "⋯" next to any comment from another user, or "⋯" at the top right of a received post, or "⋯" at the top right of a friend's wishlist → "신고하기" (Report).
- Block: Same "⋯" menus → "차단하기" (Block), or long-press a name in the friends list. Blocked users' posts, comments and notifications disappear immediately, and the two users can no longer send posts to each other. Unblock in 마이페이지 (My Page) → 차단한 사용자 (Blocked users).
- Reports are emailed to our team and reviewed within 24 hours; violating content is removed and the user is suspended.

Account deletion (Guideline 5.1.1(v)): 마이페이지 → ⚙ (top right) → 회원 탈퇴. This deletes the account and all content, including posts sent to friends and comments left on others' posts.

Contact / support: 마이페이지 → 고객 문의 (hi.wishkit@gmail.com).

Tracking: The App Tracking Transparency prompt appears on first launch, before any ad is requested. If declined, only non-personalized ads are shown.

Adding a product: share a product page from Safari or a shopping app to "wishkit", or paste a link on the 담기 screen.
```

### 연락처
이름·전화번호·이메일: 담당자 정보 (이메일은 hi.wishkit@gmail.com).

## 4. 수출 규정 (Export Compliance)
"암호화를 사용합니까?" → **예**, "면제 대상 암호화만 사용(HTTPS 등 표준 암호화)" → **예**.
매번 묻지 않게 하려면 Info.plist 에 `ITSAppUsesNonExemptEncryption = NO` 를 넣는다 (이번 변경에 포함됨).
