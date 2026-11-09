"""
브랜드 이름 정리 + 모회사 쇼핑몰·브랜드별 주소 규칙 — 데이터는 brand_rules.json.

왜 JSON인가: 쇼핑몰은 주소 구조를 예고 없이 바꾼다. 규칙이 코드에 섞여 있으면 고칠 때마다 코드 리뷰·테스트·
배포가 필요하지만, 데이터 파일이면 한 줄 고쳐서 바로 반영할 수 있고 개발자가 아닌 팀원도 고칠 수 있다.
나중에 DB·관리 화면으로 옮기기도 쉽다(이 모듈의 load_rules만 바꾸면 됨).

- canonical_brand(): 태그에서 읽은 브랜드("8 seconds", "에잇세컨즈")를 하나의 이름("8seconds")으로.
- candidate_urls(): 태그 품번으로 바로 열어 볼 상품 주소들. 규칙이 있는 브랜드·몰만.
- channel_of() / seller_hints() / official_domain(): 브랜드 종류별로 어디서 찾을지.
  백화점 브랜드 → 모회사 몰, 젊은 브랜드(처음 보는 브랜드 포함) → 무신사·29CM, SPA·글로벌 → 공식몰.

⚠️ 이 주소들은 우리가 품번으로 "만든" 것이라, 주소에 품번이 있다는 건 증거가 아니다. 반드시 페이지를
열어 그 안에서 품번을 확인한다(tag_identify._try_brand_rules).
"""
from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

logger = logging.getLogger("extract-server")

RULES_PATH = Path(__file__).with_name("brand_rules.json")
MAX_RULE_URLS = 2  # 한 태그에서 열어 볼 규칙 주소 최대 개수(렌더링 하나에 수 초가 걸린다)


@dataclass(frozen=True)
class RuleUrl:
    url: str
    brand: str  # 정리된 브랜드 이름
    mall: str | None  # 모회사 몰 키(ssf 등). 브랜드 전용 규칙이면 None
    label: str  # 로그·후보 목록에 남길 이름("SSF샵 (삼성물산 패션)" 등)


def _key(name: str | None) -> str:
    """비교용 키: 소문자, 공백·구두점 제거. '8 Seconds' == '8seconds', 'JUUN.J' == 'juunj'."""
    return re.sub(r"[\s.\-_'’·]+", "", (name or "").strip().lower())


@lru_cache(maxsize=1)
def load_rules(path: str = str(RULES_PATH)) -> dict:
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:  # 규칙 파일이 깨져도 태그 찾기는 계속한다(검색으로)
        logger.warning("[identify] 브랜드 규칙 파일을 읽지 못함: %s", exc)
        return {"brands": {}, "malls": {}}
    data.setdefault("brands", {})
    data.setdefault("malls", {})
    data["_alias_index"] = {
        _key(alias): name
        for name, info in data["brands"].items()
        for alias in [name, *(info.get("aliases") or [])]
    }
    return data


def canonical_brand(brand: str | None, rules: dict | None = None) -> str | None:
    """태그 브랜드 → 규칙 파일의 브랜드 이름. 모르는 브랜드면 None."""
    rules = rules or load_rules()
    return rules["_alias_index"].get(_key(brand)) if brand else None


def _fill(template: str, code: str, pattern: str | None) -> str | None:
    upper = code.upper().replace(" ", "")
    values = {"code": code.replace(" ", ""), "code_compact": re.sub(r"[^0-9A-Z]", "", upper)}
    if pattern:
        m = re.match(pattern, upper)
        if not m:
            return None
        values.update({k: v for k, v in m.groupdict().items() if v})
    try:
        return template.format(**values)
    except (KeyError, IndexError, ValueError):
        return None


def candidate_urls(tag: dict, rules: dict | None = None) -> list[RuleUrl]:
    """태그 품번으로 만든 상품 주소(규칙이 있는 브랜드만). 브랜드 전용 규칙 → 모회사 몰 규칙 순."""
    rules = rules or load_rules()
    brand = canonical_brand(tag.get("brand"), rules)
    code = str(tag.get("product_code") or "").strip()
    if not brand or not code:
        return []
    info = rules["brands"].get(brand) or {}
    mall_key = info.get("mall")
    mall = (rules["malls"].get(mall_key) or {}) if mall_key else {}

    out: list[RuleUrl] = []
    sources = [(r, None, brand) for r in info.get("rules") or []]
    sources += [(r, mall_key, mall.get("name") or mall_key) for r in mall.get("rules") or []]
    for rule, mk, label in sources:
        url = _fill(rule.get("url", ""), code, rule.get("code_pattern"))
        if url and all(u.url != url for u in out):
            out.append(RuleUrl(url=url, brand=brand, mall=mk, label=label))
        if len(out) >= MAX_RULE_URLS:
            break
    return out


def channel_of(tag: dict, rules: dict | None = None) -> str:
    """이 브랜드를 어디서 찾을지: 'dept'(모회사 몰) | 'youth'(무신사·29CM) | 'official'(공식몰).
    규칙 파일에 없는 브랜드는 default_channel(youth) — 처음 보는 브랜드는 대개 온라인 편집숍 브랜드다."""
    rules = rules or load_rules()
    brand = canonical_brand(tag.get("brand"), rules)
    info = (rules["brands"].get(brand) or {}) if brand else {}
    return info.get("channel") or rules.get("default_channel") or "youth"


def official_domain(tag: dict, rules: dict | None = None) -> str | None:
    """SPA·글로벌 브랜드의 공식몰 도메인(검색 단계의 공식몰 판단에 쓴다). 모르면 None."""
    rules = rules or load_rules()
    brand = canonical_brand(tag.get("brand"), rules)
    return (rules["brands"].get(brand) or {}).get("official_domain") if brand else None


def seller_hints(tag: dict, rules: dict | None = None) -> list[str]:
    """검색에 줄 판매처 힌트(도메인 목록). 채널에 따라: 모회사 몰 / 무신사·29CM / 공식몰."""
    rules = rules or load_rules()
    brand = canonical_brand(tag.get("brand"), rules)
    info = (rules["brands"].get(brand) or {}) if brand else {}
    channel = channel_of(tag, rules)
    if channel == "dept":
        domain = (rules["malls"].get(info.get("mall")) or {}).get("domain")
        return [domain] if domain else []
    if channel == "official":
        return [info["official_domain"]] if info.get("official_domain") else []
    return list((rules.get("channels", {}).get(channel) or {}).get("sellers") or [])
