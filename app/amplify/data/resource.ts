import { type ClientSchema, a, defineData } from '@aws-amplify/backend';
import { publicWishlist } from '../functions/public-wishlist/resource';
import { socialActions } from '../functions/social-actions/resource';
import { parsingProxy } from '../functions/parsing-proxy/resource';

/**
 * wishkit 데이터 설계도 (AWS AppSync + DynamoDB)
 *
 * 공통 규칙
 * - ownerId 에는 항상 Cognito `sub` 를 저장한다. (= 앱의 store.uid / AuthUserInfo.uid)
 * - 권한 "본인"은 ownerId == 로그인한 사람의 sub 일 때만 통과한다.
 *
 * 2단계: 프로필 · 아이디 · 탭 · 상품 · 리뷰 (내가 쓰는 데이터)
 * 3-1단계: 팔로우 · 친구 위시리스트(공개만, 서버 함수) · 친구 리뷰
 * 3-2단계: 살까말까 · 댓글 · 알림
 *   → 남의 받은함·알림함·댓글방에 쓰는 일은 앱이 직접 못 하고, 서버 함수(socialActions)만 한다.
 *     서버는 보낸 사람 이름·사진을 DB의 진짜 프로필에서 가져온다(사칭 불가).
 *
 * 권한은 필요한 만큼만 연다.
 * - 이메일·푸시 토큰은 PrivateProfile 로 분리해서 본인만 읽는다. (예전엔 누구나 읽기 가능)
 * - 탭·상품은 본인만 읽는다. 친구에게는 서버 함수(publicWishlist)가 "공개(isPublic)인 것만",
 *   그리고 메모(memo)는 빼고 돌려준다. (예전엔 로그인만 하면 비공개·메모까지 읽기 가능)
 *
 * 신고·차단 (Google Play UGC 정책)
 * - Block: 차단한 사람이 직접 만들고 지운다. 서버 함수는 차단 관계(양방향)를 보고
 *   살까말까 보내기·댓글·팔로우 알림·공개 위시리스트를 거부한다.
 * - Report: 서버 함수(reportContent)만 만든다. 신고 당시 내용을 snapshot 으로 남긴다.
 *   담당자는 DynamoDB 콘솔에서 status = 'open' 인 행을 확인한다 (docs/play-release/moderation.md).
 */
