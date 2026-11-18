"""
실패한 태그 보관 — 엔진이 못 찾은(또는 확인 못 한) 태그의 사진과 읽은 내용을 모아 둔다.
tools/discover_rules.py가 이걸 다시 돌려 보며 브랜드별 새 규칙을 찾고, 사람이 볼 때도 쓴다.

켜는 법(환경 변수, 둘 다 비우면 꺼짐 — 기본값 꺼짐):
  TAG_FAILURE_DIR=/경로          로컬 폴더에 저장(개발·테스트용)
  TAG_FAILURE_S3_BUCKET=버킷이름  S3에 저장(운영). 접두사는 TAG_FAILURE_S3_PREFIX(기본 tag-failures/)
     → 엔진 태스크 역할에 그 접두사로의 s3:PutObject 권한이 필요하고, 버킷 수명 주기 규칙으로
       보관 기간(예: 90일)을 정해 두는 걸 권한다.

저장하는 것: 사진 1장(JPEG로 다시 저장해 촬영 위치·기기 정보 같은 메타데이터를 지움) + 기록 JSON
            (failure_report.build_report와 같은 내용: 브랜드·품번·원인 등). 사용자 id·기기 정보는 없다.
⚠️ 운영에서 켜기 전에 개인정보 처리방침에 "인식 개선을 위해 인식에 실패한 태그 사진을 보관"을 반영할 것.
   사진에 손·얼굴이 같이 찍힐 수 있다.

저장은 응답을 늦추지 않게 백그라운드에서 하고, 실패해도 요청에는 영향이 없다.
"""
from __future__ import annotations

import io
import json
import logging
import os
import time
from pathlib import Path

logger = logging.getLogger("extract-server")

# 이 원인들만 보관한다(찾음·태그 아님은 보관 안 함).
STORE_CAUSES = {"no_brand_no_code", "no_brand", "no_code", "search_error", "search_empty", "search_redirect_only",
                "page_blocked", "code_not_on_page", "unconfirmed", "timeout", "other"}


def enabled() -> bool:
    return bool(os.environ.get("TAG_FAILURE_DIR") or os.environ.get("TAG_FAILURE_S3_BUCKET"))


def clean_image(image: bytes) -> bytes | None:
    """사진을 JPEG로 다시 저장해 EXIF(촬영 위치·기기·시간 등)를 지운다. 열 수 없는 형식이면 None."""
    try:
        from PIL import Image, ImageOps

        img = ImageOps.exif_transpose(Image.open(io.BytesIO(image))).convert("RGB")
        img.thumbnail((1600, 1600))
        out = io.BytesIO()
        img.save(out, "JPEG", quality=85)  # exif 인자를 주지 않으면 메타데이터 없이 저장된다
        return out.getvalue()
    except Exception:  # noqa: BLE001
        return None


def _key(report: dict) -> str:
    day = time.strftime("%Y/%m/%d", time.gmtime(report.get("ts") or time.time()))
    return f"{day}/{report.get('cause', 'other')}/{report['trace_id']}"


def save(image: bytes, report: dict) -> str | None:
    """보관 대상이면 저장하고 저장 위치를 돌려준다. 꺼져 있거나 대상이 아니면 None. 예외를 밖으로 내지 않는다."""
    if not enabled() or report.get("cause") not in STORE_CAUSES:
        return None
    try:
        photo = clean_image(image)
        record = {**report, "has_photo": photo is not None}
        key = _key(report)
        local = os.environ.get("TAG_FAILURE_DIR")
        if local:
            base = Path(local) / key
            base.parent.mkdir(parents=True, exist_ok=True)
            if photo:
                base.with_suffix(".jpg").write_bytes(photo)
            base.with_suffix(".json").write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
            return str(base)
        bucket = os.environ["TAG_FAILURE_S3_BUCKET"]
        prefix = os.environ.get("TAG_FAILURE_S3_PREFIX", "tag-failures/")
        import boto3

        s3 = boto3.client("s3")
        if photo:
            s3.put_object(Bucket=bucket, Key=f"{prefix}{key}.jpg", Body=photo, ContentType="image/jpeg")
        s3.put_object(Bucket=bucket, Key=f"{prefix}{key}.json",
                      Body=json.dumps(record, ensure_ascii=False).encode("utf-8"), ContentType="application/json")
        return f"s3://{bucket}/{prefix}{key}"
    except Exception as exc:  # noqa: BLE001 — 보관 실패가 태그 찾기를 망가뜨리면 안 된다
        logger.warning("[identify] 실패 태그 보관 실패: %s", exc)
        return None
