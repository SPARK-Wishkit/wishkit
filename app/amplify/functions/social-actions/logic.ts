/**
 * 살까말까 · 댓글 · 알림 서버 로직 (DynamoDB 는 밖에서 넣어 준다 → 테스트 가능).
 *
 * 원칙
 * - 호출한 사람(caller)은 Cognito 토큰에서 온 sub 만 믿는다. 앱이 보낸 "보낸 사람 정보"는 쓰지 않는다.
 * - 이름·아이디·사진은 DB 의 Profile 에서 가져온다 → 남을 사칭할 수 없다.
 * - AppSync 모델로 읽힐 행이므로 __typename · createdAt · updatedAt 을 반드시 채운다.
 */
import { randomUUID } from 'node:crypto';
import { findBannedWord } from './moderation';

export type Row = Record<string, unknown>;
export type Table =
  | 'Profile'
  | 'Follow'
  | 'BasketThread'
  | 'BasketComment'
  | 'BasketVote'
  | 'ReceivedBasket'
  | 'Notification'
  | 'Block'
  | 'ContentReport';

/** 보조 인덱스(GSI) 이름 — amplify/data/resource.ts 의 .name(...) 과 같아야 한다. */
export const INDEX = {
  commentsByAuthor: 'byAuthorId', // BasketComment.authorId
  receivedByFrom: 'byFromUid', // ReceivedBasket.fromUid
  threadsByOwner: 'byOwnerId', // BasketThread.ownerId
} as const;

export interface Db {
  get(table: Table, key: Row): Promise<Row | undefined>;
  put(table: Table, item: Row): Promise<void>;
  del(table: Table, key: Row): Promise<void>;
  /** 파티션 키 하나로 조회 */
  query(table: Table, keyName: string, keyValue: string): Promise<Row[]>;
  /** 보조 인덱스(GSI)의 키 하나로 조회 */
  queryIndex(table: Table, indexName: string, keyName: string, keyValue: string): Promise<Row[]>;
}

export const LIMITS = {
  recipients: 50,
  items: 100,
  text: 1000,
  memo: 500,
  reportDetail: 500,
};

/** 신고 사유. 앱의 신고 화면 선택지와 같다. */
export const REPORT_REASONS = ['spam', 'abuse', 'sexual', 'hate', 'other'] as const;
/** 신고 대상 종류. */
export const REPORT_TARGETS = ['comment', 'basket', 'user'] as const;

const THREAD_ID = /^[A-Za-z0-9_.:-]{1,100}$/;
/** 상품 번호(앱의 Product.id, int) 를 문자열로 받는다. */
const PRODUCT_ID = /^-?\d{1,20}$/;

/** 앱에 돌려주는 오류 코드. 앱이 한국어 문구로 바꿔 보여 준다. */
export class ActionError extends Error {
  constructor(public readonly code: string) {
    super(code);
  }
}
// 화살표 함수(const fail = ...)가 아니라 함수 선언으로 둬야 TypeScript가 `if (!x) fail(...)`
// 뒤에서 x를 non-null로 좁혀 준다 → 아래 코드에서 `!` 단언과 `as` 캐스팅이 필요 없어진다.
function fail(code: string): never {
  throw new ActionError(code);
}

export interface Env {
  db: Db;
  now?: () => Date;
  newId?: () => string;
  /** 운영팀에 알리기 (신고·차단). 없으면 아무것도 안 한다. 실패해도 신고 자체는 저장된다. */
  alert?: (subject: string, message: string) => Promise<void>;
}

interface Author {
  uid: string;
  name: string;
  handle: string;
  avatar: string;
}

// ── 공통 ──────────────────────────────────────────────────────

async function authorOf(env: Env, uid: string): Promise<Author> {
  const p = await env.db.get('Profile', { ownerId: uid });
  if (!p) fail('PROFILE_MISSING');
  return {
    uid,
    name: String(p.name ?? '사용자'),
    handle: String(p.handle ?? '@user'),
    avatar: String(p.avatarUrl ?? ''),
  };
}

