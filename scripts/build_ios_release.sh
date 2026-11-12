#!/usr/bin/env bash
# App Store 제출용 iOS 빌드. 출시 전에 빠뜨리기 쉬운 것을 검사하고 나서 빌드한다.
#
#   AMPLIFY_APP_ID=d1234abcd \
#   ADMOB_NATIVE_IOS=ca-app-pub-XXXX/YYYY \
#   ADMOB_BANNER_IOS=ca-app-pub-XXXX/ZZZZ \
#   scripts/build_ios_release.sh
#
# 1) 운영 백엔드(Amplify 콘솔의 main 브랜치) 주소록으로 lib/amplify_outputs.dart 를 새로 만든다 — sandbox 로 출시하지 않게.
#    (AWS 자격 증명이 필요: npx ampx configure profile 로 한 번 설정)
# 2) AdMob 앱 ID(ios/Flutter/AdMob.xcconfig)와 광고 단위 ID가 구글 테스트 값이 아닌지 확인한다.
# 3) flutter build ipa → build/ios/ipa/*.ipa 를 Transporter 앱으로 올린다.
# 자세한 순서: docs/RELEASE_IOS.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app"

TEST_PUBLISHER='ca-app-pub-3940256099942544'
BRANCH="${AMPLIFY_BRANCH:-main}"
fail() { echo "❌ $*" >&2; exit 1; }

[[ -n "${AMPLIFY_APP_ID:-}" ]] || fail "AMPLIFY_APP_ID 가 없어요. Amplify 콘솔 → 앱 → 앱 설정 → '앱 ARN' 끝의 d로 시작하는 ID 를 넣어 주세요."
for v in ADMOB_NATIVE_IOS ADMOB_BANNER_IOS; do
  val="${!v:-}"
  [[ -n "$val" ]] || fail "$v 가 없어요. AdMob 콘솔에서 만든 실제 광고 단위 ID 를 넣어 주세요."
  [[ "$val" == "$TEST_PUBLISHER"* ]] && fail "$v 가 구글 테스트 ID 예요. 실제 광고 단위 ID 를 넣어 주세요."
  [[ "$val" == ca-app-pub-*/* ]] || fail "$v 모양이 이상해요 (ca-app-pub-XXXX/YYYY): $val"
done
APP_ID_LINE="$(grep -E '^ADMOB_IOS_APP_ID' ios/Flutter/AdMob.xcconfig || true)"
[[ "$APP_ID_LINE" == *"$TEST_PUBLISHER"* ]] && fail "ios/Flutter/AdMob.xcconfig 의 ADMOB_IOS_APP_ID 가 구글 테스트 앱 ID 예요. 실제 AdMob iOS 앱 ID 로 바꿔 주세요."
[[ "$APP_ID_LINE" == *"ca-app-pub-"*"~"* ]] || fail "ios/Flutter/AdMob.xcconfig 의 ADMOB_IOS_APP_ID 모양이 이상해요 (ca-app-pub-XXXX~YYYY)."

echo "▶ 운영 백엔드($BRANCH) 주소록 받는 중…"
npx ampx generate outputs --app-id "$AMPLIFY_APP_ID" --branch "$BRANCH" --format dart --out-dir lib
grep -q 'siteBaseUrl' lib/amplify_outputs.dart || fail "amplify_outputs.dart 에 siteBaseUrl 이 없어요. 최신 main 이 Amplify 콘솔에서 배포됐는지 확인해 주세요."

echo "▶ 테스트"
flutter pub get
flutter analyze --no-fatal-infos
flutter test

echo "▶ iOS 빌드"
flutter build ipa --release \
  --dart-define=ADMOB_NATIVE_IOS="$ADMOB_NATIVE_IOS" \
  --dart-define=ADMOB_BANNER_IOS="$ADMOB_BANNER_IOS"

echo "✅ 완료: $(ls build/ios/ipa/*.ipa 2>/dev/null || echo build/ios/ipa)"
echo "   Transporter 앱으로 올리거나: xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios --apiKey … --apiIssuer …"
echo "⚠️  사이트 주소(App Store Connect 에 입력): $(grep -o 'https://[a-z0-9]*\.cloudfront\.net' lib/amplify_outputs.dart | sort -u | tr '\n' ' ')"
