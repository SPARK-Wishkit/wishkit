# 신고 처리 절차 (Google Play UGC 정책 5.5)

## 신고가 들어오는 곳

- 앱: 댓글 길게 누르기/… → 신고, 받은 살까말까 오른쪽 위 … → 신고, 친구 wishkit 오른쪽 위 … → 신고
- 서버 함수 `reportContent` 가 DynamoDB **Report** 표에 한 줄을 만든다 (`status = open`).
  신고 당시 내용이 `snapshot` 에 남아서, 작성자가 지워도 확인할 수 있다.
- 같은 때 CloudWatch 로그(`social-actions` 함수)에 `"event":"WISHKIT_REPORT"` 한 줄이 찍힌다.

## 알림 켜기 (한 번만)

CloudWatch → 로그 그룹(social-actions 함수) → 지표 필터: `{ $.event = "WISHKIT_REPORT" }`
→ 지표 `WishKit/Reports` → 경보(1건 이상) → SNS 로 담당자 이메일.

## 처리 기준 (24시간 안에)

| 사유 | 조치 |
|---|---|
| 욕설·비방·괴롭힘 | 해당 댓글/살까말까 삭제. 반복이면 계정 정지 |
| 음란·선정적 | 즉시 삭제 + 계정 정지. 아동 관련이면 관계 기관 신고 |
| 스팸·광고 | 삭제 + 계정 정지 |
| 위반 아님 | `status = dismissed` |

## 조치 방법 (AWS 콘솔)

- 댓글 삭제: BasketComment 표에서 `threadId` + `commentId` 행 삭제
- 받은 살까말까 삭제: ReceivedBasket 표에서 `fromUid` 로 찾아 삭제
- 계정 정지: Cognito 사용자 풀 → 해당 사용자(sub = `targetUserId`) → **사용자 비활성화**
- 처리 후 Report 행의 `status` 를 `actioned` 또는 `dismissed` 로 바꾼다.
- 처리 완료 후 1년이 지난 Report 행은 지운다 (개인정보처리방침 4번).

신고가 많아지면 관리자 화면이나 금칙어 필터(체크리스트 5.5 권장)를 따로 만든다.
