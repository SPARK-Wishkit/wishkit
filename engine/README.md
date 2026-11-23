# engine — AI 완전 의존 상품 추출 서버 (예전 이름: parsing-engine)

예전 WebView 인수인계 문서(레포에서 뺌, 깃 기록 커밋 `8db873f`에 있음) 0.9절에서 삭제됐던 `parsing-engine/` 폴더를 다른 방향으로
되살린 것이다 — 이전 버전(DOM 규칙 기반 Python 폴백)과는 무관하다. 이번 버전은 **몰별 규칙이
전혀 없고, 상품 페이지를 렌더링해서 AI(Gemini)에게 통째로 읽혀 이름/가격/이미지를 뽑는다.**

**이관 메모**: 이 폴더는 원래 `soft-studio-team/2026-softstudio-project` 저장소의
`feat/ai-extraction-server` 브랜치(커밋 `ea81107`)에서 개발·검증됐고, 이 저장소로 그대로
이관됐다. AWS Fargate 실측 검증(서울 리전, 4GB/6GB 태스크, 단일/수평 확장)과 Gemini
Tier 1 전환까지 끝난 상태이며, 그 과정은 `docs/reports/2026-09-19-engine-server-port.md`·
`docs/reports/2026-09-24-fargate-validation.md`에 그대로 남아있다.

## 배경 — 반드시 먼저 읽을 것

**2026-10-24 갱신**: 앱의 WebView 추출기를 제거하고, 앱은 상품 URL 을 이 서버로만 읽는다(GraphQL
`extractProduct` → `parsing-proxy` Lambda → `POST /extract`). AppSync 30초 한도 때문에 배포 시
`EXTRACT_TIMEOUT_S=25`로 띄운다(`deploy/engine.sh`). 아래 문단은 그 전 상황 기록이다.

이 폴더가 만들어진 시점(2026-09-19)에 `main` 브랜치의 `ENGINE_DEVELOPMENT_HANDOFF.md`는
여전히 "Python 서버 폴백은 채택하지 않음, WebView 우선"이라고 적혀 있었다(마지막 갱신
2026-08-21). 이 서버는 그 결정을 뒤집는 **2026-09-18 새 결정**("서버 AI 완전 의존" —
`engine-ai-prototype/design-doc-snapshot-2026-09-18.md` 0절)에 따라 만들어졌다. 두 문서가
당분간 서로 다른 이야기를 할 수 있으니, 이 폴더를 보고 헷갈리면 그 두 문서(및
`ENGINE_DEVELOPMENT_HANDOFF.md`에 새로 추가된 노트)를 먼저 대조해볼 것.

## 이 폴더와 `engine-ai-prototype`의 관계

`engine-ai-prototype/`(이 저장소 밖, 별도 폴더)은 이 파이프라인의 **원본 프로토타입**이다 —
로컬 배치 스크립트(`bakeoff.py`)로 골든셋 36개 상품에 대해 정확도만 검증했다(완전 일치
21/36=58%, 그라운딩 통과 31/36=86% — `docs/reports/2026-09-19-engine-server-port.md` 참고).
이 폴더(`server/`)는 그 검증된 로직(`render.py`/`prompts.py`/`providers.py`/`compare.py`)을
실제 HTTP 요청에 응답하는 서버로 감싼 것 — 로직 자체(프롬프트 문구, few-shot, 가격 정책,
그라운딩 체크)는 바뀐 게 없고, 브라우저 생명주기만 "요청마다 새로 띄움"에서 "앱 시작 시
한 번 띄워서 재사용"으로 바뀌었다(자세한 이유는 `server/render.py` 상단 주석 참고).

원래 `engine-ai-prototype/`(2026-softstudio-project 저장소 밖, 이 저장소에는 없음) 폴더에
있던 골든셋(`golden_catalog.json`)은 이관하면서 **이 폴더의 `testdata/`로 같이 옮겨왔다**.
프로토타입 단계의 1회성 베이스라인(`bakeoff_results_run6_final.json`)도 같이 옮겨왔었지만,
골든셋을 갱신(`docs/reports/2026-10-29-golden-catalog-refresh.md`)하면서 이제는 그 옛 기준과
비교할 일이 없어 지웠다 — 당시 수치는 위 두 리포트에 남아 있다.

## 구성

