"""
태그 찾기 결과 진단 — 요청마다 "왜 이렇게 끝났는지"를 한 단어(cause)로 정하고, 분석용 기록 한 줄을 만든다.

- diagnose(): 엔진 응답(dict) → (cause, flags). cause는 아래 CAUSES의 키 하나, flags는 같이 있었던 사정들.
- build_report(): 로그에 남길 익명 기록. tools/learn_from_feedback.py가 이 기록과 앱의 피드백(TagFeedback)을
  trace_id로 이어 붙여 원인별 집계·브랜드 규칙 학습을 한다.

개인정보를 넣지 않는다: 사진·사용자·기기 정보 없음. 태그에 인쇄된 상품 정보(브랜드·품번·상품명·가격·회사명)와
엔진이 열어 본 쇼핑몰 주소만 남는다.
"""
from __future__ import annotations

import time
import uuid

# cause 키 → (설명, 보통 해결 방법). 리포트 표에 그대로 쓴다.
CAUSES: dict[str, tuple[str, str]] = {
    "ok": ("찾음", "-"),
    "no_brand_no_code": ("태그에 브랜드·품번이 없음(일부러 안 찾음)", "해결 대상 아님"),
    "not_a_tag": ("태그 사진이 아님", "해결 대상 아님"),
    "no_code": ("품번을 못 읽음(브랜드는 있음 — 일부러 안 찾음)", "태그 읽기 프롬프트·브랜드 code_format 확인"),
    "no_brand": ("브랜드를 알 수 없음(품번은 있음 — 일부러 안 찾음)", "품번 모양(code_brands)·회사명(companies) 규칙 추가"),
    "search_error": ("검색 호출 실패(한도·오류)", "Gemini 키 한도·상태 확인"),
    "search_empty": ("검색이 후보를 하나도 못 가져옴", "브랜드 규칙(주소·편집숍 검색) 추가"),
    "search_redirect_only": ("검색 결과가 구글 우회 주소뿐이고 풀지 못함", "주소 따라가기 시간·차단 확인"),
    "page_blocked": ("후보 페이지를 열지 못함(봇 차단·빈 화면)", "휴대폰에서 열기(WebView) 검토"),
    "code_not_on_page": ("페이지는 열었지만 품번이 없음", "다른 상품이거나 품번 표기 방식이 다름 — 브랜드 code 변환 확인"),
    "unconfirmed": ("후보는 있지만 품번 확인 못 함(맞나요?)", "사용자 답(yes/no)으로 판단"),
    "timeout": ("시간 초과", "단계별 시간 확인"),
    "other": ("기타", "기록 직접 확인"),
}


def diagnose(body: dict) -> tuple[str, list[str]]:
    """엔진 응답 → (cause, flags)."""
    status = body.get("status")
    tag = body.get("tag") or {}
    checked = body.get("candidates_checked") or []
    reasons = [str(c.get("reason") or "") for c in checked]
    flags: list[str] = []
    if tag.get("brand_decided_by", "").startswith("모르는 브랜드"):
        flags.append("unknown_brand")
    if tag.get("brand_decided_by") == "품번 모양":
        flags.append("brand_from_code")
    if any("못 읽음" in r or "빈 화면" in r or "차단" in r for r in reasons):
        flags.append("page_blocked")
    if any(r.startswith("규칙(") for r in reasons):
        flags.append("rule_tried")

    if status == "found":
        return "ok", flags
    if body.get("skip_reason") in ("no_brand_no_code", "no_brand", "no_code"):
        return body["skip_reason"], flags
    if status == "not_a_tag":
        return "not_a_tag", flags
    if status == "needs_confirm":
        return "unconfirmed", flags
    note = str(body.get("note") or "")
    if "검색에 실패" in note or "한도" in note:
        return "search_error", flags
    if not str(tag.get("product_code") or "").strip() and not tag.get("other_codes"):
        return "no_code", flags
    if any("품번 없음" in r for r in reasons):
        return "code_not_on_page", flags
    if "page_blocked" in flags:
        return "page_blocked", flags
    if reasons and all("리다이렉트" in r for r in reasons):
        return "search_redirect_only", flags
    if not checked:
        return "search_empty", flags
    return "other", flags


def new_trace_id() -> str:
    """요청 하나를 가리키는 무작위 id — 앱 피드백과 엔진 기록을 이어 붙이는 데만 쓴다(사용자와 무관)."""
    return uuid.uuid4().hex[:16]


def build_report(body: dict, *, trace_id: str, stages: dict[str, int], total_ms: int,
                 search_query: str | None) -> dict:
    """로그 한 줄([identify-report] …)로 남길 기록. 사진·사용자 정보 없음."""
    tag = body.get("tag") or {}
    match = body.get("match") or {}
    cause, flags = diagnose(body)
    return {
        "v": 1,
        "trace_id": trace_id,
        "ts": int(time.time()),
        "status": body.get("status"),
        "cause": cause,
        "flags": flags,
        "brand_raw": tag.get("brand_ocr") if tag.get("brand_ocr") is not None else tag.get("brand"),
        "brand": tag.get("brand"),
        "brand_canonical": tag.get("brand_canonical"),
        "brand_category": tag.get("brand_category"),
        "brand_decided_by": tag.get("brand_decided_by"),
        "product_code": tag.get("product_code"),
        "other_codes": list(tag.get("other_codes") or [])[:5],
        "barcode": tag.get("barcode"),
        "product_name": tag.get("product_name"),
        "company": tag.get("company"),
        "website": tag.get("website"),
        "official_domain_hint": tag.get("official_domain_hint") or body.get("official_domain"),
        "search_query": search_query,
        "match": {k: match.get(k) for k in ("url", "host", "source", "via", "verified_by")} if match else None,
        "checked": [
            {"url": c.get("url"), "source": c.get("source"), "verified": c.get("verified"), "reason": c.get("reason")}
            for c in (body.get("candidates_checked") or [])[:8]
        ],
        "qr": [{"kind": q.get("kind"), "final_url": q.get("final_url"), "result": q.get("result")}
               for q in (body.get("qr") or [])],
        "stages_ms": stages,
        "total_ms": total_ms,
    }
