/**
 * 금칙어 필터 (App Store 심사 1.2: 사용자 생성 콘텐츠는 불쾌한 내용을 거르는 장치가 있어야 한다).
 *
 * 댓글·살까말까 메모를 저장하기 전에 서버에서 검사한다. 앱이 보낸 글을 믿지 않고 여기서 막으므로
 * 앱을 고쳐 쓰는 사람도 우회할 수 없다. 걸리면 'BANNED_WORD' 오류 → 앱이 한국어 문구로 보여 준다.
 *
 * 검사 방법: 소문자로 바꾸고 공백·숫자·기호를 지운 뒤(“시 1 발”, “f.u.c.k” 도 잡힘) 목록의 낱말이 들어 있는지 본다.
 * 오탐(멀쩡한 낱말이 걸리는 것)을 줄이려고 짧고 흔한 글자 조합(예: '자지' → '남자지만')은 넣지 않았다.
 * 낱말을 더하거나 뺄 때는 아래 두 목록만 고치면 된다.
 */

/** 걸리는 낱말 (정규화한 모양으로 적는다: 소문자, 공백·기호 없음). */
export const BANNED_WORDS: readonly string[] = [
  // 한국어 욕설·비하
  '씨발', '시발', '씨팔', '시팔', '씨빨', '씨바ㄹ', '썅', 'ㅅㅂ', 'ㅆㅂ', 'ㅆㅃ',
  '병신', '븅신', '빙신', 'ㅂㅅ',
  '개새끼', '개새기', '개색기', '개색끼', '개쌔끼', '개세끼', 'ㄱㅅㄲ',
  '좆', 'ㅈㄹ', '지랄', '존나', 'ㅈㄴ',
  '미친놈', '미친년', '미친새끼', '또라이',
  '엠창', '느금마', '니애미', '니앰', '애미뒤진', '애비뒤진',
  '닥쳐', '꺼지라고', '뒤져라', '뒤지세요', '죽어라', '자살해',
  '창녀', '걸레년', '보슬아치', '김치녀', '한남충', '틀딱', '급식충', '맘충',
  '장애인새끼', '정신병자새끼',
  // 성적인 표현
  '섹스', '야동', '보빨', '자위해', '강간',
  // 영어
  'fuck', 'fuk', 'shit', 'bitch', 'asshole', 'cunt', 'dick', 'pussy', 'nigger', 'nigga',
  'faggot', 'retard', 'motherfucker', 'whore', 'slut', 'rape',
];

/** 금칙어가 들어 있어도 괜찮은 흔한 낱말. 검사 전에 지운다. */
export const ALLOWED_WORDS: readonly string[] = [
  '시발점', '시발역', '시발택시', // 출발점
  '병신년', '병신정변', '병신양요', // 역사(병신년 = 60갑자)
  'dickens', 'dickies', 'fukuoka', 'scrape', 'trapeze', 'shitake', 'shiitake', 'cockpit', 'scunthorpe', 'grape', 'drape', 'therapist',
];

export function normalizeForFilter(text: string): string {
  let t = text.normalize('NFC').toLowerCase();
  // 공백·숫자·기호·이모지를 지운다 (한글 완성형, 한글 자모, 영문만 남긴다).
  t = t.replace(/[^a-z가-힣ㄱ-ㆎ]/g, '');
  for (const ok of ALLOWED_WORDS) t = t.split(ok).join('');
  return t;
}

/** 금칙어가 있으면 그 낱말을, 없으면 null 을 돌려준다. */
export function findBannedWord(text: string | null | undefined): string | null {
  if (!text) return null;
  const t = normalizeForFilter(text);
  if (!t) return null;
  for (const w of BANNED_WORDS) {
    if (t.includes(w)) return w;
  }
  return null;
}
