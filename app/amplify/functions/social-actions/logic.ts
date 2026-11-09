/**
 * 살까말까 · 댓글 · 알림 서버 로직 (DynamoDB 는 밖에서 넣어 준다 → 테스트 가능).
 *
 * 원칙
 * - 호출한 사람(caller)은 Cognito 토큰에서 온 sub 만 믿는다. 앱이 보낸 "보낸 사람 정보"는 쓰지 않는다.
 * - 이름·아이디·사진은 DB 의 Profile 에서 가져온다 → 남을 사칭할 수 없다.
 * - AppSync 모델로 읽힐 행이므로 __typename · createdAt · updatedAt 을 반드시 채운다.
 */
import { randomUUID } from 'node:crypto';

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
  | 'Report';

export interface Db {
  get(table: Table, key: Row): Promise<Row | undefined>;
  put(table: Table, item: Row): Promise<void>;
  del(table: Table, key: Row): Promise<void>;
  /** 파티션 키(또는 [indexName] 보조 인덱스의 키) 하나로 조회 */
  query(table: Table, keyName: string, keyValue: string, indexName?: string): Promise<Row[]>;
}

export const LIMITS = {
  recipients: 50,
  items: 100,
  text: 1000,
  memo: 500,
  reportDetail: 500,
};

export const REPORT_TARGETS = ['comment', 'basket', 'user'] as const;
export const REPORT_REASONS = ['abuse', 'harassment', 'sexual', 'spam', 'other'] as const;

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

function cleanText(raw: unknown, max: number, { required }: { required: boolean }): string {
  const t = typeof raw === 'string' ? raw.trim() : '';
  if (required && t.length === 0) fail('INVALID_INPUT');
  if (t.length > max) fail('TOO_LONG');
  return t;
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
  };
}

// ── 차단 ──────────────────────────────────────────────────────

/** a 가 b 를 차단했거나 b 가 a 를 차단했으면 true. */
export async function isBlockedEitherWay(env: Env, a: string, b: string): Promise<boolean> {
  if (!a || !b || a === b) return false;
  const [ab, ba] = await Promise.all([
    env.db.get('Block', { blockerId: a, blockedId: b }),
    env.db.get('Block', { blockerId: b, blockedId: a }),
  ]);
  return Boolean(ab || ba);
}

// ── 살까말까 보내기 ────────────────────────────────────────────

export async function sendBasket(
  envIn: Env,
  caller: string,
  args: { threadId: string; recipientIds: string[]; items: unknown; memo?: string | null },
): Promise<number> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  if (!THREAD_ID.test(args.threadId ?? '')) fail('INVALID_INPUT');
  const memo = cleanText(args.memo, LIMITS.memo, { required: false });
  const items = sanitizeItems(args.items);

  const wanted = [...new Set(args.recipientIds ?? [])].filter((id) => id && id !== caller);
  if (wanted.length === 0) fail('NO_RECIPIENTS');
  if (wanted.length > LIMITS.recipients) fail('TOO_MANY_RECIPIENTS');

  const from = await authorOf(env, caller);
  // 탈퇴했거나 없는 사람에게는 보내지 않는다.
  const recipients: string[] = [];
  // 차단 관계(어느 쪽이든)인 사람에게도 보내지 않는다.
  for (const id of wanted) {
    if (!(await env.db.get('Profile', { ownerId: id }))) continue;
    if (await isBlockedEitherWay(env, caller, id)) continue;
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
  await env.db.put(
    'BasketThread',
    stamp(
      'BasketThread',
      { threadId: args.threadId, ownerId: caller, participantIds: participants, memo, itemIds },
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
  const text = cleanText(args.text, LIMITS.text, { required: true });

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
        memo: cleanText(args.memo, LIMITS.memo, { required: false }),
      },
      now,
    );
    await env.db.put('BasketThread', thread);
  }
  const participants = (thread.participantIds as string[]) ?? [];
  if (!participants.includes(caller)) fail('NOT_PARTICIPANT');
  // 댓글방 주인과 차단 관계면 댓글을 달 수 없다.
  if (await isBlockedEitherWay(env, caller, String(thread.ownerId ?? ''))) fail('BLOCKED');

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
    if (await isBlockedEitherWay(env, caller, t)) continue;
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
  const text = cleanText(args.text, LIMITS.text, { required: true });
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
  // 차단 관계면 알림을 보내지 않는다(차단 사실은 알리지 않는다).
  if (await isBlockedEitherWay(env, caller, args.targetId)) return false;
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

// ── 신고 ──────────────────────────────────────────────────────

/**
 * 댓글·받은 바구니·사용자 신고. 신고 당시 내용을 snapshot 으로 저장해서, 작성자가 지우거나
 * 고쳐도 담당자가 확인할 수 있게 한다. 신고한 사람이 볼 수 있는 콘텐츠만 신고할 수 있다.
 */