function stamp(typename: string, item: Row, now: string, existing?: Row): Row {
  return {
    ...item,
    __typename: typename,
    createdAt: (existing?.createdAt as string | undefined) ?? now,
    updatedAt: now,
  };
}

function asJson(v: unknown): unknown {
  return typeof v === 'string' ? JSON.parse(v) : v;
}

function cleanText(
  raw: unknown,
  max: number,
  { required, filter = false }: { required: boolean; filter?: boolean },
): string {
  const t = typeof raw === 'string' ? raw.trim() : '';
  if (required && t.length === 0) fail('INVALID_INPUT');
  if (t.length > max) fail('TOO_LONG');
  // 남에게 보이는 글(댓글·살까말까 메모)은 금칙어를 막는다 (moderation.ts).
  if (filter && findBannedWord(t)) fail('BANNED_WORD');
  return t;
}

/** [blocker] 가 [blocked] 를 차단했는지. */
async function hasBlocked(env: Env, blocker: string, blocked: string): Promise<boolean> {
  if (!blocker || !blocked || blocker === blocked) return false;
  return (await env.db.get('Block', { blockerId: blocker, blockedId: blocked })) !== undefined;
}

/** 둘 중 한 사람이라도 상대를 차단했는지. 차단하면 서로 살까말까를 주고받지 않는다. */
async function eitherBlocked(env: Env, a: string, b: string): Promise<boolean> {
  return (await hasBlocked(env, a, b)) || (await hasBlocked(env, b, a));
}

async function notify(
  env: Env,
  recipientId: string,
  from: Author,
  type: string,
  message: string,
  relatedId: string,
  now: string,
  notificationId?: string,
) {
  if (recipientId === from.uid) return;
  const id = notificationId ?? env.newId!();
  const existing = notificationId
    ? await env.db.get('Notification', { recipientId, notificationId: id })
    : undefined;
  await env.db.put(
    'Notification',
    stamp(
      'Notification',
      {
        recipientId,
        notificationId: id,
        type,
        read: false,
        data: {
          id,
          type,
          fromUid: from.uid,
          fromName: from.name,
          fromHandle: from.handle,
          fromAvatar: from.avatar,
          message,
          relatedId,
          read: false,
          createdAt: now,
        },
      },
      now,
      existing,
    ),
  );
}

/** 보낸 상품에서 앱이 쓰는 칸만 남긴다. 개인 메모(memo)는 친구에게 보내지 않는다. */
function sanitizeItems(raw: unknown): Row[] {
  const list = asJson(raw);
  if (!Array.isArray(list) || list.length === 0) fail('INVALID_INPUT');
  if (list.length > LIMITS.items) fail('TOO_MANY_ITEMS');
  return list.map((it: unknown) => {
    if (typeof it !== 'object' || it === null) fail('INVALID_INPUT');
    const p = it as Row;
    const id = typeof p.id === 'number' ? p.id : Number(p.id);
    if (!Number.isFinite(id)) fail('INVALID_INPUT');
    return {
      id,
      listId: String(p.listId ?? 'all'),
      name: String(p.name ?? '').slice(0, 300),
      price: typeof p.price === 'number' ? p.price : 0,
      image: String(p.image ?? ''),
      platform: String(p.platform ?? ''),
      originalPrice: typeof p.originalPrice === 'number' ? p.originalPrice : null,
      discount: typeof p.discount === 'number' ? p.discount : null,
      productUrl: typeof p.productUrl === 'string' ? p.productUrl : null,
      isPublic: p.isPublic === true,
    };
  });
}

function withDefaults(env: Env): Required<Env> {
  return {
    db: env.db,
    now: env.now ?? (() => new Date()),
    newId: env.newId ?? (() => randomUUID()),
    alert: env.alert ?? (async () => {}),
  };
}

// ── 살까말까 보내기 ────────────────────────────────────────────