```
testdata/
  golden_catalog.json             — 골든셋 36개 상품(12개 몰) 정답지(수시로 갱신됨, 변경
                                     근거는 docs/reports/ 참고)
  results/                        — 지난 회귀·부하 테스트 결과 기록
deploy/
  engine.sh     — AWS Fargate 엔진 켜기·끄기·배포 (bash deploy/engine.sh start 등)
server/
  main.py       — FastAPI 앱, POST /extract, GET /healthz, 브라우저 생명주기(lifespan)
  render.py     — Playwright 렌더링(async, 브라우저 재사용). 로직은 engine-ai-prototype과 동일
  providers.py  — Gemini 텍스트/스크린샷(비전) 호출 + 429 재시도. 호출 방식은
                  engine-ai-prototype과 동일(bakeoff용 Anthropic/OpenAI 함수는 서버에서 제거)
  prompts.py    — 시스템 프롬프트/few-shot/JSON 스키마. engine-ai-prototype과 완전히 동일
                  (문구를 바꾸지 않았음)
  compare.py    — 그라운딩 체크(응답에 포함) + 골든셋 비교(회귀 테스트용)
  metrics.py    — 요청별 elapsed_ms/peak_rss_mb 측정
  config.py     — 전부 환경변수로 오버라이드 가능한 설정값
tools/
  golden_regression_check.py — 로컬 서버에 골든셋 36개를 던져서 완전 일치·그라운딩 통과율을
                                확인(--baseline으로 과거 결과 JSON과 비교도 가능, 선택사항)
  concurrency_load_test.py   — 동시 요청 N건 부하 테스트(AWS Fargate 검증에 사용)
```

## 태그 사진으로 찾기 — `POST /identify-tag` (2026-10-22 추가)

`{image_base64, mime_type}`를 받아 태그의 품번으로 상품 상세 페이지를 찾는다(공식몰 우선, 없으면
국내 쇼핑몰). **가격은 읽지 않는다** — 앱이 돌려받은 URL을 기존 "URL로 담기" 경로로 읽는다.

0. QR 먼저(2026-11-08, `qr_codes.py`): 태그 읽기와 동시에 zxing-cpp로 QR·바코드를 디코딩한다(LLM은 QR을
   못 읽고 주소를 지어낼 수 있어서 쓰지 않음). QR 주소는 홉마다 공개 IP인지 확인하며 따라가고(SSRF 방지),
   상품 페이지면 렌더링해 품번을 확인 → 확인되면 검색 없이 `found`(`match.via="qr"`). 브랜드 메인으로 가면
   그 도메인을 공식몰 도메인으로 검색에 넘긴다. GS1 QR의 GTIN·1차원 바코드는 태그 바코드로 쓴다.
   QR로 못 찾으면 아래 1~4로. 응답의 `qr`에 QR마다 어디로 갔고 왜 안 됐는지 남는다.
   ⚠️ 엔진 태스크의 보안 그룹에서 사설망·메타데이터 주소 송신을 막아 두는 게 근본 대책이다(코드 검사는 1차 방어).
1. 태그 읽기: Gemini 비전 + JSON 스키마(브랜드·품번·다른 코드들·바코드·상품명·색상·태그 가격).
   바코드는 검증 숫자가 안 맞으면 버린다(`tag_codes.py`).
2. 검색: Gemini + Google 검색 그라운딩(텍스트 응답을 직접 파싱 — 도구와 JSON 스키마를 같이
   쓰면 그라운딩 메타데이터가 비는 문제가 보고돼 있음)
3. 확인: 후보 페이지를 렌더링해서 **품번(또는 바코드)이 페이지에 실제로 있는지** 확인. 품번이
   있는데 페이지에 없으면 이름이 비슷해도 인정하지 않는다. 색상 코드를 뗀 기본 번호(`product_code_base`)도
   근거로 쓰고, 같은 수준의 후보끼리는 태그 가격이 페이지에 보이는 쪽(`tag_price_seen`)을 고른다.
4. 응답: `status`(found / not_found / not_a_tag), `tag`, `match`(url·host·source·verified_by)

⚠️ 앱 → AppSync → Lambda 경로는 AppSync가 30초에 끊는다. 그래서 `IDENTIFY_TIMEOUT_S` 기본값을
25초로 두고, 남은 시간이 모자라면 후보 확인을 덜 하고 not_found로 끝낸다.

정확도는 실제 태그 사진으로 잰다: `tools/tag_identify_check.py --photos ./photos`
(사용법은 파일 상단 참고. 품번 읽기 정확도와 페이지 찾기 정확도를 따로 센다.)

## 실행

```bash
cd server
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
playwright install chrome   # 또는 이미 설치된 크롬을 쓰려면 생략(폴백 있음)
cp .env.example .env        # GEMINI_API_KEY 채우기
uvicorn main:app --host 0.0.0.0 --port 8000
```

