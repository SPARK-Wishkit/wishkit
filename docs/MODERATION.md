# 신고 · 차단 처리 (운영팀용)

App Store 심사 1.2 는 "신고를 받으면 **24시간 안에** 확인해서 내용을 지우고 작성자를 내보낼 것"을 요구한다.
이 문서는 그 일을 하는 방법이다.

## 신고가 들어오는 길

| 무엇 | 어디에 |
|---|---|
| 신고 (댓글 · 받은 살까말까 · 사용자) | DynamoDB `ContentReport-…` 표 + **hi.wishkit@gmail.com** 메일 |
| 차단 | DynamoDB `Block-…` 표 + 같은 메일 (`[wishkit 차단]`) |
| 앱 밖 문의 | hi.wishkit@gmail.com |

> ⚠️ 처음 배포한 뒤 hi.wishkit@gmail.com 에 오는 **"AWS Notification - Subscription Confirmation"** 메일에서
> **Confirm subscription** 을 눌러야 신고 메일이 오기 시작한다. (안 눌러도 신고는 표에 쌓인다)

신고 메일에는 신고 번호, 신고한 사람·대상 사용자 uid(Cognito `sub`), 신고 사유, **신고한 순간의 내용(snapshot)** 이 들어 있다.

## 처리 순서 (24시간 안에)

1. 메일이나 AWS 콘솔 → DynamoDB → `ContentReport-…` 표 → `status = open` 인 줄을 연다.
2. `snapshot` 을 읽고 규칙 위반인지 판단한다 (기준: `app/site/terms.html` 제4조).
3. 위반이면:
   - **댓글 지우기:** `BasketComment-…` 표에서 `threadId` + `commentId`(신고의 `targetKey` = `threadId/commentId`) 줄 삭제.
   - **살까말까 지우기:** `ReceivedBasket-…` 표에서 `fromUid = 대상 uid` 인 줄을 찾아 삭제 (보조 인덱스 `byFromUid` 로 조회).
   - **계정 정지:** Cognito → 사용자 풀 → 사용자 검색(`sub` = 대상 uid) → **사용자 비활성화(Disable user)**.
     비활성화하면 로그인할 수 없다. 심하면 **삭제**한다.
   - 이름·아이디·사진이 문제면 `Profile-…` 표에서 고치거나 계정을 정지한다.
4. 신고 줄의 `status` 를 `resolved` 로 바꾸고, 필요하면 `detail` 옆에 처리 내용을 적는다.
5. 신고한 사람이 메일로도 알렸다면 결과를 답장한다.

## 금칙어 고치기

`app/amplify/functions/social-actions/moderation.ts` 의 `BANNED_WORDS` / `ALLOWED_WORDS` 를 고치고 main 에 머지하면 다음 배포부터 적용된다.
멀쩡한 말이 막힌다는 문의가 오면 `ALLOWED_WORDS` 에 그 낱말을 넣는다.
