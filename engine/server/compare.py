"""
사실검증(그라운딩) + 골든셋 비교 로직.

`engine-ai-prototype/compare.py`를 그대로 포팅했다(2026-09-18 재현성 실측으로 다듬은
최종 버전 — 19절 name_match 포함관계 규칙, 26-2절 계산값 그라운딩 인정 포함). 서버에서는
`grounding_check()`를 매 요청의 응답에 포함시켜 "이 답을 얼마나 믿을 수 있는지"를 클라이언트
에 같이 전달하는 용도로 쓴다. `compare_to_golden()`은 서버 자체 로직에서는 안 쓰이고,
`tools/golden_regression_check.py`가 골든셋 회귀 검사를 할 때만 가져다 쓴다.
"""
from __future__ import annotations

import difflib
import re

_PRICE_NUMBER_RE = re.compile(r"\d{1,3}(?:,\d{3})+|\d{4,}")
_PERCENT_RE = re.compile(r"(\d{1,2})\s*%")


def normalize_price_text(text: str) -> set[int]:
    """텍스트 안의 숫자 시퀀스(콤마 포함)를 정수 집합으로 뽑는다."""
    return {int(m.replace(",", "")) for m in _PRICE_NUMBER_RE.findall(text)}


def _extract_percents(text: str) -> set[int]:
    """원문 안의 "N%" 할인율만 따로 뽑는다. normalize_price_text의 숫자 패턴(콤마 포함 또는
    4자리 이상)은 1~2자리 할인율(예: "32%")을 못 잡기 때문에 별도 함수로 분리."""
    return {int(p) for p in _PERCENT_RE.findall(text)}


def _price_grounded(price, regular_price, text_numbers: set[int], percents: set[int]) -> bool:
    """가격이 원문에 리터럴로 있거나(직접 그라운딩), "정상가 − 즉시할인액"처럼 원문에 있는
    두 숫자의 차/비율로 정확히 재현되면(계산 그라운딩) 그라운딩된 것으로 인정한다."""
    if price is None:
        return False
    price = int(price)
    if price in text_numbers:
        return True
    if regular_price is None or int(regular_price) not in text_numbers:
        return False
    regular_price = int(regular_price)
    diff = regular_price - price
    if diff <= 0:
        return False
    # (a) 할인액이 원문에 그대로 있는 경우: 정상가 99,000 − 기본할인 64,200원 = 34,800
    if diff in text_numbers:
        return True
    # (b) 할인율(%)이 원문에 있고 그 비율로 정상가를 깎으면 반올림 오차(±1원) 안에서 price와
    #     일치하는 경우: 정상가 225,500 × (1−32%) = 153,340
    for pct in percents:
        if abs(round(regular_price * (100 - pct) / 100) - price) <= 1:
            return True
    return False


def most_prominent_prices(price_candidates: list[dict] | None) -> set[int]:
    """첫 화면에서 취소선 없이 가장 큰 글자로 표시된 가격(들). 같은 크기가 여럿이면 전부.
    후보가 없으면 빈 집합."""
    pool = [c for c in price_candidates or [] if c.get("first_screen") and not c.get("struck")]
    if not pool:
        return set()
    top = max(c["font_px"] for c in pool)
    return {int(c["value"]) for c in pool if c["font_px"] == top}


def _price_prominence(price, price_candidates: list[dict] | None) -> tuple[int | None, bool | None]:
    """(가장 크게 표시된 가격, AI가 고른 가격이 그것과 같은지). 2026-11 가격 정책("가장 크게
    홍보하는 가격")을 AI가 지켰는지 코드로 확인한다. 같은 크기가 여럿이면 대표 가격은 None으로 두고,
    그중 하나와 같으면 True. 판단할 근거(후보·가격)가 없으면 판정은 None."""
    top_values = most_prominent_prices(price_candidates)
    representative = next(iter(top_values)) if len(top_values) == 1 else None
    if price is None or not top_values:
        return representative, None
    return representative, int(price) in top_values


def grounding_check(
    extracted: dict,
    raw_text: str,
    image_candidates: list[str],
    price_candidates: list[dict] | None = None,
) -> dict:
    """AI가 뽑은 값이 실제 페이지 원문에 등장하는지 확인 (환각 방지 안전판).

    `price_is_most_prominent`는 원문 존재 여부와 별개로, 고른 가격이 화면에서 가장 큰 글자의
    가격인지를 본다. 측정 오차(같은 가격이 여러 크기로 표시, 몰마다 다른 마크업)가 있을 수 있어
    `all_grounded`에는 넣지 않는다 — 회귀 테스트와 로그에서 정책 준수율을 보는 용도."""
    price_info = extracted.get("price") or {}
    price, regular_price = price_info.get("unconditional_price"), price_info.get("regular_price")
    name = extracted.get("product_name")
    image = extracted.get("image_url")

    text_numbers = normalize_price_text(raw_text)
    price_grounded = _price_grounded(price, regular_price, text_numbers, _extract_percents(raw_text))

    name_grounded = bool(name) and _normalize_name(name)[:15] in _normalize_name(raw_text)

    image_grounded = bool(image) and (
        image in image_candidates or _basename(image) in map(_basename, image_candidates)
    )

    most_prominent_price, price_is_most_prominent = _price_prominence(price, price_candidates)

    return {
        "price_grounded": price_grounded,
        "name_grounded": name_grounded,
        "image_grounded": image_grounded,
        "all_grounded": price_grounded and name_grounded and image_grounded,
        "most_prominent_price": most_prominent_price,
        "price_is_most_prominent": price_is_most_prominent,
    }


def _normalize_name(s: str) -> str:
    return re.sub(r"\s+", "", s or "").lower()


def _basename(url: str) -> str:
    return url.rstrip("/").split("/")[-1].split("?")[0] if url else ""


def _numeric_tokens(s: str) -> set[str]:
    """URL 안에서 5자리 이상 숫자열(상품ID·타임스탬프 등)을 뽑는다."""
    return set(re.findall(r"\d{5,}", s or ""))


def _image_core_match(a: str, b: str) -> bool:
    """같은 이미지의 다른 해상도/썸네일 변형을 같은 이미지로 취급한다."""
    if _basename(a) == _basename(b):
        return True
    return bool(_numeric_tokens(a) & _numeric_tokens(b))


def _name_containment_match(a: str, b: str, min_len: int = 6) -> bool:
    """짧은 쪽 이름이 긴 쪽 이름에 연속 부분문자열로 포함되면 같은 상품으로 간주."""
    shorter, longer = (a, b) if len(a) <= len(b) else (b, a)
    return len(shorter) >= min_len and shorter in longer


def compare_to_golden(extracted: dict, golden: dict) -> dict:
    """골든셋(실제 확인된 값)과 AI 추출 결과를 비교. 정확 일치가 아니라 유사도 기반."""
    price = (extracted.get("price") or {}).get("unconditional_price")
    name = extracted.get("product_name") or ""
    image = extracted.get("image_url") or ""

    price_match = price is not None and int(price) == int(golden["price"])

    norm_name, norm_golden_name = _normalize_name(name), _normalize_name(golden["name"])
    name_ratio = difflib.SequenceMatcher(None, norm_name, norm_golden_name).ratio()
    name_match = name_ratio >= 0.8 or _name_containment_match(norm_name, norm_golden_name)

    image_match = bool(image) and _image_core_match(image, golden["image"])

    return {
        "price_match": price_match,
        "name_match": name_match,
        "name_similarity": round(name_ratio, 3),
        "image_match": image_match,
        "full_match": price_match and name_match and image_match,
    }
