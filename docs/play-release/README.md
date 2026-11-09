# Google Play 출시 준비 — 코드 밖에서 해야 할 일

브랜치 `chore/play-release-requirements` 가 코드 쪽 필수 항목(서명 설정, AdMob ID 연결, 약관 동의,
신고·차단, 탈퇴 시 공유 콘텐츠 삭제, 처리방침·약관·계정 삭제 페이지)을 넣었다.
아래는 사람이 직접 해야 하는 일이다. 체크리스트 원본: 「WishKit Android Google Play 출시 체크리스트」(Google 문서).

## 1. 업로드 키 만들기 (체크리스트 2.1)

```bash
keytool -genkey -v -keystore ~/wishkit-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp app/android/key.properties.example app/android/key.properties   # 값 채우기 (git 에 안 올라감)
flutter build appbundle --release                                  # app/ 에서
```

- `.jks` 와 비밀번호는 레포 밖, 팀 금고에 백업한다. 잃어버리면 Play Console 에서 업로드 키 재설정 요청이 필요하다.
- Play Console 에서 **Play 앱 서명**을 켠다 (기본값).
- `key.properties` 가 없으면 빌드 로그에 `debug 키로 서명` 경고가 뜬다. 그 .aab 는 올리지 말 것.

## 2. AdMob 실제 ID (체크리스트 6.1)

1. AdMob 콘솔에서 Android 앱 추가 → 앱 ID(`ca-app-pub-…~…`)를 `key.properties` 의 `admobAppId` 에 넣는다.
2. 네이티브·배너 광고 단위를 만들고 빌드할 때 넣는다:
   ```bash
   flutter build appbundle --release \
     --dart-define=ADMOB_NATIVE_ANDROID=ca-app-pub-…/… \
     --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-…/…
   ```
3. iOS 는 `ios/Runner/Info.plist` 의 `GADApplicationIdentifier` 가 아직 테스트 ID — iOS 출시 때 교체.

## 3. 처리방침·약관·계정 삭제 페이지 공개 (체크리스트 4.1, 4.3, 5.2)

1. `legal-site/legal/*.html` 의 `[운영자명]`, `[문의 이메일]`, `[책임자 이름]`, `[시행일]` 을 채운다.
   초안이므로 출시 전 법률 검토를 받는다.
2. GitHub 저장소 Settings → Pages → Source 를 **GitHub Actions** 로 바꾸고 `main` 에 머지하면
   `.github/workflows/legal-pages.yml` 이 올린다. 주소:
   `https://spark-wishkit.github.io/SPARK_Wishkit/legal/privacy.html`
   (비공개 저장소라 Pages 를 못 쓰면 S3·Amplify Hosting 등에 올리고 `--dart-define=LEGAL_BASE_URL=…/legal` 로 빌드)
3. Play Console 입력
   - 앱 콘텐츠 → 개인정보처리방침: `…/legal/privacy.html`
   - 데이터 보안 → 계정 삭제 URL: `…/legal/account-deletion.html`
4. 처리방침 내용(수집 항목·공유처·보관 기간)과 **데이터 보안 양식**(체크리스트 4.5)이 같게 답한다.
   직접 기록한 옷 사진도 "사진" 항목으로 넣는다.

## 4. 백엔드 배포 (체크리스트 5.3–5.5, 4.4, 6.5)

- 이 브랜치는 DynamoDB 표 4개(BasketComment, ReceivedBasket, BasketThread, Block)에 보조 인덱스를 하나씩 추가하고
  Block·Report 표를 새로 만든다. 표마다 인덱스가 하나씩이라 한 번의 배포로 된다.
- 운영 환경(체크리스트 6.5): Amplify 콘솔에서 `main` 브랜치를 연결해 공용 백엔드를 만들고,
  출시 빌드는 그 환경의 `amplify_outputs.dart` 로 만든다.
- 앱의 `lib/services/aws/gql_documents.dart` 에 새 문서(listBlocks, createBlock, deleteBlock, reportContent,
  deleteMySocialData)를 넣었다. 배포 후 README 의 스키마 대조 검증을 다시 돌린다.

## 5. 신고 처리 담당 (체크리스트 5.5)

[moderation.md](moderation.md) 참고. 담당자를 정하고 CloudWatch 알림을 켠다.

## 6. Play Console 나머지

- 개인 계정이면 비공개 테스트(테스터 12명 이상 × 14일 연속)를 바로 시작한다 (체크리스트 1.2).
- 광고 ID 신고 "예, 광고용", 광고 포함 "예", 콘텐츠 등급 설문에서 사용자 상호작용·UGC "예".
- 심사용 테스트 계정(위시리스트·팔로우·댓글 달린 살까말까가 있는 계정)을 앱 액세스에 넣는다.