export async function sendBasket(
  envIn: Env,
  caller: string,
  args: {
    threadId: string;
    recipientIds: string[];
    items: unknown;
    memo?: string | null;
    allowMultipleVotes?: boolean | null;
    voteEnabled?: boolean | null;
  },
): Promise<number> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  if (!THREAD_ID.test(args.threadId ?? '')) fail('INVALID_INPUT');
  const memo = cleanText(args.memo, LIMITS.memo, { required: false, filter: true });
  const items = sanitizeItems(args.items);

  const wanted = [...new Set(args.recipientIds ?? [])].filter((id) => id && id !== caller);
  if (wanted.length === 0) fail('NO_RECIPIENTS');
  if (wanted.length > LIMITS.recipients) fail('TOO_MANY_RECIPIENTS');

  const from = await authorOf(env, caller);
  // 탈퇴했거나 없는 사람, 차단 관계(어느 쪽이든)인 사람에게는 보내지 않는다.
  const recipients: string[] = [];
  for (const id of wanted) {
    if (!(await env.db.get('Profile', { ownerId: id }))) continue;
    if (await eitherBlocked(env, caller, id)) continue;
    recipients.push(id);
  }
  if (recipients.length === 0) fail('NO_RECIPIENTS');

  // 댓글방: 남의 댓글방에 끼어들 수 없다.
  const thread = await env.db.get('BasketThread', { threadId: args.threadId });
  if (thread && thread.ownerId !== caller) fail('THREAD_CONFLICT');
  const before = new Set((thread?.participantIds as string[] | undefined) ?? []);
  const participants = [...new Set([...before, caller, ...recipients])];
  // 투표 후보: 이전에 보낸 상품 + 이번에 보낸 상품 (다시 보내도 기존 표가 무효가 되지 않게)
  const itemIds = [
    ...new Set([
      ...((thread?.itemIds as string[] | undefined) ?? []),
      ...items.map((it) => String(it.id)),
    ]),
  ];
  // 투표 설정은 처음 보낼 때 정하고 그대로 둔다 — 다시 보내도 이미 받은 사람과 화면이 같게.
  // 투표를 안 보내면 복수 선택도 의미가 없으니 false 로 맞춘다.
  const voteEnabled = thread ? thread.voteEnabled !== false : args.voteEnabled !== false;
  const allowMultipleVotes = !voteEnabled
    ? false
    : thread
      ? thread.allowMultipleVotes !== false
      : args.allowMultipleVotes !== false;
  await env.db.put(
    'BasketThread',
    stamp(
      'BasketThread',
      {
        threadId: args.threadId,
        ownerId: caller,
        participantIds: participants,
        memo,
        itemIds,
        allowMultipleVotes,
        voteEnabled,
      },
      now,
      thread,
    ),
  );

  // 참여자가 늘었으면, 새 참여자도 기존 댓글·투표를 볼 수 있게 목록을 고친다.
  if (thread && participants.length !== before.size) {
    const comments = await env.db.query('BasketComment', 'threadId', args.threadId);
    for (const c of comments) {
      await env.db.put('BasketComment', { ...c, participantIds: participants, updatedAt: now });
    }
    const votes = await env.db.query('BasketVote', 'threadId', args.threadId);
    for (const v of votes) {
      await env.db.put('BasketVote', { ...v, participantIds: participants, updatedAt: now });
    }
  }

  for (const recipientId of recipients) {
    const basketId = env.newId();
    await env.db.put(
      'ReceivedBasket',
      stamp(
        'ReceivedBasket',
        {
          recipientId,
          basketId,
          fromUid: caller,
          data: {
            id: basketId,
            title: `${from.name}의 살까말까`,
            ownerName: from.name,
            fromUid: caller,
            fromHandle: from.handle,
            fromAvatar: from.avatar,
            items,
            createdAt: now,
            channels: ['friends'],
            memo,
            threadId: args.threadId,
            allowMultipleVotes,
            voteEnabled,
          },
        },
        now,
      ),
    );
    await notify(
      env,
      recipientId,
      from,
      'basket',
      `${from.name} 님이 살까말까 장바구니를 보냈어요`,
      args.threadId,
      now,
    );
  }
  return recipients.length;
}

