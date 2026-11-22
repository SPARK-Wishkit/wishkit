#!/usr/bin/env bash
# 엔진 상시 운영 안전장치: 로그 보관 30일 + CloudWatch 알람 3개(→ 신고 메일과 같은 SNS 주제 ReportAlerts).
# 여러 번 돌려도 같은 결과(put-* 명령은 같은 이름이면 덮어쓴다). 엔진을 켜거나 끄지는 않는다.
#
#   bash ops-setup.sh                  # 로그 보관 30일 + 알람 만들기/갱신. 새 알람은 알림 꺼진 상태로 만들고,
#                                      #   이미 있는 알람은 지금 알림 상태(켜짐/꺼짐)를 그대로 둔다
#   bash ops-setup.sh --enable-alarms  # 위와 같고 알람 알림을 켠다 — 출시 때 engine.sh start 뒤에
#   bash ops-setup.sh --disable-alarms # 위와 같고 알람 알림을 끈다 — 다시 시연용으로 끌 때
#   bash ops-setup.sh --dry-run        # AWS 를 바꾸지 않고 실행할 명령만 출력(조회는 한다)
#
# 알람 (이름 접두어 wishkit-engine-):
#   wishkit-engine-down         AWS/ECS CPUUtilization(클러스터·서비스) 5분 평균에 데이터가 없으면 경보.
#                               엔진이 꺼져 있으면 늘 경보 상태 → 그래서 기본은 알림 꺼짐, 켜는 건 출시 때.
#   wishkit-engine-proxy-errors parsing-proxy Lambda Errors 5분 합계 ≥ 5
#   wishkit-engine-proxy-slow   parsing-proxy Lambda Duration 5분 p90 > 20000ms (AppSync 한도 30초 전 경고)
#
# 환경변수로 바꿀 수 있는 값: AWS_REGION, AMPLIFY_APP_ID(운영 앱), PROXY_FUNCTION(Lambda 이름 직접 지정),
#   ALARM_TOPIC_ARN(SNS 주제 직접 지정)
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
NAME="wishkit-engine"
LOG_GROUP="/ecs/${NAME}"
LOG_RETENTION_DAYS=30
AMPLIFY_APP_ID="${AMPLIFY_APP_ID:-d10l8u76nc8eda}"
ERRORS_THRESHOLD=5
SLOW_P90_MS=20000

MODE_ACTIONS="keep" # keep | enable | disable
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --enable-alarms) MODE_ACTIONS="enable" ;;
    --disable-alarms) MODE_ACTIONS="disable" ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "❌ 모르는 옵션: $arg (--help 참고)" >&2; exit 1 ;;
  esac
done

aws_() { aws --region "$REGION" "$@"; }
log() { echo "▶ $*"; }
die() { echo "❌ $*" >&2; exit 1; }
none_to_empty() { [ "$1" = "None" ] && echo "" || echo "$1"; }

# 바꾸는 명령: --dry-run 이면 출력만, 아니면 실행.
change() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  [dry-run] aws --region %s' "$REGION"
    printf ' %q' "$@"
    echo
  else
    aws_ "$@"
  fi
}

find_topic() {
  [ -n "${ALARM_TOPIC_ARN:-}" ] && { echo "$ALARM_TOPIC_ARN"; return; }
  none_to_empty "$(aws_ sns list-topics \
    --query "Topics[?contains(TopicArn, 'ReportAlerts') && contains(TopicArn, '${AMPLIFY_APP_ID}')].TopicArn | [0]" \
    --output text)"
}

find_proxy_function() {
  [ -n "${PROXY_FUNCTION:-}" ] && { echo "$PROXY_FUNCTION"; return; }
  # 운영 앱(amplify-<앱ID>-…)의 parsing-proxy 만. 개인 샌드박스(amplify-flutterapp-<이름>-…)는 빼기 위해 앱 ID 로 거른다.
  none_to_empty "$(aws_ lambda list-functions \
    --query "Functions[?contains(FunctionName, 'amplify-${AMPLIFY_APP_ID}') && contains(FunctionName, 'parsingproxy')].FunctionName | [0]" \
    --output text)"
}

