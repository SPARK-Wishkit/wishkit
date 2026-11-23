import { type AmplifyFunctionEvent, fieldNameOf } from '../shared/appsync-event';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand } from '@aws-sdk/lib-dynamodb';
import type { AppSyncIdentityCognito } from 'aws-lambda';
import { queryAll } from '../shared/ddb';
import { loadCounts, loadPublicWishlist, type QueryPublic } from './logic';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

// backend.ts 에서 넣어 주는 표 이름
const TABLES = {
  tab: process.env.WISH_TAB_TABLE ?? '',
  product: process.env.WISH_PRODUCT_TABLE ?? '',
  block: process.env.BLOCK_TABLE ?? '',
};

/** a·b 사이에 어느 쪽이든 차단이 있으면 true. (차단 관계면 공개 위시리스트를 보여 주지 않는다) */
async function blockedEitherWay(a: string, b: string): Promise<boolean> {
  if (!a || !b || a === b || !TABLES.block) return false;
  const get = (blockerId: string, blockedId: string) =>
    ddb.send(new GetCommand({ TableName: TABLES.block, Key: { blockerId, blockedId } }));
  const [ab, ba] = await Promise.all([get(a, b), get(b, a)]);
  return Boolean(ab.Item || ba.Item);
}

/** ownerId 파티션만 조회(Query)한다. 전체 표 훑기(Scan)는 하지 않는다. */
const queryPublic: QueryPublic = (table, ownerId) =>
  queryAll(ddb, {
    TableName: TABLES[table],
    KeyConditionExpression: '#o = :o',
    FilterExpression: '#p = :t',
    ExpressionAttributeNames: { '#o': 'ownerId', '#p': 'isPublic' },
    ExpressionAttributeValues: { ':o': ownerId, ':t': true },
  });

type Args = { ownerId?: string; ownerIds?: string[] };

export const handler = async (event: AmplifyFunctionEvent<Args>): Promise<unknown> => {
  const fieldName = fieldNameOf(event);
  switch (fieldName) {
    case 'publicWishlist': {
      const ownerId = event.arguments.ownerId;
      if (!ownerId) throw new Error('ownerId is required');
      // 차단 관계면 빈 결과(null)를 돌려준다. 차단 사실은 알리지 않는다.
      const caller = (event.identity as AppSyncIdentityCognito | null)?.sub ?? '';
      if (await blockedEitherWay(caller, ownerId)) return null;
      return loadPublicWishlist(queryPublic, ownerId);
    }
    case 'publicWishlistCounts':
      return loadCounts(queryPublic, event.arguments.ownerIds ?? []);
    default:
      throw new Error(`Unknown field: ${fieldName}`);
  }
};