// ── 댓글 ──────────────────────────────────────────────────────

/** 답글의 답글은 가장 위 댓글에 붙인다 (앱의 flattenCommentParentId 와 같은 규칙). */
function flattenParent(parentId: string, comments: Row[]): string {
  if (!parentId) return '';
  const parent = comments.find((c) => c.commentId === parentId);
  if (!parent || !parent.parentId) return parentId;
  return String(parent.parentId);
}

export async function addComment(
  envIn: Env,
  caller: string,
  args: {
    threadId: string;
    text: string;
    parentId?: string | null;
    participantIds?: string[] | null;
    memo?: string | null;
  },
): Promise<Row> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  if (!THREAD_ID.test(args.threadId ?? '')) fail('INVALID_INPUT');
  const text = cleanText(args.text, LIMITS.text, { required: true, filter: true });

  let thread = await env.db.get('BasketThread', { threadId: args.threadId });
  if (!thread) {
    // 댓글방이 없으면: 호출한 사람을 방장으로 새로 만든다 (보낸 사람의 첫 댓글).
    const extra = [...new Set(args.participantIds ?? [])]
      .filter((id) => id && id !== caller)
      .slice(0, LIMITS.recipients);
    thread = stamp(
      'BasketThread',
      {
        threadId: args.threadId,
        ownerId: caller,
        participantIds: [caller, ...extra],
        memo: cleanText(args.memo, LIMITS.memo, { required: false, filter: true }),
      },
      now,
    );
    await env.db.put('BasketThread', thread);
  }
  const participants = (thread.participantIds as string[]) ?? [];
  if (!participants.includes(caller)) fail('NOT_PARTICIPANT');

  const existing = await env.db.query('BasketComment', 'threadId', args.threadId);
  const parentId = flattenParent(String(args.parentId ?? ''), existing);
  const from = await authorOf(env, caller);
  const commentId = env.newId();
  const comment = {
    id: commentId,
    threadId: args.threadId,
    parentId,
    authorUid: caller,
    authorName: from.name,
    authorHandle: from.handle,
    authorAvatar: from.avatar,
    text,
    createdAt: now,
    updatedAt: null,
  };
  await env.db.put(
    'BasketComment',
    stamp(
      'BasketComment',
      {
        threadId: args.threadId,
        commentId,
        authorId: caller,
        parentId,
        participantIds: participants,
        data: comment,
      },
      now,
    ),
  );

  // 알림 대상 (원래 앱 규칙 그대로)
  const owner = String(thread.ownerId);
  const targets = new Set<string>();
  if (owner && owner !== caller) targets.add(owner);
  if (parentId) {
    const parent = existing.find((c) => c.commentId === parentId);
    const parentAuthor = parent ? String(parent.authorId ?? '') : '';
    if (parentAuthor && parentAuthor !== caller) targets.add(parentAuthor);
  } else if (caller === owner) {
    participants.filter((id) => id !== caller).forEach((id) => targets.add(id));
  }
  const message = parentId
    ? `${from.name} 님이 살까말까 댓글에 답글을 남겼어요`
    : `${from.name} 님이 살까말까에 댓글을 남겼어요`;
  for (const t of targets) {
    // 나를 차단한 사람에게는 알림을 보내지 않는다.
    if (await hasBlocked(env, t, caller)) continue;
    await notify(env, t, from, 'comment', message, args.threadId, now);
  }
  return comment;
}

async function ownComment(env: Env, caller: string, threadId: string, commentId: string) {
  const row = await env.db.get('BasketComment', { threadId, commentId });
  if (!row) return undefined;
  if (row.authorId !== caller) fail('NOT_AUTHOR');
  return row;
}

export async function updateComment(
  envIn: Env,
  caller: string,
  args: { threadId: string; commentId: string; text: string },
): Promise<boolean> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  const text = cleanText(args.text, LIMITS.text, { required: true, filter: true });
  const row = await ownComment(env, caller, args.threadId, args.commentId);
  if (!row) fail('COMMENT_NOT_FOUND');
  const data = { ...(asJson(row.data) as Row), text, updatedAt: now };
  await env.db.put('BasketComment', { ...row, data, updatedAt: now });
  return true;
}

