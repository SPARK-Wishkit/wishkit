"""
브랜드 이름 정리 + 모회사 쇼핑몰·브랜드별 주소 규칙 — 데이터는 brand_rules.json.

왜 JSON인가: 쇼핑몰은 주소 구조를 예고 없이 바꾼다. 규칙이 코드에 섞여 있으면 고칠 때마다 코드 리뷰·테스트·
배포가 필요하지만, 데이터 파일이면 한 줄 고쳐서 바로 반영할 수 있고 개발자가 아닌 팀원도 고칠 수 있다.
나중에 DB·관리 화면으로 옮기기도 쉽다(이 모듈의 load_rules만 바꾸면 됨).

- canonical_brand(): 태그에서 읽은 브랜드("8 seconds", "에잇세컨즈")를 하나의 이름("8seconds")으로.
- candidate_urls(): 태그 품번으로 열어 볼 주소들. 규칙이 있는 브랜드·몰만. 상품 주소를 바로 만들 수 있는
  몰은 상품 주소(kind=product), 상품 주소가 내부 번호인 몰은 몰 검색 결과 주소(kind=search).
- plan_for() / seller_hints(): 어디서 찾을지. 백화점 층 구성 기준을 빌린 브랜드 분류(컨템포러리·캐주얼·
  스포츠·SPA·K디자이너 등)마다 찾는 순서가 있고, 모르는 브랜드는 공식몰부터 찾는다.

⚠️ 이 주소들은 우리가 품번으로 "만든" 것이라, 주소에 품번이 있다는 건 증거가 아니다. 반드시 페이지를
열어 그 안에서 품번을 확인한다(tag_identify._try_brand_rules).
"""
from __future__ import annotations

import json
import logging
import re
import urllib.parse
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

logger = logging.getLogger("extract-server")

RULES_PATH = Path(__file__).with_name("brand_rules.json")
# 피드백으로 자동 학습한 규칙(tools/learn_from_feedback.py가 쓴다). 사람이 고치는 brand_rules.json과 따로 두고,
# 둘이 겹치면 사람이 쓴 쪽이 이긴다. 학습 규칙도 엔진이 페이지에서 품번을 확인해야 "찾음"이 되므로 틀려도 안전하다.
LEARNED_PATH = Path(__file__).with_name("brand_rules.learned.json")
MAX_RULE_URLS = 3  # 한 태그에서 열어 볼 규칙 주소 최대 개수(렌더링 하나에 수 초가 걸린다)


@dataclass(frozen=True)
class RuleUrl:
    url: str
    brand: str  # 정리된 브랜드 이름
    mall: str | None  # 모회사 몰 키(ssf 등). 브랜드 전용 규칙이면 None
    label: str  # 로그·후보 목록에 남길 이름("SSF샵 (삼성물산 패션)" 등)
    # 'product': url이 곧 상품 페이지. 'search': url은 몰 검색 결과 — 거기서 product_id_pattern으로 첫 상품
    # 번호를 찾아 product_url({id})로 상품 페이지를 만든다(상품 주소가 내부 번호인 몰).
    kind: str = "product"
    product_id_pattern: str = ""
    product_url: str = ""


def _key(name: str | None) -> str:
    """비교용 키: 소문자, 공백·구두점 제거. '8 Seconds' == '8seconds', 'JUUN.J' == 'juunj'."""
    return re.sub(r"[\s.\-_'’·]+", "", (name or "").strip().lower())


@lru_cache(maxsize=1)
def load_rules(path: str = str(RULES_PATH), learned_path: str = str(LEARNED_PATH)) -> dict:
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:  # 규칙 파일이 깨져도 태그 찾기는 계속한다(검색으로)
        logger.warning("[identify] 브랜드 규칙 파일을 읽지 못함: %s", exc)
        return {"brands": {}, "malls": {}, "_alias_index": {}}
    data.setdefault("brands", {})
    data.setdefault("malls", {})
    _merge_learned(data, learned_path)
    data["_alias_index"] = {
        _key(alias): name
        for name, info in data["brands"].items()
        for alias in [name, *(info.get("aliases") or [])]
    }
    return data