const schema = a.schema({
  /** 친구 목록·검색에 보이는 공개 프로필. */
  Profile: a
    .model({
      ownerId: a.id().required(),
      handle: a.string().required(), // '@kim.ji'
      handleLower: a.string().required(),
      name: a.string().required(),
      avatarUrl: a.string(),
      followers: a.integer(),
      following: a.integer(),
    })
    .identifier(['ownerId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('ownerId').identityClaim('sub'),
      allow.authenticated().to(['read']),
    ]),

  /** 본인만 볼 수 있는 계정 정보. */
  PrivateProfile: a
    .model({
      ownerId: a.id().required(),
      email: a.string().required(),
      fcmTokens: a.string().array(),
      hiddenFeedBaskets: a.string().array(),
    })
    .identifier(['ownerId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('ownerId').identityClaim('sub'),
    ]),

  /**
   * 아이디 중복 방지표. 아이디(소문자)가 곧 키라서 같은 아이디는 두 번 만들어지지 않는다.
   * 비로그인(가입 전 중복 확인, 이메일 찾기)은 정확한 아이디 1건 조회(get)만 가능하다.
   */
  Handle: a
    .model({
      handleLower: a.string().required(),
      ownerId: a.id().required(),
      maskedEmail: a.string(), // 'k***n@gmail.com' — 이메일 찾기 화면용
    })
    .identifier(['handleLower'])
    .authorization((allow) => [
      // 수정(update)은 막는다: 아이디를 남에게 넘기는 일을 원천 차단. 바꿀 땐 새로 만들고 옛것을 지운다.
      allow.ownerDefinedIn('ownerId').identityClaim('sub').to(['create', 'read', 'delete']),
      allow.authenticated().to(['get']),
      allow.guest().to(['get']),
    ]),

  WishTab: a
    .model({
      ownerId: a.id().required(),
      tabId: a.string().required(),
      name: a.string().required(),
      isPublic: a.boolean().required(),
      colorHex: a.string(),
      sortOrder: a.integer().required(),
    })
    .identifier(['ownerId', 'tabId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('ownerId').identityClaim('sub'),
    ]),

  WishProduct: a
    .model({
      ownerId: a.id().required(),
      productId: a.string().required(), // 앱의 Product.id(int) 를 문자열로 저장
      listId: a.string().required(),
      name: a.string().required(),
      price: a.integer().required(),
      image: a.string(),
      platform: a.string(),
      originalPrice: a.integer(),
      discount: a.integer(),
      productUrl: a.string(),
      memo: a.string(),
      isPublic: a.boolean().required(),
      // 태그 사진으로 담은 상품의 태그 사진 주소(파일 배달망). 메모처럼 본인만 본다 —
      // publicWishlist(친구에게 보이는 목록)에는 넣지 않는다.
      tagImageUrl: a.string(),
    })
    .identifier(['ownerId', 'productId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('ownerId').identityClaim('sub'),
    ]),

  /**
   * 팔로우 관계 한 줄 = "followerId 가 followeeId 를 팔로우한다".
   * - 팔로우/언팔로우: 팔로우하는 사람(followerId)만 만들고 지운다.
   * - 팔로워 삭제: 팔로우 당하는 사람(followeeId)도 지울 수 있다.
   * - 수정은 없다. (남의 팔로우를 조작할 방법 자체가 없음)
   * 팔로워·팔로잉 수는 따로 저장하지 않고 이 표에서 센다. (숫자가 어긋날 일이 없음)
   */
  Follow: a
    .model({
      followerId: a.id().required(),
      followeeId: a.id().required(),
    })
    .identifier(['followerId', 'followeeId'])
    .secondaryIndexes((index) => [
      index('followeeId').queryField('listFollowsByFollowee'),
    ])
    .authorization((allow) => [
      allow.ownerDefinedIn('followerId').identityClaim('sub').to(['create', 'read', 'delete']),
      allow.ownerDefinedIn('followeeId').identityClaim('sub').to(['read', 'delete']),
      allow.authenticated().to(['read']),
    ]),

  // ── 친구에게 보여 주는 공개 위시리스트 (서버 함수가 공개 항목만 골라 돌려줌) ──
  PublicTab: a.customType({
    tabId: a.string().required(),
    name: a.string().required(),
    colorHex: a.string(),
    sortOrder: a.integer(),
  }),
  PublicProduct: a.customType({
    productId: a.string().required(),
    listId: a.string().required(),
    name: a.string().required(),
    price: a.integer().required(),
    image: a.string(),
    platform: a.string(),
    originalPrice: a.integer(),
    discount: a.integer(),
    productUrl: a.string(),
  }),
  PublicWishlist: a.customType({
    ownerId: a.id().required(),
    tabs: a.ref('PublicTab').required().array().required(),
    products: a.ref('PublicProduct').required().array().required(),
  }),
  WishlistCount: a.customType({
    ownerId: a.id().required(),
    listCount: a.integer().required(),
    itemCount: a.integer().required(),
  }),

  // ── 3-2: 살까말까 · 댓글 · 알림 ────────────────────────────

  /** 내가 보낸 살까말까 기록. 본인만. (SharedBasket.toJson) */
  SentBasket: a
    .model({
      ownerId: a.id().required(),
      basketId: a.string().required(),
      data: a.json().required(),
    })
    .identifier(['ownerId', 'basketId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('ownerId').identityClaim('sub'),
    ]),

  /** 친구에게 받은 살까말까. 서버만 만들고, 받은 사람은 읽기·지우기만. */
  ReceivedBasket: a
    .model({
      recipientId: a.id().required(),
      basketId: a.string().required(),
      fromUid: a.id().required(),
      data: a.json().required(),
    })
    .identifier(['recipientId', 'basketId'])
    // 탈퇴한 사람이 보낸 바구니를 서버가 찾아 지우는 용도
    .secondaryIndexes((index) => [index('fromUid').name('byFromUid')])
    .authorization((allow) => [
      allow.ownerDefinedIn('recipientId').identityClaim('sub').to(['read', 'delete']),
    ]),

  /** 살까말까 댓글방. 참여자(보낸 사람 + 받은 사람들)만 읽는다. 쓰기는 서버만. */
  BasketThread: a
    .model({
      threadId: a.string().required(),
      ownerId: a.id().required(),
      participantIds: a.id().required().array().required(),
      memo: a.string(),
      // 투표할 수 있는 상품 번호(Product.id 문자열). 다시 보내면 새 상품이 더해진다.
      itemIds: a.string().array(),
    })
    .identifier(['threadId'])
    // 탈퇴한 사람이 만든 댓글방을 서버가 찾아 지우는 용도
    .secondaryIndexes((index) => [index('ownerId').name('byOwner')])
    .authorization((allow) => [
      allow.ownersDefinedIn('participantIds').identityClaim('sub').to(['read']),
    ]),

  /**
   * 댓글 한 개. 댓글방 참여자 목록을 같이 저장해서 참여자만 읽게 한다.
   * (참여자가 늘면 서버가 기존 댓글의 목록도 함께 고친다)
   * 쓰기·수정·삭제는 서버만 한다. 서버가 "작성자 본인인지" 확인한다.
   */
  BasketComment: a
    .model({
      threadId: a.string().required(),
      commentId: a.string().required(),
      authorId: a.id().required(),
      parentId: a.string(),
      participantIds: a.id().required().array().required(),
      data: a.json().required(),
    })
    .identifier(['threadId', 'commentId'])
    // 탈퇴한 사람이 남의 댓글방에 쓴 댓글을 서버가 찾아 지우는 용도
    .secondaryIndexes((index) => [index('authorId').name('byAuthor')])
    .authorization((allow) => [
      allow.ownersDefinedIn('participantIds').identityClaim('sub').to(['read']),
    ]),

  /**
   * 살까말까 투표: 한 사람당 한 줄 = 그 사람이 고른 상품들(여러 개 선택).
   * 댓글처럼 참여자만 읽고, 쓰기·바꾸기·취소는 서버만 한다(참여자인지, 보낸 상품인지 확인).
   * 마감은 없다. 살까말까(댓글방)를 따라가고, 다 빼고 투표하면 줄이 지워진다.
   */
  BasketVote: a
    .model({
      threadId: a.string().required(),
      voterId: a.id().required(),
      participantIds: a.id().required().array().required(),
      data: a.json().required(),
    })
    .identifier(['threadId', 'voterId'])
    .secondaryIndexes((index) => [index('voterId').name('byVoter')])
    .authorization((allow) => [
      allow.ownersDefinedIn('participantIds').identityClaim('sub').to(['read']),
    ]),

  /** 알림함. 서버만 만들고, 받은 사람은 읽기·읽음 표시·지우기만. */
  Notification: a
    .model({
      recipientId: a.id().required(),
      notificationId: a.string().required(),
      type: a.string().required(),
      read: a.boolean().required(),
      data: a.json().required(),
    })
    .identifier(['recipientId', 'notificationId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('recipientId').identityClaim('sub').to(['read', 'update', 'delete']),
    ]),

  /**
   * 차단 한 줄 = "blockerId 가 blockedId 를 차단했다". 차단한 사람만 만들고 읽고 지운다.
   * 차단된 사람은 이 표를 읽을 수 없다(차단 사실을 알리지 않음).
   */
  Block: a
    .model({
      blockerId: a.id().required(),
      blockedId: a.id().required(),
    })
    .identifier(['blockerId', 'blockedId'])
    // 서버가 "나를 차단한 사람"을 찾을 때, 탈퇴 시 정리할 때 쓴다.
    .secondaryIndexes((index) => [index('blockedId').name('byBlocked')])
    .authorization((allow) => [
      allow.ownerDefinedIn('blockerId').identityClaim('sub').to(['create', 'read', 'delete']),
    ]),

  /**
   * 신고 한 건. 서버 함수(reportContent)만 만든다. 신고한 사람은 자기 신고만 읽을 수 있다.
   * targetType: 'comment' | 'basket' | 'user'
   * status: 'open' → 담당자가 처리하면 'actioned'(삭제·정지) 또는 'dismissed'
   */
  Report: a
    .model({
      reporterId: a.id().required(),
      reportId: a.string().required(),
      targetType: a.string().required(),
      targetUserId: a.id().required(),
      targetId: a.string(),
      threadId: a.string(),
      reason: a.string().required(),
      detail: a.string(),
      snapshot: a.json(),
      status: a.string().required(),
    })
    .identifier(['reporterId', 'reportId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('reporterId').identityClaim('sub').to(['read']),
    ]),

  /** 살까말까 보내기: 댓글방 준비 → 받은 사람마다 받은함 + 알림. 받은 사람 수를 돌려준다. */
  sendBasket: a
    .mutation()
    .arguments({
      threadId: a.string().required(),
      recipientIds: a.id().required().array().required(),
      items: a.json().required(), // Product.toJson() 목록
      memo: a.string(),
    })
    .returns(a.integer().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  /** 댓글·답글 달기. 만든 댓글(BasketComment.toJson)을 돌려준다. */
  addBasketComment: a
    .mutation()
    .arguments({
      threadId: a.string().required(),
      text: a.string().required(),
      parentId: a.string(),
      // 댓글방이 아직 없을 때(보낸 사람이 첫 댓글) 만들 정보
      participantIds: a.id().array(),
      memo: a.string(),
    })
    .returns(a.json().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  editBasketComment: a
    .mutation()
    .arguments({
      threadId: a.string().required(),
      commentId: a.string().required(),
      text: a.string().required(),
    })
    .returns(a.boolean().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  removeBasketComment: a
    .mutation()
    .arguments({
      threadId: a.string().required(),
      commentId: a.string().required(),
    })
    .returns(a.boolean().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  /** 투표하기·다시 투표하기. productIds 가 비어 있으면 내 투표를 취소한다. */
  voteBasket: a
    .mutation()
    .arguments({
      threadId: a.string().required(),
      productIds: a.string().required().array().required(),
    })
    .returns(a.boolean().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  /**
   * 댓글·받은 살까말까·사용자 신고. 서버가 신고 당시 내용을 함께 저장한다.
   * reason: 'abuse' | 'harassment' | 'sexual' | 'spam' | 'other'
   */
  reportContent: a
    .mutation()
    .arguments({
      targetType: a.string().required(),
      targetUserId: a.id().required(),
      targetId: a.string(), // comment: commentId, basket: basketId(내 받은함)
      threadId: a.string(), // comment 일 때
      reason: a.string().required(),
      detail: a.string(),
    })
    .returns(a.boolean().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  /**
   * 탈퇴 직전에 호출: 내가 남긴 공유 콘텐츠를 지운다.
   * 남의 댓글방에 쓴 내 댓글, 친구 받은함에 있는 내가 보낸 바구니, 내가 만든 댓글방(과 그 댓글),
   * 나와 관련된 차단 기록. 지운 행 수를 돌려준다.
   */
  deleteMySocialData: a
    .mutation()
    .returns(a.integer().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  /** 팔로우 알림. 서버가 실제로 팔로우 중인지 확인하고 보낸다. 다시 팔로우해도 알림은 1개. */
  notifyFollow: a
    .mutation()
    .arguments({ targetId: a.id().required() })
    .returns(a.boolean().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  /** 한 사람의 공개 탭('전체' 제외)과 공개 상품. 메모는 포함하지 않는다. */
  publicWishlist: a
    .query()
    .arguments({ ownerId: a.id().required() })
    .returns(a.ref('PublicWishlist'))
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(publicWishlist)),

  /** 친구 목록에 보이는 "위시리스트 N · 아이템 M" 숫자를 여러 명 한 번에. (최대 100명) */
  publicWishlistCounts: a
    .query()
    .arguments({ ownerIds: a.id().required().array().required() })
    .returns(a.ref('WishlistCount').required().array().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(publicWishlist)),

  // ── AI 추출 엔진(parsing-engine) 연동 ──────────────────────

  /**
   * 엔진 서버(POST /extract)의 실제 응답을 그대로 옮긴 모양.
   * 필드 설명은 engine/server/main.py `_extract()` 참고.
   */
  ExtractedProduct: a.customType({
    // 엔진이 실제로 연 상품 페이지 주소(공유용 짧은 링크를 푼 결과). 앱은 이 주소를 저장한다.
    productUrl: a.string(),
    productName: a.string(),
    unconditionalPrice: a.integer(),
    regularPrice: a.integer(),
    currency: a.string(),
    imageUrl: a.string(),
    ambiguous: a.boolean().required(),
    ambiguityReason: a.string(),
    confidence: a.string(),
  }),

  /**
   * 상품 URL 하나를 AI 추출 엔진에 넘겨 이름·가격·이미지를 뽑는다. 로그인 사용자만
   * 호출 가능 — 엔진 서버 자체는 VPC 프라이빗 서브넷에 있어 이 함수를 거치지 않고는
   * 접근할 수 없다(Gemini API 남용·과금 폭탄 방지).
   */
  extractProduct: a
    .query()
    .arguments({ url: a.string().required() })
    .returns(a.ref('ExtractedProduct'))
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(parsingProxy)),

  /**
   * 태그 사진으로 찾은 결과. 필드 설명은 engine/server/tag_identify.py 참고.
   * status: 'found'(matchUrl 있음) | 'needs_confirm'(matchUrl 있음, 서버가 페이지를 못 읽어 품번 미확인 —
   *         앱이 사용자에게 같은 상품인지 꼭 묻고 담는다) | 'not_found'(태그 정보만 있음) | 'not_a_tag'
   * matchSource: 'official'(브랜드 공식몰) | 'mall'(공식몰에 없어 국내 쇼핑몰에서 찾음)
   * verifiedBy: 'product_code' | 'barcode' | 'product_code_base'(색상 뗀 기본 번호) | 'name'(품번 없이 이름으로만
   *             확인 — 앱이 한 번 더 확인) | 'search'(needs_confirm — 검색 결과일 뿐 확인 안 됨)
   *             | 'qr'(needs_confirm — 태그 QR이 가리킨 페이지를 못 읽어 확인 안 됨)
   * matchVia: 'qr'(태그 QR로 찾음) | 'search'(품번·브랜드 검색으로 찾음) | null(링크 없음)
   */
  IdentifiedTag: a.customType({
    status: a.string().required(),
    brand: a.string(),
    productCode: a.string(),
    productName: a.string(),
    color: a.string(),
    tagPrice: a.integer(),
    officialDomain: a.string(),
    matchUrl: a.string(),
    matchHost: a.string(),
    matchSource: a.string(),
    verifiedBy: a.string(),
    note: a.string(),
    // 찾은 페이지에서 읽은 정보(엔진이 구글의 페이지 사본으로 읽음 — 최신이 아닐 수 있음). 없으면 null.
    matchName: a.string(),
    matchPrice: a.integer(),
    matchRegularPrice: a.integer(),
    matchImage: a.string(),
    matchVia: a.string(),
  }),

  /**
   * 상품 태그 사진(base64)으로 그 상품의 상세 페이지 URL을 찾는다(공식몰 우선). 가격은 읽지
   * 않는다 — 앱이 찾은 URL을 기존 "URL로 담기"와 같은 경로로 읽는다. 로그인 사용자만 호출 가능.
   */
  identifyProductTag: a
    .query()
    .arguments({ imageBase64: a.string().required(), mimeType: a.string().required() })
    .returns(a.ref('IdentifiedTag'))
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(parsingProxy)),
});

export type Schema = ClientSchema<typeof schema>;

export const data = defineData({
  schema,
  authorizationModes: {
    defaultAuthorizationMode: 'userPool',
  },
});