export async function deleteComment(
  envIn: Env,
  caller: string,
  args: { threadId: string; commentId: string },
): Promise<boolean> {
  const env = withDefaults(envIn);
  const row = await ownComment(env, caller, args.threadId, args.commentId);
  if (row) await env.db.del('BasketComment', { threadId: args.threadId, commentId: args.commentId });
  return true;
}

// ── 투표 ──────────────────────────────────────────────────────

/**
 * 투표하기 · 다시 투표하기 · 취소(빈 목록). 카톡 투표처럼 여러 개 고를 수 있다.
 * - 댓글방 참여자(보낸 사람 + 받은 사람)만 투표한다.
 * - 보낸 상품만 고를 수 있다. (예전 댓글방처럼 itemIds 가 없으면 번호 모양만 확인)
 * - 마감은 없다. 투표는 댓글방을 따라간다.
 */
export async function voteBasket(
  envIn: Env,
  caller: string,
  args: { threadId: string; productIds: unknown },
): Promise<boolean> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  if (!THREAD_ID.test(args.threadId ?? '')) fail('INVALID_INPUT');
  if (!Array.isArray(args.productIds)) fail('INVALID_INPUT');
  const picked = [...new Set(args.productIds.map((id) => String(id ?? '').trim()))];
  if (picked.length > LIMITS.items) fail('TOO_MANY_ITEMS');
  if (picked.some((id) => !PRODUCT_ID.test(id))) fail('INVALID_INPUT');

  const thread = await env.db.get('BasketThread', { threadId: args.threadId });
  const participants = (thread?.participantIds as string[] | undefined) ?? [];
  if (!thread || !participants.includes(caller)) fail('VOTE_NOT_ALLOWED');
  // 투표 없이 보낸 살까말까. 빈 목록(취소·탈퇴 정리)은 그대로 받는다.
  if (thread.voteEnabled === false && picked.length > 0) fail('VOTE_OFF');
  if (thread.allowMultipleVotes === false && picked.length > 1) fail('MULTIPLE_VOTES_NOT_ALLOWED');
  const allowed = thread.itemIds as string[] | undefined;
  if (allowed && allowed.length > 0 && picked.some((id) => !allowed.includes(id))) {
    fail('INVALID_INPUT');
  }

  const key = { threadId: args.threadId, voterId: caller };
  if (picked.length === 0) {
    await env.db.del('BasketVote', key);
    return true;
  }
  const existing = await env.db.get('BasketVote', key);
  const from = await authorOf(env, caller);
  await env.db.put(
    'BasketVote',
    stamp(
      'BasketVote',
      {
        ...key,
        participantIds: participants,
        data: {
          threadId: args.threadId,
          voterUid: caller,
          voterName: from.name,
          voterHandle: from.handle,
          voterAvatar: from.avatar,
          productIds: picked,
          updatedAt: now,
        },
      },
      now,
      existing,
    ),
  );
  return true;
}

// ── 팔로우 알림 ────────────────────────────────────────────────

export async function notifyFollow(
  envIn: Env,
  caller: string,
  args: { targetId: string },
): Promise<boolean> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  if (!args.targetId || args.targetId === caller) return false;
  const edge = await env.db.get('Follow', { followerId: caller, followeeId: args.targetId });
  if (!edge) fail('NOT_FOLLOWING');
  // 나를 차단한 사람에게는 팔로우 알림을 보내지 않는다.
  if (await hasBlocked(env, args.targetId, caller)) return false;
  const from = await authorOf(env, caller);
  // 알림 id 를 고정 → 팔로우를 껐다 켜도 알림은 하나만 (최신으로 갱신)
  await notify(
    env,
    args.targetId,
    from,
    'follow',
    `${from.name} 님이 회원님을 팔로우하기 시작했어요`,
    '',
    now,
    `follow-${caller}`,
  );
  return true;
}

