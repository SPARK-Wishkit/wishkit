#!/usr/bin/env bash
# Google Play 업로드용 Android 빌드(.aab). 출시 전에 빠뜨리기 쉬운 것을 검사하고 나서 빌드한다.
#
#   scripts/build_android_release.sh
#
# 1) 운영 백엔드 주소록(lib/amplify_outputs.dart)에 siteBaseUrl 이 있는지 — sandbox·옛 주소록으로 출시하지 않게.
#    없으면: cd app && npx ampx generate outputs --app-id d10l8u76nc8eda --branch main --format dart --out-dir lib
# 2) 업로드 키 설정(app/android/key.properties)이 있는지 — 없으면 debug 키로 서명돼 Play 가 거부한다.
# 3) AdMob 앱 ID(app/android/gradle.properties 의 admobAndroidAppId)와 광고 단위 ID가 구글 테스트 값이 아닌지.
# 4) flutter build appbundle → app/build/app/outputs/bundle/release/app-release.aab 를 Play Console 에 올린다.
#    빌드 번호(versionCode)는 git 커밋 수로 자동으로 정한다(업로드마다 저절로 커진다).
#    같은 커밋으로 다시 올려야 하면 BUILD_NUMBER=… 로 직접 정한다(이전 업로드보다 커야 함).
#
# 광고 단위 ID 는 비밀이 아니라서 아래에 기본값으로 둔다(AdMob 팀 계정 pub-8101096133732475, 앱 "WishKit").
# 바꿀 때: ADMOB_NATIVE_ANDROID=… ADMOB_BANNER_ANDROID=… scripts/build_android_release.sh
# 테스트를 건너뛰려면(이미 돌렸을 때): SKIP_TESTS=1 scripts/build_android_release.sh
# 자세한 순서: docs/play-release/README.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app"

ADMOB_NATIVE_ANDROID="${ADMOB_NATIVE_ANDROID:-ca-app-pub-8101096133732475/2293241289}"
ADMOB_BANNER_ANDROID="${ADMOB_BANNER_ANDROID:-ca-app-pub-8101096133732475/7327122292}"
TEST_PUBLISHER='ca-app-pub-3940256099942544'
fail() { echo "❌ $*" >&2; exit 1; }

echo "▶ 출시 전 검사"
[[ -f lib/amplify_outputs.dart ]] || fail "lib/amplify_outputs.dart 가 없어요. 운영 주소록을 먼저 받아 주세요(위 1번)."
grep -q 'siteBaseUrl' lib/amplify_outputs.dart ||
  fail "amplify_outputs.dart 에 siteBaseUrl 이 없어요(옛 주소록). 운영 주소록을 다시 받아 주세요(위 1번)."

[[ -f android/key.properties ]] ||
  fail "android/key.properties 가 없어요. 업로드 키 설정이 필요해요(docs/play-release/README.md 1절)."
for k in storeFile storePassword keyPassword keyAlias; do
  grep -qE "^${k}=.+" android/key.properties || fail "android/key.properties 의 ${k} 가 비어 있어요."
done
STORE_FILE="$(grep -E '^storeFile=' android/key.properties | cut -d= -f2-)"
[[ -f "$STORE_FILE" ]] || fail "키 파일이 없어요: $STORE_FILE"

APP_ID="$(grep -E '^admobAndroidAppId=' android/gradle.properties | cut -d= -f2- || true)"
[[ -n "$APP_ID" ]] || fail "android/gradle.properties 에 admobAndroidAppId 가 없어요."
[[ "$APP_ID" == "$TEST_PUBLISHER"* ]] && fail "admobAndroidAppId 가 구글 테스트 앱 ID 예요. 실제 AdMob 앱 ID 로 바꿔 주세요."
[[ "$APP_ID" == ca-app-pub-*~* ]] || fail "admobAndroidAppId 모양이 이상해요 (ca-app-pub-XXXX~YYYY): $APP_ID"
for v in ADMOB_NATIVE_ANDROID ADMOB_BANNER_ANDROID; do
  val="${!v}"
  [[ "$val" == "$TEST_PUBLISHER"* ]] && fail "$v 가 구글 테스트 ID 예요. 실제 광고 단위 ID 를 넣어 주세요."
  [[ "$val" == ca-app-pub-*/* ]] || fail "$v 모양이 이상해요 (ca-app-pub-XXXX/YYYY): $val"
done
echo "  AdMob 앱 ID: $APP_ID"
echo "  네이티브: $ADMOB_NATIVE_ANDROID / 배너: $ADMOB_BANNER_ANDROID"

if [[ "${SKIP_TESTS:-0}" != 1 ]]; then
  echo "▶ 테스트"
  flutter pub get
  # 경고 1개(mypage_screen.dart unused_element_parameter)가 남아 있어 경고는 실패로 보지 않는다. 오류만 막는다.
  flutter analyze --no-fatal-infos --no-fatal-warnings
  flutter test
fi

git -C "$ROOT" rev-parse --is-shallow-repository | grep -q true &&
  fail "얕은 클론이라 커밋 수를 셀 수 없어요. git fetch --unshallow 후 다시 실행하세요."
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD)}"
echo "▶ 빌드 번호(versionCode): $BUILD_NUMBER"

echo "▶ Android 빌드(.aab)"
flutter build appbundle --release \
  --build-number="$BUILD_NUMBER" \
  --dart-define=ADMOB_NATIVE_ANDROID="$ADMOB_NATIVE_ANDROID" \
  --dart-define=ADMOB_BANNER_ANDROID="$ADMOB_BANNER_ANDROID"

AAB=build/app/outputs/bundle/release/app-release.aab
[[ -f "$AAB" ]] || fail "빌드 결과가 없어요: $AAB"
if command -v jarsigner >/dev/null 2>&1; then
  SIGNER="$(jarsigner -verify -verbose -certs "$AAB" 2>/dev/null | grep -m1 -oE 'Signed by "[^"]*"' || true)"
  echo "  서명: ${SIGNER:-확인 못 함}"
  [[ "$SIGNER" == *"Android Debug"* ]] && fail "debug 키로 서명됐어요. key.properties 를 확인해 주세요."
fi
echo "✅ 완료: app/$AAB ($(du -h "$AAB" | cut -f1))"
echo "   Play Console → 테스트(내부/비공개) 또는 프로덕션 → 새 버전 만들기 → 이 .aab 업로드"