def _merge_learned(data: dict, learned_path: str) -> None:
    """학습 규칙을 합친다. 사람이 쓴 브랜드는 그대로 두고 별칭·판매처·주소 규칙만 덧붙인다."""
    try:
        learned = json.loads(Path(learned_path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return
    except (OSError, ValueError) as exc:
        logger.warning("[identify] 학습 규칙 파일을 읽지 못함(무시): %s", exc)
        return
    for name, info in (learned.get("brands") or {}).items():
        base = data["brands"].get(name)
        if base is None:
            data["brands"][name] = {k: v for k, v in info.items() if k != "evidence"}
            continue
        for key in ("aliases", "rules", "sellers"):
            extra = [x for x in info.get(key) or [] if x not in (base.get(key) or [])]
            if extra:
                base[key] = [*(base.get(key) or []), *extra]
    for alias, name in (learned.get("aliases") or {}).items():
        if name in data["brands"] and alias not in data["brands"][name].setdefault("aliases", []):
            data["brands"][name]["aliases"].append(alias)
    shops = data.setdefault("editshop_brands", {})
    for shop, brands in (learned.get("editshop_brands") or {}).items():
        shops[shop] = sorted({*(shops.get(shop) or []), *brands})


def canonical_brand(brand: str | None, rules: dict | None = None) -> str | None:
    """태그 브랜드 → 규칙 파일의 브랜드 이름. 모르는 브랜드면 None."""
    rules = rules or load_rules()
    return rules["_alias_index"].get(_key(brand)) if brand else None


def _fill(template: str, code: str, pattern: str | None, brand: str | None = None,
          slug: str | None = None) -> str | None:
    """주소 틀 채우기. {code} {code_compact} {brand}(검색어용 브랜드 이름, 주소 인코딩)
    {brand_slug}(편집숍 안 브랜드 주소 이름 — 규칙 파일의 editshop_slugs, 없으면 영문 소문자·숫자만)."""
    upper = code.upper().replace(" ", "")
    base = re.sub(r"[-_/][0-9A-Z]{1,3}$", "", upper)  # 색상·사이즈 꼬리(-01, _002) 떼기 — 없으면 그대로
    values = {"code": urllib.parse.quote(code.replace(" ", "")), "code_compact": re.sub(r"[^0-9A-Z]", "", upper),
              "code_base": urllib.parse.quote(base)}
    if brand:
        values["brand"] = urllib.parse.quote(brand.strip())
        derived = re.sub(r"[^0-9a-z]", "", brand.lower())
        values["brand_slug"] = derived if slug is None else slug
        if "{brand_slug}" in template and not values["brand_slug"]:
            return None  # 브랜드 페이지가 없거나(빈 값) 한글 이름뿐이라 영문 주소 이름을 만들 수 없다
    elif "{brand" in template:
        return None
    if pattern:
        m = re.match(pattern, upper)
        if not m:
            return None
        values.update({k: v for k, v in m.groupdict().items() if v})
    try:
        return template.format(**values)
    except (KeyError, IndexError, ValueError):
        return None


_SOCIAL_HOSTS = ("instagram.com", "facebook.com", "youtube.com", "twitter.com", "x.com", "tiktok.com",
                 "kakao.com", "naver.com", "linktr.ee")


@dataclass(frozen=True)
class BrandPlan:
    """태그 하나를 어디서 찾을지. decided_by는 왜 그렇게 정했는지(로그로 남겨 규칙을 고칠 근거로 쓴다)."""
    brand: str | None  # 규칙 파일의 브랜드 이름(모르면 None)
    category: str  # categories의 키(백화점 층 구성 기준을 빌린 분류)
    order: tuple[str, ...]  # 찾는 순서: official | parent_mall | dept_store | editshop
    mall: str | None  # 모회사 몰 키
    official_domain: str | None
    decided_by: str

    @property
    def find_official_first(self) -> bool:
        """공식몰을 먼저 찾아야 하는데 도메인을 모름 → 검색 단계에서 공식 홈페이지부터 찾게 한다."""
        return bool(self.order) and self.order[0] == "official" and not self.official_domain


def _company_key(name: str | None) -> str:
    s = re.sub(r"\(주\)|㈜|주식회사|\(유\)|유한회사|co\.?,?\s*ltd\.?|inc\.?|corp\.?", "", (name or "").lower())
    return re.sub(r"[\s.\-_,()]+", "", s)


def _website_domain(raw: str | None) -> str | None:
    """태그에 인쇄된 웹사이트 → 도메인. SNS·포털은 공식몰이 아니라 버린다."""
    text = (raw or "").strip().lower()
    m = re.search(r"([a-z0-9-]+(?:\.[a-z0-9-]+)+)", text.replace("https://", "").replace("http://", ""))
    if not m:
        return None
    host = m.group(1).removeprefix("www.").removeprefix("m.")
    if any(host == s or host.endswith("." + s) for s in _SOCIAL_HOSTS):
        return None
    return host


def _order(rules: dict, category: str) -> tuple[str, ...]:
    cat = rules.get("categories", {}).get(category) or rules.get("categories", {}).get("unknown") or {}
    return tuple(cat.get("order") or ("official", "editshop"))


def brand_from_code(tag: dict, rules: dict | None = None) -> str | None:
    """품번(없으면 기타 코드) 모양으로 브랜드를 정한다 — 태그에서 브랜드를 못 읽었거나 'NBA'처럼 잘못 읽은 경우.
    규칙 파일의 code_brands 정규식을 쓴다(반스 VN000…, 뉴발란스 NB…)."""
    rules = rules or load_rules()
    codes = [tag.get("product_code"), *(tag.get("other_codes") or [])]
    for entry in rules.get("code_brands") or []:
        pattern = re.compile(entry["pattern"])
        for code in codes:
            compact = re.sub(r"[^0-9A-Za-z]", "", str(code or "")).upper()
            if compact and pattern.match(compact) and entry["brand"] in rules["brands"]:
                return entry["brand"]
    return None


def promote_code(tag: dict, rules: dict | None = None) -> str | None:
    """브랜드의 품번 모양(code_format)과 맞는 기타 코드가 있으면 그걸 품번으로 쓴다. 바꾸지 않으면 None.
    아디다스 태그는 품번 칸이 비었거나 내부 번호(96000195)가 들어가고, 진짜 품번(KR9552)이 기타 코드에 있다."""
    rules = rules or load_rules()
    brand = canonical_brand(tag.get("brand"), rules) or brand_from_code(tag, rules)
    fmt = (rules["brands"].get(brand) or {}).get("code_format") if brand else None
    if not fmt:
        return None
    pattern = re.compile(fmt)
    current = re.sub(r"[^0-9A-Za-z]", "", str(tag.get("product_code") or "")).upper()
    if current and pattern.match(current):
        return None
    for code in tag.get("other_codes") or []:
        compact = re.sub(r"[^0-9A-Za-z]", "", str(code or "")).upper()
        if pattern.match(compact):
            return compact
    return None


def plan_for(tag: dict, rules: dict | None = None) -> BrandPlan:
    """태그를 보고 어디서 찾을지 정한다. 순서(먼저 걸리는 것):
    1. 브랜드 목록에 있는 브랜드 → 그 브랜드 분류(category)의 찾는 순서
    2. 태그에 인쇄된 회사명이 아는 회사 → 모회사 몰 → 백화점 몰 → 공식몰
    3. 그 밖(모르는 브랜드) → 공식몰 먼저(태그에 웹사이트가 인쇄돼 있으면 그 사이트), 그다음 편집숍
    (QR이 가리킨 사이트는 이보다 먼저, tag_identify의 QR 단계에서 쓴다.)"""
    rules = rules or load_rules()
    brand = canonical_brand(tag.get("brand"), rules)
    decided = "브랜드 목록"
    if not brand:
        brand = brand_from_code(tag, rules)
        decided = "품번 모양"
    website = _website_domain(tag.get("website"))
    if brand:
        info = rules["brands"][brand]
        category = info.get("category") or "unknown"
        return BrandPlan(brand, category, _order(rules, category), info.get("mall"),
                         info.get("official_domain") or website, decided)
    company_mall = rules.get("companies", {}).get(_company_key(tag.get("company")))
    if company_mall and company_mall in rules["malls"]:
        return BrandPlan(None, "unknown", ("parent_mall", "dept_store", "official"), company_mall, website,
                         f"태그 회사명({tag.get('company')})")
    if website:
        return BrandPlan(None, "unknown", _order(rules, "unknown"), None, website, f"태그 인쇄 주소({website})")
    return BrandPlan(None, "unknown", _order(rules, "unknown"), None, None, "모르는 브랜드 — 공식몰부터")


def uses_editshop_rules(plan: BrandPlan, info: dict, rules: dict) -> bool:
    """편집숍(무신사 등)을 엔진이 직접 열어 볼지. 2026-11-10 결정:
    - 젊은 브랜드(찾는 순서가 편집숍부터) → 예
    - 그 밖의 브랜드 → 편집숍 입점이 확인됐거나(editshop_brands, 자동 학습 포함) editshop_first일 때만
    - 모르는 브랜드 → 아니오(공식몰부터 — 검색 단계가 공식몰을 먼저 찾고, 편집숍은 검색 힌트로만)
    직접 열지 않더라도 편집숍은 검색 단계의 판매처 힌트(seller_hints)로는 계속 쓴다."""
    if "editshop" not in plan.order:
        return False
    if plan.order[0] == "editshop" or info.get("editshop_first"):
        return True
    listed = rules.get("editshop_brands") or {}
    return bool(plan.brand) and any(plan.brand in (bs or []) for bs in listed.values())


def candidate_urls(tag: dict, rules: dict | None = None) -> list[RuleUrl]:
    """태그 품번으로 만든 주소(규칙이 있는 브랜드·몰만). 브랜드 전용 규칙 → 모회사 몰 규칙 순."""
    rules = rules or load_rules()
    plan = plan_for(tag, rules)
    code = str(tag.get("product_code") or "").strip()
    if not code:
        return []
    info = (rules["brands"].get(plan.brand) or {}) if plan.brand else {}
    mall = (rules["malls"].get(plan.mall) or {}) if plan.mall else {}
    label_brand = plan.brand or tag.get("brand") or "?"

    out: list[RuleUrl] = []
    sources = [(r, None, label_brand) for r in info.get("rules") or []]
    sources += [(r, plan.mall, mall.get("name") or plan.mall) for r in mall.get("rules") or []]
    if uses_editshop_rules(plan, info, rules):  # 편집숍 검색 규칙 — 입점했다고 알려진 편집숍부터
        listed = rules.get("editshop_brands") or {}
        shops = _editshops_for(plan.brand, rules)
        if plan.order[:1] != ("editshop",) and not info.get("editshop_first"):
            # 젊은 브랜드가 아니면, 입점이 확인된 편집숍에서만 직접 찾는다(아디다스 → 무신사 등).
            shops = [s for s in shops if plan.brand in (listed.get(s) or [])]
        shop_sources = [(r, None, shop) for shop in shops
                        for r in (rules.get("editshop_rules") or {}).get(shop) or []]
        # 공식몰이 서버를 막는 브랜드(editshop_first)는 편집숍을 먼저 본다(2026-11-09 뉴발란스: 공식몰 빈 화면, 무신사에서 찾음).
        # 그래도 브랜드 규칙은 버리지 않게, 편집숍의 첫 규칙(브랜드 안 검색)만 앞으로 보낸다.
        if info.get("editshop_first"):
            sources = [*shop_sources, *sources]
        else:
            sources = [*sources, *shop_sources]
    # 검색어용 브랜드 이름: 태그에 적힌 그대로(영문이 있으면 영문). 규칙 파일에서만 알아낸 경우엔 규칙 이름.
    brand_text = str(tag.get("brand") or "").strip() or plan.brand
    slugs = info.get("editshop_slugs") or {}
    # 브랜드 주소 이름은 규칙 이름(영문)이 태그 글자보다 정확하다(태그에 한글만 있을 수 있음).
    slug_source = plan.brand if plan.brand and re.search(r"[a-z]", plan.brand) else brand_text
    names = info.get("editshop_names") or {}
    korean = next((a for a in info.get("aliases") or [] if re.search(r"[가-힣]", a)), None)
    for rule, mk, label in sources:
        kind = "search" if rule.get("search_url") else "product"
        if label in slugs:  # 규칙 파일에 적힌 값(빈 문자열 = 그 편집숍에 브랜드 페이지 없음)
            slug = slugs[label]
        else:
            slug = re.sub(r"[^0-9a-z]", "", str(slug_source).lower()) if slug_source else None
        # 편집숍 검색어의 브랜드 이름: 편집숍이 쓰는 이름 → 한글 별칭 → 태그 글자(태그마다 "new", "NB"처럼 들쭉날쭉해서)
        search_brand = names.get(label) or (korean if label in (rules.get("editshops") or []) else None) or brand_text
        url = _fill(rule.get("search_url") or rule.get("url", ""), code, rule.get("code_pattern"), search_brand, slug)
        if url and all(u.url != url for u in out):
            out.append(RuleUrl(url=url, brand=label_brand, mall=mk, label=label, kind=kind,
                               product_id_pattern=rule.get("product_id_pattern", ""),
                               product_url=rule.get("product_url", "")))
        if len(out) >= MAX_RULE_URLS:
            break
    return out


def category_of(tag: dict, rules: dict | None = None) -> str:
    return plan_for(tag, rules).category


def official_domain(tag: dict, rules: dict | None = None) -> str | None:
    return plan_for(tag, rules).official_domain


def _editshops_for(brand: str | None, rules: dict) -> list[str]:
    """편집숍 목록. 이 브랜드가 입점했다고 알려진 편집숍을 앞으로."""
    shops = list(rules.get("editshops") or [])
    listed = rules.get("editshop_brands") or {}
    known = [shop for shop in shops if brand and brand in (listed.get(shop) or [])]
    return known + [shop for shop in shops if shop not in known]


def seller_hints(tag: dict, rules: dict | None = None) -> list[str]:
    """검색에 줄 판매처 힌트(도메인 목록) — 분류의 찾는 순서대로 펼친 것. 공식몰 도메인을 모르면 빠진다
    (그때는 plan.find_official_first로 검색 단계가 공식 홈페이지부터 찾는다)."""
    rules = rules or load_rules()
    plan = plan_for(tag, rules)
    # 학습으로 알게 된 판매처(사용자가 "맞아요"를 누른 사이트)가 있으면 맨 앞에.
    out: list[str] = list(((rules["brands"].get(plan.brand) or {}).get("sellers") or []) if plan.brand else [])
    for step in plan.order:
        if step == "official" and plan.official_domain:
            out.append(plan.official_domain)
        elif step == "parent_mall" and plan.mall:
            domain = (rules["malls"].get(plan.mall) or {}).get("domain")
            if domain:
                out.append(domain)
        elif step == "dept_store":
            out.extend(rules.get("dept_store_malls") or [])
        elif step == "editshop":
            out.extend(_editshops_for(plan.brand, rules))
    return list(dict.fromkeys(out))