// ── 신고 · 차단 (App Store 심사 1.2: 사용자 생성 콘텐츠) ───────────────────────

type ReportTarget = (typeof REPORT_TARGETS)[number];
type ReportReason = (typeof REPORT_REASONS)[number];

/**
 * 댓글·살까말까·사용자 신고. 신고한 순간의 내용을 그대로 복사해 둔다(나중에 지워져도 검토할 수 있게).
 * 신고는 ContentReport 표에 쌓이고(사용자는 읽을 수 없음), 운영팀 메일로도 알린다(env.alert).
 * 운영팀은 24시간 안에 확인해서 내용 삭제·계정 정지를 한다 (docs/MODERATION.md).
 * - 댓글: 그 댓글방 참여자만 신고할 수 있다.
 * - 살까말까: 내 받은함에 있는 것만 신고할 수 있다.
 */
export async function reportContent(
  envIn: Env,
  caller: string,
  args: {
    targetType: string;
    targetUserId?: string | null;
    threadId?: string | null;
    commentId?: string | null;
    basketId?: string | null;
    reason: string;
    detail?: string | null;
  },
): Promise<boolean> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  const targetType = args.targetType as ReportTarget;
  const reason = args.reason as ReportReason;
  if (!REPORT_TARGETS.includes(targetType)) fail('INVALID_INPUT');
  if (!REPORT_REASONS.includes(reason)) fail('INVALID_INPUT');
  const detail = cleanText(args.detail, LIMITS.reportDetail, { required: false });

  let targetUserId = '';
  let targetKey = '';
  let snapshot: unknown = null;
  if (targetType === 'comment') {
    const threadId = String(args.threadId ?? '');
    const commentId = String(args.commentId ?? '');
    if (!THREAD_ID.test(threadId) || !commentId) fail('INVALID_INPUT');
    const row = await env.db.get('BasketComment', { threadId, commentId });
    if (!row) fail('TARGET_NOT_FOUND');
    if (!((row.participantIds as string[] | undefined) ?? []).includes(caller)) fail('NOT_PARTICIPANT');
    targetUserId = String(row.authorId ?? '');
    targetKey = `${threadId}/${commentId}`;
    snapshot = asJson(row.data);
  } else if (targetType === 'basket') {
    const basketId = String(args.basketId ?? '');
    if (!basketId) fail('INVALID_INPUT');
    const row = await env.db.get('ReceivedBasket', { recipientId: caller, basketId });
    if (!row) fail('TARGET_NOT_FOUND');
    targetUserId = String(row.fromUid ?? '');
    targetKey = basketId;
    snapshot = asJson(row.data);
  } else {
    targetUserId = String(args.targetUserId ?? '');
    if (!targetUserId) fail('INVALID_INPUT');
    const p = await env.db.get('Profile', { ownerId: targetUserId });
    if (!p) fail('TARGET_NOT_FOUND');
    targetKey = targetUserId;
    snapshot = { name: p.name, handle: p.handle, avatarUrl: p.avatarUrl ?? null };
  }
  if (targetUserId === caller) fail('INVALID_INPUT');

  const reportId = env.newId();
  await env.db.put(
    'ContentReport',
    stamp(
      'ContentReport',
      {
        reportId,
        reporterId: caller,
        targetType,
        targetUserId,
        targetKey,
        reason,
        detail,
        snapshot,
        status: 'open',
      },
      now,
    ),
  );
  await safeAlert(
    env,
    `[wishkit 신고] ${targetType} · ${reason}`,
    [
      `신고 번호: ${reportId}`,
      `시각: ${now}`,
      `신고한 사람: ${caller}`,
      `대상: ${targetType} ${targetKey}`,
      `대상 사용자: ${targetUserId}`,
      `사유: ${reason}${detail ? ` — ${detail}` : ''}`,
      `내용: ${JSON.stringify(snapshot).slice(0, 2000)}`,
      '',
      '24시간 안에 확인해 주세요. 처리 방법: docs/MODERATION.md',
    ].join('\n'),
  );
  return true;
}

