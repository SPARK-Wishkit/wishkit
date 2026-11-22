# 엔진 배포·운영 (`engine/deploy/`)

- `engine.sh` — 엔진(ECS Fargate, 태스크 1개)을 만들고·배포하고·켜고·끈다. 사용법은 `bash engine.sh` (인자 없이).
- `ops-setup.sh` — 상시 운영 안전장치: 로그 보관 30일 + CloudWatch 알람 3개(→ SNS `ReportAlerts`, 신고 메일과 같은 주소). 여러 번 돌려도 같은 결과.

지금(출시 전)은 시연·테스트할 때만 켠다(`engine.sh start` / `stop`). **출시하면 엔진은 계속 켜 둔다** — 꺼져 있으면 앱의 모든 링크 담기가 실패한다.

## 출시 때 켜는 순서

1. `bash engine.sh start` — 1~3분. `desired=1, running=1` 이 될 때까지 기다린다.
2. 헬스 확인 — `bash engine.sh status` 에서 running=1, 서킷 브레이커 `True`.
   엔진은 인터넷에서 직접 못 들어가므로(보안그룹: parsing-proxy Lambda 만 허용) `/healthz` 는 태스크 헬스체크(30초마다)가 대신 본다.
   ECS 콘솔 → 클러스터 `wishkit-engine` → 태스크 → Health status 가 `HEALTHY` 인지 확인.
3. `bash ops-setup.sh --enable-alarms` — 알람 알림 켜기. 엔진이 켜진 뒤에 해야 `wishkit-engine-down` 이 바로 울리지 않는다.
4. 앱에서 상품 1개 담기(쇼핑몰 주소 붙여 넣기 또는 공유) → 상품 정보가 채워지는지 확인.

다시 시연용으로 끌 때: `bash ops-setup.sh --disable-alarms` → `bash engine.sh stop` (확인 질문, `--yes` 로 건너뜀).

## 알람

| 이름 | 조건 | 뜻 |
|---|---|---|
| `wishkit-engine-down` | AWS/ECS `CPUUtilization`(클러스터·서비스) 5분 평균이 2번 연속 **데이터 없음** | 엔진 태스크가 없음(꺼짐·죽음) → 링크 담기 전부 실패 |
| `wishkit-engine-proxy-errors` | parsing-proxy Lambda `Errors` 5분 합계 ≥ 5 | 엔진·Gemini 오류나 쇼핑몰 차단이 몰림 |
| `wishkit-engine-proxy-slow` | parsing-proxy Lambda `Duration` 5분 p90 > 20,000ms | AppSync 30초 한도에 가까움 |

- 경보·복구 모두 SNS `ReportAlerts` 로 메일이 간다.
- `ops-setup.sh` 를 옵션 없이 다시 돌리면 이미 있는 알람의 알림 켜짐/꺼짐은 그대로 둔다(출시 뒤 실수로 꺼지지 않게). 새로 만드는 알람은 꺼진 상태다.
- 엔진이 꺼져 있는 동안 `wishkit-engine-down` 은 늘 경보(ALARM) 상태다 — 알림이 꺼져 있으면 메일은 안 간다.
- 비용: 표준 해상도 알람 개당 월 약 0.10달러(p90 같은 백분위 통계도 표준 알람). 3개면 월 약 0.3달러.

## 배포 설정

`engine.sh deploy` 는 서비스에 **배포 서킷 브레이커 + 자동 되돌리기**(`deploymentCircuitBreaker={enable=true,rollback=true}`, 최소 100%·최대 200%)를 매번 넣는다. 새 이미지가 뜨지 못하면 이전 버전으로 돌아간다.
