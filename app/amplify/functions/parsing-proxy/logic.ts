/**
 * parsing-engine 서버(POST /extract) 응답을 앱이 쓰기 편한 모양으로 바꾸는 순수 로직.
 * 실제 HTTP 호출은 handler.ts에서 한다(테스트에서 가짜로 바꿔 끼우기 위함).
 *
 * 엔진 서버의 실제 응답 스키마는 이 저장소의
 * engine/server/main.py `_extract()` 참고.
 */

/** 엔진 서버(POST /extract)가 실제로 돌려주는 응답 모양. */
export interface EngineExtractResponse {
  product_name: string | null;
  /** 엔진이 실제로 렌더링한 페이지(공유용 짧은 링크를 푼 뒤의 주소). */
  render?: { final_url?: string | null } | null;
  price: {
    unconditional_price: number | null;
    regular_price: number | null;
    currency: string;
  } | null;
  image_url: string | null;
  ambiguous: boolean;
  ambiguity_reason: string | null;
  confidence: string;
}

/** 이 함수가 앱에 돌려주는 모양(GraphQL ExtractedProduct와 1:1로 맞춤). */
export interface ExtractedProduct {
  productUrl: string | null;
  productName: string | null;
  unconditionalPrice: number | null;
  regularPrice: number | null;
  currency: string | null;
  imageUrl: string | null;
  ambiguous: boolean;
  ambiguityReason: string | null;
  confidence: string | null;
}

/** http(s) URL인지만 확인한다 — 몰별 상세 검증은 엔진 서버가 한다. */
export function isValidHttpUrl(value: string): boolean {
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

export function toExtractedProduct(res: EngineExtractResponse): ExtractedProduct {
  const finalUrl = res.render?.final_url;
  return {
    productUrl: finalUrl && isValidHttpUrl(finalUrl) ? finalUrl : null,
    productName: res.product_name,
    unconditionalPrice: res.price?.unconditional_price ?? null,
    regularPrice: res.price?.regular_price ?? null,
    currency: res.price?.currency ?? null,
    imageUrl: res.image_url,
    ambiguous: res.ambiguous,
    ambiguityReason: res.ambiguity_reason,
    confidence: res.confidence,
  };
}

// ── 태그 사진으로 찾기 (엔진 POST /identify-tag) ──────────────

/** 엔진 서버(POST /identify-tag) 응답 모양 — engine/server/tag_identify.py `IdentifyOutcome`. */
export interface EngineIdentifyResponse {
  /** 'found' | 'needs_confirm' | 'not_found' | 'not_a_tag' — 앱에 그대로 넘긴다. */
  status: string;
  tag: {
    brand: string | null;
    product_code: string | null;
    barcode: string | null;
    product_name: string | null;
    color: string | null;
    size: string | null;
    tag_price: number | null;
    confidence: string | null;
  } | null;
  official_domain: string | null;
  match: {
    url: string;
    host: string;
    source: string;
    verified_by: string;
    /** 찾은 페이지에서 읽은 상품명·가격·사진(구글 페이지 사본, 없으면 null/생략). */
    name?: string | null;
    price?: number | null;
    regular_price?: number | null;
    image?: string | null;
    /** 'qr' = 태그 QR이 가리킨 페이지로 찾음. 검색으로 찾았으면 생략. */
    via?: string | null;
  } | null;
  note: string | null;
}

/** 앱에 돌려주는 모양(GraphQL IdentifiedTag와 1:1). */
export interface IdentifiedTag {
  status: string;
  brand: string | null;
  productCode: string | null;
  productName: string | null;
  color: string | null;
  tagPrice: number | null;
  officialDomain: string | null;
  matchUrl: string | null;
  matchHost: string | null;
  matchSource: string | null;
  verifiedBy: string | null;
  note: string | null;
  matchName: string | null;
  matchPrice: number | null;
  matchRegularPrice: number | null;
  matchImage: string | null;
  /** 'qr'(태그 QR로 찾음) | 'search'(품번·브랜드 검색으로 찾음) | null(링크 없음) */
  matchVia: string | null;
}

/** 엔진 서버가 받는 사진 형식. */
export const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'];

/** base64 길이 상한 — 엔진의 IDENTIFY_MAX_IMAGE_BYTES(4MB)를 base64로 늘린 값. */
export const MAX_IMAGE_BASE64_CHARS = Math.ceil((4 * 1024 * 1024) / 3) * 4;

export function isValidImageInput(imageBase64: string, mimeType: string): boolean {
  return (
    ALLOWED_IMAGE_TYPES.includes(mimeType) &&
    imageBase64.length > 0 &&
    imageBase64.length <= MAX_IMAGE_BASE64_CHARS &&
    /^[A-Za-z0-9+/]+={0,2}$/.test(imageBase64)
  );
}

/** GraphQL Int로 보낼 수 있는 양의 정수 가격만(아니면 null). */
function wonOrNull(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) && v > 0 && v < 2_000_000_000 ? Math.round(v) : null;
}

export function toIdentifiedTag(res: EngineIdentifyResponse): IdentifiedTag {
  const price = res.tag?.tag_price;
  const image = res.match?.image;
  return {
    status: res.status,
    brand: res.tag?.brand ?? null,
    productCode: res.tag?.product_code ?? null,
    productName: res.tag?.product_name ?? null,
    color: res.tag?.color ?? null,
    // GraphQL Int — 엔진은 number(소수 가능)로 준다.
    tagPrice: typeof price === 'number' && Number.isFinite(price) && price > 0 ? Math.round(price) : null,
    officialDomain: res.official_domain,
    matchUrl: res.match?.url ?? null,
    matchHost: res.match?.host ?? null,
    matchSource: res.match?.source ?? null,
    verifiedBy: res.match?.verified_by ?? null,
    note: res.note,
    matchName: res.match?.name || null,
    matchPrice: wonOrNull(res.match?.price),
    matchRegularPrice: wonOrNull(res.match?.regular_price),
    matchImage: typeof image === 'string' && /^https?:\/\//.test(image) ? image : null,
    matchVia: res.match ? (res.match.via === 'qr' ? 'qr' : 'search') : null,
  };
}