# 알람의 알림 켜짐 여부: enable/disable 이면 그대로, keep 이면 이미 있는 알람의 지금 상태(없으면 꺼짐).
actions_flag() {
  local current
  case "$MODE_ACTIONS" in
    enable) echo "--actions-enabled"; return ;;
    disable) echo "--no-actions-enabled"; return ;;
  esac
  current=$(none_to_empty "$(aws_ cloudwatch describe-alarms --alarm-names "$1" \
    --query 'MetricAlarms[0].ActionsEnabled' --output text)")
  [ "$current" = "True" ] && echo "--actions-enabled" || echo "--no-actions-enabled"
}

who=$(aws sts get-caller-identity --query Arn --output text 2>&1) || die "AWS 로그인 정보가 없어요: $who"
log "AWS 계정: $who"

topic=$(find_topic)
[ -n "$topic" ] || die "SNS 주제(ReportAlerts, 앱 ${AMPLIFY_APP_ID})를 못 찾았어요. ALARM_TOPIC_ARN 으로 지정해 주세요."
proxy=$(find_proxy_function)
[ -n "$proxy" ] || die "parsing-proxy Lambda(앱 ${AMPLIFY_APP_ID})를 못 찾았어요. PROXY_FUNCTION 으로 지정해 주세요."
log "알람 보낼 곳: ${topic##*:}"
log "parsing-proxy: $proxy"
[ "$DRY_RUN" = 1 ] && log "dry-run — 아래 명령은 실행하지 않아요"

log "로그 그룹 ${LOG_GROUP} 보관 ${LOG_RETENTION_DAYS}일"
change logs put-retention-policy --log-group-name "$LOG_GROUP" --retention-in-days "$LOG_RETENTION_DAYS"

alarm="${NAME}-down"
log "알람 ${alarm} (ECS CPU 데이터 없음 = 엔진 꺼짐/죽음)"
change cloudwatch put-metric-alarm --alarm-name "$alarm" \
  --alarm-description "엔진(ECS ${NAME}) 태스크가 10분 동안 없음 — 링크 담기가 전부 실패 중. engine.sh status 확인" \
  --namespace AWS/ECS --metric-name CPUUtilization \
  --dimensions "Name=ClusterName,Value=${NAME}" "Name=ServiceName,Value=${NAME}" \
  --statistic Average --period 300 --evaluation-periods 2 \
  --comparison-operator LessThanThreshold --threshold 0 --treat-missing-data breaching \
  --alarm-actions "$topic" --ok-actions "$topic" "$(actions_flag "$alarm")"

alarm="${NAME}-proxy-errors"
log "알람 ${alarm} (Lambda Errors 5분 합계 ≥ ${ERRORS_THRESHOLD})"
change cloudwatch put-metric-alarm --alarm-name "$alarm" \
  --alarm-description "parsing-proxy Lambda 오류가 5분에 ${ERRORS_THRESHOLD}건 이상 — 엔진·Gemini·쇼핑몰 차단 확인" \
  --namespace AWS/Lambda --metric-name Errors --dimensions "Name=FunctionName,Value=${proxy}" \
  --statistic Sum --period 300 --evaluation-periods 1 \
  --comparison-operator GreaterThanOrEqualToThreshold --threshold "$ERRORS_THRESHOLD" --treat-missing-data notBreaching \
  --alarm-actions "$topic" --ok-actions "$topic" "$(actions_flag "$alarm")"

alarm="${NAME}-proxy-slow"
log "알람 ${alarm} (Lambda Duration 5분 p90 > ${SLOW_P90_MS}ms)"
change cloudwatch put-metric-alarm --alarm-name "$alarm" \
  --alarm-description "parsing-proxy Lambda 응답 p90 이 ${SLOW_P90_MS}ms 초과 — AppSync 30초 한도에 가까움" \
  --namespace AWS/Lambda --metric-name Duration --dimensions "Name=FunctionName,Value=${proxy}" \
  --extended-statistic p90 --period 300 --evaluation-periods 1 \
  --comparison-operator GreaterThanThreshold --threshold "$SLOW_P90_MS" --treat-missing-data notBreaching \
  --alarm-actions "$topic" --ok-actions "$topic" "$(actions_flag "$alarm")"

if [ "$DRY_RUN" = 0 ]; then
  log "알람 상태"
  aws_ cloudwatch describe-alarms --alarm-name-prefix "${NAME}-" \
    --query 'MetricAlarms[].{name:AlarmName,state:StateValue,actions:ActionsEnabled}' --output table
fi
log "끝."
