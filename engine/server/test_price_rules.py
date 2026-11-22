"""price_rules.py — 에이블리 즉시할인가 규칙."""
import copy

import pytest
from price_rules import ably_instant_price, apply_price_rules

# 2026-11-22 로컬 렌더링(m.a-bly.com/goods/77103060 → mobile.a-bly.com) 화면 글자를 줄인 것.
# 웹(비로그인)은 에블프 쿠폰가 29,210 을 가장 크게 보여 주고, 즉시할인가 32,450 은 회색으로 작게 보인다.
ABLY_77103060 = (
    "미니포에 133.7만 도착보장 최저가도전 ABLY 단독 [컬러포인트🖤] 루이 홀스 후드집업 (5color) "
    "0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 일 남음 쿠폰적용가 34,900원 32,450원 16% 29,210 원 "
    "최대 649원 받기 공유하기 에블프 종료 시 0 1 2 3 4 5 6 7 8 9 , 0 1 2 3 4 5 6 7 8 9 원 비싸져요 "
    "나의 예상 구매가 20% 27,590원 상품 할인 즉시 할인 7% -2,450원 쿠폰 최대 할인 "
    "[🎁첫 구매 ONLY] 무조건 15% 할인쿠폰 받기 -4,860원 포인트 첫 결제 페이백 -582원 할인 쿠폰 받기"
)
# 04(2026-11-19)에서 본 다른 레이아웃(51469717): 쿠폰적용가 라벨 없이 정가·할인율·즉시할인가.
ABLY_51469717 = (
    "[뱃살커버/빅사이즈] 허리셔링 3사이즈 후드집업 통통제작 21,500원 7% 19,800원 공유하기 "
    "나의 예상 구매가 21% 16,830원 상품 할인 즉시 할인 7% -1,700원 쿠폰 최대 할인 "
    "[🎁첫 구매 ONLY] 무조건 15% 할인쿠폰 받기 -2,970원"
)


def _extracted(price, regular, ambiguous=False):
    return {"product_name": "후드집업", "image_url": None, "confidence": "high",
            "ambiguous": ambiguous, "ambiguity_reason": "가격 후보 여러 개" if ambiguous else None,
            "price": {"unconditional_price": price, "regular_price": regular, "currency": "KRW"}}


def test_ably_coupon_price_is_corrected_to_instant_discount_price():
    """운영에서 저장된 29,210(에블프 쿠폰가)을 32,450(정가 34,900 − 즉시 할인 2,450)으로."""
    extracted = _extracted(29210, 34900)
    note = apply_price_rules(extracted, ABLY_77103060, "mobile.a-bly.com")
    assert extracted["price"]["unconditional_price"] == 32450
    assert extracted["price"]["regular_price"] == 34900
    assert note and "29210 → 32450" in note


@pytest.mark.parametrize("picked", [27590, 26740, 29210])
def test_ably_other_conditional_prices_are_not_kept(picked):
    """예상 구매가·최대혜택가·쿠폰가 어느 것을 골라도 즉시할인가로."""
    extracted = _extracted(picked, 34900)
    apply_price_rules(extracted, ABLY_77103060, "m.a-bly.com")
    assert extracted["price"]["unconditional_price"] == 32450


def test_ably_regular_price_from_coupon_label_when_ai_missed_it():
    extracted = _extracted(29210, None)
    apply_price_rules(extracted, ABLY_77103060, "mobile.a-bly.com")
    assert extracted["price"] == {"unconditional_price": 32450, "regular_price": 34900, "currency": "KRW"}


def test_ably_ambiguous_abstention_is_filled_and_unflagged():
    extracted = _extracted(None, 34900, ambiguous=True)
    apply_price_rules(extracted, ABLY_77103060, "mobile.a-bly.com")
    assert extracted["price"]["unconditional_price"] == 32450
    assert extracted["ambiguous"] is False and extracted["ambiguity_reason"] is None


def test_ably_layout_without_coupon_label():
    extracted = _extracted(16830, 21500)
    apply_price_rules(extracted, ABLY_51469717, "mobile.a-bly.com")
    assert extracted["price"]["unconditional_price"] == 19800
    assert extracted["price"]["regular_price"] == 21500


def test_already_correct_is_left_alone():
    extracted = _extracted(32450, 34900)
    before = copy.deepcopy(extracted)
    assert apply_price_rules(extracted, ABLY_77103060, "mobile.a-bly.com") is None
    assert extracted == before


def test_other_malls_are_not_touched():
    extracted = _extracted(29210, 34900)
    before = copy.deepcopy(extracted)
    assert apply_price_rules(extracted, ABLY_77103060, "www.musinsa.com") is None
    assert apply_price_rules(extracted, ABLY_77103060, "fake-a-bly.com") is None
    assert extracted == before


@pytest.mark.parametrize(
    "text, regular",
    [
        # 즉시 할인 줄이 없음(할인 없는 상품, 또는 렌더링이 덜 됨)
        ("쿠폰적용가 34,900원 16% 29,210 원 나의 예상 구매가 20% 27,590원", 34900),
        # 계산값(32,450)이 화면에 없음 — 확인 못 하면 바꾸지 않는다
        ("쿠폰적용가 34,900원 16% 29,210 원 즉시 할인 7% -2,450원", 34900),
        # 정가를 알 수 없음(AI 도 못 찾고 쿠폰적용가 라벨도 없음)
        ("32,450원 16% 29,210 원 즉시 할인 7% -2,450원", None),
        # 즉시 할인 금액이 둘(옵션별 등) — 어느 것인지 모름
        ("쿠폰적용가 34,900원 32,450원 즉시 할인 7% -2,450원 즉시 할인 10% -3,490원", 34900),
    ],
)
def test_unverifiable_pages_keep_ai_value(text, regular):
    extracted = _extracted(29210, regular)
    before = copy.deepcopy(extracted)
    assert ably_instant_price(text, regular) is None
    assert apply_price_rules(extracted, text, "mobile.a-bly.com") is None
    assert extracted == before


def test_amount_must_not_be_part_of_a_bigger_number():
    """`132,450원` 안의 32,450 은 화면에 표시된 것으로 치지 않는다."""
    text = "쿠폰적용가 34,900원 132,450원 즉시 할인 7% -2,450원"
    assert ably_instant_price(text, 34900) is None