/**
 * 사용자 차단. 차단하면
 * - 서로 살까말까를 보낼 수 없고(sendBasket), 차단한 사람에게 댓글·팔로우 알림이 가지 않는다.
 * - 앱은 차단한 사람의 살까말까·댓글·알림을 바로 숨기고, 서로의 팔로우를 끊는다.
 * 차단 해제는 앱이 Block 행을 직접 지운다(본인 것만 지울 수 있음).
 * 운영팀에도 알린다 (App Store 1.2: 차단도 개발자에게 알려야 한다).
 */
export async function blockUser(
  envIn: Env,
  caller: string,
  args: { targetId: string },
): Promise<boolean> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  const target = String(args.targetId ?? '');
  if (!target || target === caller) fail('INVALID_INPUT');
  const key = { blockerId: caller, blockedId: target };
  const existing = await env.db.get('Block', key);
  await env.db.put('Block', stamp('Block', key, now, existing));
  if (!existing) {
    const p = await env.db.get('Profile', { ownerId: target });
    await safeAlert(
      env,
      '[wishkit 차단] 사용자 차단',
      [
        `시각: ${now}`,
        `차단한 사람: ${caller}`,
        `차단된 사람: ${target} (${String(p?.handle ?? '?')} ${String(p?.name ?? '')})`,
        '',
        '같은 사람이 여러 번 차단되면 계정을 확인해 주세요. docs/MODERATION.md',
      ].join('\n'),
    );
  }
  return true;
}

async function safeAlert(env: Required<Env>, subject: string, message: string) {
  try {
    await env.alert(subject, message);
  } catch (e) {
    console.error('alert failed', e);
  }
}

// ── 탈퇴: 내가 남에게 남긴 콘텐츠 지우기 (App Store 심사 5.1.1(v)) ─────────────────

/**
 * 탈퇴할 때 앱이 가장 먼저 부른다. 다른 사람 공간에 남아 있는 내 콘텐츠를 지운다.
 * - 내가 쓴 댓글 (남의 살까말까에 쓴 것 포함)
 * - 내가 보낸 살까말까가 친구들 받은함에 남은 사본
 * - 내가 만든 댓글방 + 그 안의 댓글·투표 (방장이 없어지면 방도 없앤다)
 * - 내가 한 차단 목록
 * 내 투표 취소, 내 받은함·보낸함·알림·위시리스트·프로필은 앱이 이어서 지운다(basket_store.dart 등).
 * 몇 개를 지웠는지 돌려준다.
 */
export async function deleteMyContent(envIn: Env, caller: string): Promise<number> {
  const env = withDefaults(envIn);
  let removed = 0;

  for (const c of await env.db.queryIndex('BasketComment', INDEX.commentsByAuthor, 'authorId', caller)) {
    await env.db.del('BasketComment', { threadId: c.threadId, commentId: c.commentId });
    removed++;
  }
  for (const b of await env.db.queryIndex('ReceivedBasket', INDEX.receivedByFrom, 'fromUid', caller)) {
    await env.db.del('ReceivedBasket', { recipientId: b.recipientId, basketId: b.basketId });
    removed++;
  }
  for (const t of await env.db.queryIndex('BasketThread', INDEX.threadsByOwner, 'ownerId', caller)) {
    const threadId = String(t.threadId);
    for (const c of await env.db.query('BasketComment', 'threadId', threadId)) {
      await env.db.del('BasketComment', { threadId, commentId: c.commentId });
      removed++;
    }
    for (const v of await env.db.query('BasketVote', 'threadId', threadId)) {
      await env.db.del('BasketVote', { threadId, voterId: v.voterId });
    }
    await env.db.del('BasketThread', { threadId });
    removed++;
  }
  for (const b of await env.db.query('Block', 'blockerId', caller)) {
    await env.db.del('Block', { blockerId: caller, blockedId: b.blockedId });
  }
  return removed;
}