export async function reportContent(
  envIn: Env,
  caller: string,
  args: {
    targetType: string;
    targetUserId: string;
    targetId?: string | null;
    threadId?: string | null;
    reason: string;
    detail?: string | null;
  },
): Promise<boolean> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  const type = args.targetType as (typeof REPORT_TARGETS)[number];
  if (!REPORT_TARGETS.includes(type)) fail('INVALID_INPUT');
  if (!REPORT_REASONS.includes(args.reason as (typeof REPORT_REASONS)[number])) fail('INVALID_INPUT');
  if (!args.targetUserId || args.targetUserId === caller) fail('INVALID_INPUT');
  const detail = cleanText(args.detail, LIMITS.reportDetail, { required: false });

  let snapshot: unknown;
  let targetUserId = args.targetUserId;
  if (type === 'comment') {
    if (!THREAD_ID.test(args.threadId ?? '') || !args.targetId) fail('INVALID_INPUT');
    const row = await env.db.get('BasketComment', {
      threadId: args.threadId,
      commentId: args.targetId,
    });
    if (!row) fail('NOT_FOUND');
    const participants = (row.participantIds as string[] | undefined) ?? [];
    if (!participants.includes(caller)) fail('NOT_PARTICIPANT');
    targetUserId = String(row.authorId);
    snapshot = asJson(row.data);
  } else if (type === 'basket') {
    if (!args.targetId) fail('INVALID_INPUT');
    const row = await env.db.get('ReceivedBasket', { recipientId: caller, basketId: args.targetId });
    if (!row) fail('NOT_FOUND');
    targetUserId = String(row.fromUid);
    snapshot = asJson(row.data);
  } else {
    const p = await env.db.get('Profile', { ownerId: args.targetUserId });
    if (!p) fail('NOT_FOUND');
    snapshot = { name: p.name, handle: p.handle, avatarUrl: p.avatarUrl ?? null };
  }

  const reportId = `${now}#${env.newId()}`;
  await env.db.put(
    'Report',
    stamp(
      'Report',
      {
        reporterId: caller,
        reportId,
        targetType: type,
        targetUserId,
        targetId: args.targetId ?? null,
        threadId: args.threadId ?? null,
        reason: args.reason,
        detail,
        snapshot,
        status: 'open',
      },
      now,
    ),
  );
  // CloudWatch 지표 필터·알림용 한 줄 (docs/play-release/moderation.md)
  console.log(
    JSON.stringify({ event: 'WISHKIT_REPORT', reportId, reporterId: caller, targetType: type, targetUserId }),
  );
  return true;
}

// ── 탈퇴 시 공유 콘텐츠 정리 ─────────────────────────────────

/**
 * 탈퇴하는 사람(caller)이 남긴, 다른 사람에게 보이는 콘텐츠를 지운다. Google Play 계정 삭제 요건
 * (연결된 사용자 데이터 모두 삭제). 앱이 Cognito 계정을 지우기 전에 호출한다.
 * - 남의 댓글방에 쓴 내 댓글
 * - 친구 받은함에 있는, 내가 보낸 살까말까
 * - 내가 만든 댓글방과 그 안의 댓글 전부
 * - 내가 한 차단, 나를 대상으로 한 차단
 * 신고 기록(Report)은 관리 목적상 남긴다(처리방침에 명시).
 */
export async function deleteMySocialData(envIn: Env, caller: string): Promise<number> {
  const env = withDefaults(envIn);
  let count = 0;

  const myComments = await env.db.query('BasketComment', 'authorId', caller, 'byAuthor');
  for (const c of myComments) {
    await env.db.del('BasketComment', { threadId: c.threadId, commentId: c.commentId });
    count++;
  }

  const sent = await env.db.query('ReceivedBasket', 'fromUid', caller, 'byFromUid');
  for (const b of sent) {
    await env.db.del('ReceivedBasket', { recipientId: b.recipientId, basketId: b.basketId });
    count++;
  }

  const threads = await env.db.query('BasketThread', 'ownerId', caller, 'byOwner');
  for (const t of threads) {
    const comments = await env.db.query('BasketComment', 'threadId', String(t.threadId));
    for (const c of comments) {
      await env.db.del('BasketComment', { threadId: c.threadId, commentId: c.commentId });
      count++;
    }
    await env.db.del('BasketThread', { threadId: t.threadId });
    count++;
  }

  const mine = await env.db.query('Block', 'blockerId', caller);
  const againstMe = await env.db.query('Block', 'blockedId', caller, 'byBlocked');
  for (const b of [...mine, ...againstMe]) {
    await env.db.del('Block', { blockerId: b.blockerId, blockedId: b.blockedId });
    count++;
  }
  return count;
}
