"""
몰별 가격 후처리 — AI 가 고른 가격을 페이지 글자로 확인할 수 있는 규칙으로 바로잡는다.

에이블리(a-bly.com)
- 정책: 조건 없는 가격 = 정가 − "즉시 할인" 금액(쿠폰·첫구매·최대혜택·예상 구매가는 조건부라 제외).
- 문제(2026-11-22 운영, 상품 77103060): 웹 페이지(비로그인)는
  `쿠폰적용가 34,900원(취소선) 32,450원 16% 29,210원` 처럼 **에블프 쿠폰가(29,210)를 가장 크게** 보여 주고,
  메타 `product:price:amount` 도 29,210 이다. 아래 상세에는 `즉시 할인 7% -2,450원` 이 따로 있다.
  프롬프트 few-shot 1번이 "정가 − 즉시할인액"을 지시하는데도 Gemini 가 29,210 을 고른 일이 있어(같은 상품이
  오전엔 32,450, 오후엔 29,210) 규칙으로 고정한다.
- 규칙: 페이지 글자에 `즉시 할인 N% -X원` 이 정확히 한 금액으로 있고, 정가 R(AI 의 regular_price 또는
  `쿠폰적용가` 바로 뒤 금액)이 페이지에 있고, R − X 도 `…원` 으로 페이지에 표시돼 있을 때만 그 값으로 바꾼다.
  하나라도 확인이 안 되면 AI 결과를 그대로 둔다(틀린 값보다 빈 값/원래 값이 안전).
"""
from __future__ import annotations

import re

ABLY_HOST = "a-bly.com"

_INSTANT_DISCOUNT = re.compile(r"즉시\s*할인\s*\d+\s*%\s*-\s*([\d,]+)\s*원")
_COUPON_LABEL_FIRST_PRICE = re.compile(r"쿠폰적용가\s*([\d,]+)\s*원")


def _is_ably(host: str | None) -> bool:
    host = (host or "").lower()
    return host == ABLY_HOST or host.endswith("." + ABLY_HOST)


def _won(text: str) -> int | None:
    digits = text.replace(",", "")
    return int(digits) if digits.isdigit() else None


def _shown_as_won(raw_text: str, amount: int) -> bool:
    """`32,450원`·`32450 원` 처럼 금액이 원 단위로 화면 글자에 있는지(앞뒤 숫자와 붙은 경우 제외)."""
    pattern = rf"(?<![\d,])(?:{amount:,}|{amount})\s*원"
    return re.search(pattern, raw_text) is not None


def ably_instant_price(raw_text: str, regular_price) -> tuple[int, int] | None:
    """에이블리 페이지 글자에서 (조건 없는 가격, 정가)를 확인할 수 있으면 돌려준다. 못 하면 None."""
    amounts = {_won(m) for m in _INSTANT_DISCOUNT.findall(raw_text or "")} - {None}
    if len(amounts) != 1:
        return None
    discount = amounts.pop()

    candidates: list[int] = []
    if isinstance(regular_price, (int, float)) and regular_price > 0:
        candidates.append(int(regular_price))
    labeled = _COUPON_LABEL_FIRST_PRICE.search(raw_text)
    if labeled and (value := _won(labeled.group(1))):
        candidates.append(value)

    for regular in candidates:
        price = regular - discount
        if price > 0 and _shown_as_won(raw_text, regular) and _shown_as_won(raw_text, price):
            return price, regular
    return None


def apply_price_rules(extracted: dict, raw_text: str, host: str | None) -> str | None:
    """`extracted` 를 제자리에서 고친다. 고쳤으면 로그용 설명을, 아니면 None 을 돌려준다."""
    if not _is_ably(host):
        return None
    price_info = extracted.get("price") or {}
    found = ably_instant_price(raw_text, price_info.get("regular_price"))
    if not found:
        return None
    price, regular = found
    before = price_info.get("unconditional_price")
    if before == price and price_info.get("regular_price") == regular and not extracted.get("ambiguous"):
        return None
    extracted["price"] = {**price_info, "unconditional_price": price, "regular_price": regular,
                          "currency": price_info.get("currency") or "KRW"}
    extracted["ambiguous"] = False
    extracted["ambiguity_reason"] = None
    return f"에이블리 즉시할인가로 교정: {before} → {price} (정가 {regular})"
