"""
편집숍(무신사·29CM·4910·W컨셉) 입점 브랜드 목록을 brand_rules.json에 넣는다.

목록 만드는 법: 편집숍 앱·웹의 "브랜드" 메뉴(가나다/ABC 목록)에서 브랜드 이름을 복사해 텍스트 파일에
한 줄에 하나씩 붙여 넣는다. 한 줄에 한글·영문이 같이 있어도 된다("마뗑킴 MATIN KIM", "마뗑킴 / MATIN KIM").
자동 수집(크롤링)은 각 편집숍 이용약관을 확인한 뒤에만 한다 — 이 도구는 사람이 모은 목록만 받는다.

  python import_mall_brands.py --mall musinsa.com --file musinsa_brands.txt            # 미리보기
  python import_mall_brands.py --mall musinsa.com --file musinsa_brands.txt --write    # 저장
  python import_mall_brands.py --mall 29cm.co.kr --file 29cm.txt --write --add-unknown # 모르는 브랜드도 추가

--add-unknown: 규칙 파일에 없는 브랜드를 k_designer 분류로 새로 만든다(편집숍에 있는 브랜드는 대개
영패션·디자이너 브랜드). 백화점·SPA 브랜드면 나중에 category를 고친다.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

RULES = Path(__file__).resolve().parent.parent / "server" / "brand_rules.json"


def _key(name: str) -> str:
    return re.sub(r"[\s.\-_'’·]+", "", name.strip().lower())


def _names_in_line(line: str) -> list[str]:
    """'마뗑킴 / MATIN KIM' · '마뗑킴\tMATIN KIM' · '마뗑킴 MATIN KIM' → ['마뗑킴', 'MATIN KIM']."""
    line = line.strip()
    if not line or line.startswith("#"):
        return []
    parts = [p.strip() for p in re.split(r"\t|/|\|", line) if p.strip()]
    if len(parts) == 1:  # 한글과 영문이 공백으로만 붙어 있으면 나눈다
        m = re.match(r"^([^A-Za-z]+?)\s+([A-Za-z0-9].*)$", parts[0])
        if m:
            parts = [m.group(1).strip(), m.group(2).strip()]
    return parts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mall", required=True)
    ap.add_argument("--file", required=True, type=Path)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--add-unknown", action="store_true")
    args = ap.parse_args()

    data = json.loads(RULES.read_text(encoding="utf-8"))
    if args.mall not in (data.get("editshops") or []):
        print(f"{args.mall}은 editshops 목록에 없어요: {data.get('editshops')}")
        return 1
    index = {_key(a): name for name, info in data["brands"].items() for a in [name, *info.get("aliases", [])]}
    listed = data.setdefault("editshop_brands", {}).setdefault(args.mall, [])

    known, added, skipped = 0, 0, []
    for line in args.file.read_text(encoding="utf-8").splitlines():
        names = _names_in_line(line)
        if not names:
            continue
        brand = next((index[_key(n)] for n in names if _key(n) in index), None)
        if brand is None and args.add_unknown:
            brand = names[-1].lower() if re.search(r"[A-Za-z]", names[-1]) else names[0]
            data["brands"][brand] = {"aliases": names, "category": "k_designer"}
            for n in names:
                index[_key(n)] = brand
            added += 1
        if brand is None:
            skipped.append(" / ".join(names))
            continue
        if brand not in listed:
            listed.append(brand)
            known += 1
    listed.sort()

    print(f"{args.mall}: 입점 브랜드 {known}개 추가, 새 브랜드 {added}개 생성, 모르는 브랜드 {len(skipped)}개 건너뜀")
    for name in skipped[:30]:
        print("  건너뜀:", name)
    if len(skipped) > 30:
        print(f"  … 외 {len(skipped) - 30}개 (--add-unknown 으로 추가 가능)")
    if args.write:
        RULES.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("저장했어요:", RULES)
    else:
        print("미리보기예요. 저장하려면 --write")
    return 0


if __name__ == "__main__":
    sys.exit(main())