```bash
# 다른 터미널에서 회귀 테스트 (engine/tools에서 실행)
cd ../tools
python golden_regression_check.py --golden-catalog ../testdata/golden_catalog.json
```

## 하지 않은 것 (의도적으로 범위 밖에 둠)

- AWS 리소스 생성/배포, 실제 캐시 백엔드 구현, DB 연동, Flutter 앱 쪽 통합 — 전부 이 작업의
  범위가 아니다(보고서의 "다음에 결정이 필요한 것" 참고).
- 몰별 규칙 기반 폴백 — 이번 방향(AI 완전 대체)과 어긋나서 추가하지 않았다.


## 태그 찾기 실패 모으기 · 원인 정리 · 자동 학습 (2026-11-09)

엔진은 `/identify-tag` 요청마다 로그에 `[identify-report] {...}` 한 줄(익명 JSON)을 남기고, 응답에 `trace_id`와
`cause`(원인)를 넣는다. 앱은 사용자의 답(맞아요 `yes` / 다른 상품이에요 `no` / 못 불러옴 `not_found` / 못 찾은 뒤 직접
넣은 링크 `user_link`)을 같은 `traceId`로 TagFeedback에 남긴다. 사진·사용자 정보는 어디에도 남지 않는다.

- 원인 목록과 뜻: `server/failure_report.py`의 `CAUSES`
- 분석·학습: `tools/learn_from_feedback.py`
  - 로컬 테스트 결과로: `python tools/learn_from_feedback.py --reports ~/engine.log --reports tools/tag_identify_result.json`
  - 운영 데이터로(매주 자동): `.github/workflows/tag-learning.yml`이 CloudWatch 기록과 TagFeedback을 내보내 돌리고
    `engine/reports/tag_learning_날짜.md` + `server/brand_rules.learned.json`을 PR로 올린다.
- 자동 학습 기준(확실한 것만): 새 브랜드·새 판매처는 같은 사이트에서 2번 이상 확인, 주소 규칙은 서로 다른 품번 3개 이상이
  "품번만 바뀌는 같은 주소 모양". 그보다 약한 근거는 리포트의 "사람이 볼 제안"에만 적는다.
- 학습 규칙은 `brand_rules.learned.json`에 따로 쌓이고, 사람이 고치는 `brand_rules.json`과 겹치면 사람 쪽이 이긴다.
  학습 규칙도 페이지 안에서 품번이 확인돼야 "찾음"이 되므로 틀려도 잘못된 상품을 내보내지 않는다.


## 실패 태그 보관 · 자동 규칙 발견 (2026-11-09)

- QR이 없으면 **브랜드와 품번이 둘 다** 있어야 찾는다. 하나라도 없으면 `skip_reason`(`no_brand`/`no_code`/`no_brand_no_code`)으로 바로 끝낸다.
- 실패 태그 보관(`server/failure_store.py`, 기본 꺼짐): `.env`에 `TAG_FAILURE_DIR=/경로`(로컬) 또는 `TAG_FAILURE_S3_BUCKET=버킷`(운영).
  사진은 JPEG로 다시 저장해 촬영 위치·기기 정보를 지운다. **운영에서 켜기 전 개인정보 처리방침에 반영할 것.**
- 자동 규칙 발견(`tools/discover_rules.py`): 보관된 실패(또는 `tag_identify_result.json`)를 시간 제한 없이 다시 시도해,
  페이지에서 품번이 확인된 방법을 브랜드별로 모으고, 서로 다른 품번 2개 이상에서 통하면 `brand_rules.learned.json`에 넣는다.
  `python tools/discover_rules.py --failures tools/tag_identify_result.json --write-learned`
- 참고: 무신사 `llms.txt`는 쿼리가 붙은 검색 결과 주소(`?keyword=`)를 자동 수집 제외 목록에 두고 있다. 무신사 검색 규칙은
  사용량이 늘기 전에 무신사 제휴·약관을 확인하거나, 사용자 휴대폰에서 여는 방식(WebView)으로 옮기는 것을 검토한다.

- 공식몰 사이트 검색(`server/site_search.py`): 공식몰 도메인을 알면 그 사이트 검색창에 품번을 넣어 찾는다(플랫폼 공통 검색 주소 모양).
  엔진은 마지막 수단으로, `tools/discover_rules.py`는 시간 넉넉히 + 사이트가 알려 주는 검색 주소(SearchAction)까지.
