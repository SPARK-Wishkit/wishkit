"""
brand_rules.json 점검 — 규칙 파일을 고친 뒤나 한 달에 한 번 돌린다(엔진 서버는 안 켜도 됨).

  python check_brand_rules.py            # 별칭 겹침 + 몰/공식몰 도메인이 열리는지
  python check_brand_rules.py --offline  # 네트워크 없이 파일 형식·별칭만

확인하는 것
  1. 같은 별칭이 두 브랜드에 들어 있지 않은지(어느 브랜드로 정리될지 모호해짐)
  2. 브랜드의 mall이 malls에 있는지
  3. 몰·공식몰 도메인이 실제로 열리는지(https 요청이 200~399로 끝나는지) — 도메인이 바뀌었거나
     잘못 적힌 걸 찾는다. 공식몰이 봇을 막아 403이 나는 건 "확인 필요"로만 표시한다.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

RULES = Path(__file__).resolve().parent.parent / "server" / "brand_rules.json"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")


def _key(name: str) -> str:
    return re.sub(r"[\s.\-_'’·]+", "", name.strip().lower())


def check_file(data: dict) -> list[str]:
    problems: list[str] = []
    seen: dict[str, str] = {}
    for name, info in data.get("brands", {}).items():
        for alias in [name, *(info.get("aliases") or [])]:
            k = _key(alias)
            if k in seen and seen[k] != name:
                problems.append(f"별칭 겹침: '{alias}' → {seen[k]} / {name}")
            seen[k] = name
        mall = info.get("mall")
        if mall and mall not in data.get("malls", {}):
            problems.append(f"{name}: mall '{mall}'이 malls에 없음")
        if info.get("category") not in data.get("categories", {}):
            problems.append(f"{name}: category '{info.get('category')}'이 categories에 없음")
    for shop, brands in (data.get("editshop_brands") or {}).items():
        if shop not in (data.get("editshops") or []):
            problems.append(f"editshop_brands의 '{shop}'이 editshops에 없음")
        for b in brands:
            if b not in data.get("brands", {}):
                problems.append(f"{shop} 입점 브랜드 '{b}'가 brands에 없음")
    return problems


def check_domain(domain: str) -> str:
    req = urllib.request.Request(f"https://{domain}/", headers={"User-Agent": UA}, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            return f"OK {resp.status}"
    except urllib.error.HTTPError as exc:
        return f"확인 필요 {exc.code}" if exc.code in (401, 403, 429) else f"실패 {exc.code}"
    except Exception as exc:  # noqa: BLE001
        return f"실패 {type(exc).__name__}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--offline", action="store_true")
    args = ap.parse_args()

    data = json.loads(RULES.read_text(encoding="utf-8"))
    problems = check_file(data)
    for p in problems:
        print("[파일]", p)
    print(f"브랜드 {len(data['brands'])}개, 몰 {len(data['malls'])}개 — 파일 문제 {len(problems)}건")
    if args.offline:
        return 1 if problems else 0

    domains: dict[str, list[str]] = {}
    for key, mall in data["malls"].items():
        domains.setdefault(mall["domain"], []).append(f"몰:{key}")
    for name, info in data["brands"].items():
        if info.get("official_domain"):
            domains.setdefault(info["official_domain"], []).append(name)
    failed = 0
    for domain, owners in sorted(domains.items()):
        result = check_domain(domain)
        if not result.startswith("OK"):
            failed += 1
        print(f"[{result:>10}] {domain:28s} ← {', '.join(owners)}")
    print(f"\n도메인 {len(domains)}개 중 OK 아님 {failed}개 — '실패'는 도메인이 틀렸거나 바뀌었을 수 있어요.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
