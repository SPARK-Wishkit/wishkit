import type { AppSyncIdentityCognito } from 'aws-lambda';
import { type AmplifyFunctionEvent, fieldNameOf } from '../shared/appsync-event';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DeleteCommand, DynamoDBDocumentClient, GetCommand, PutCommand } from '@aws-sdk/lib-dynamodb';
import { PublishCommand, SNSClient } from '@aws-sdk/client-sns';
import { queryAll } from '../shared/ddb';
import {
  ActionError,
  addComment,
  blockUser,
  deleteComment,
  deleteMyContent,
  notifyFollow,
  reportContent,
  sendBasket,
  updateComment,
  voteBasket,
  type Db,
  type Row,
  type Table,
} from './logic';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

// backend.ts 에서 넣어 주는 표 이름
const TABLES: Record<Table, string> = {
  Profile: process.env.PROFILE_TABLE ?? '',
  Follow: process.env.FOLLOW_TABLE ?? '',
  BasketThread: process.env.THREAD_TABLE ?? '',
  BasketComment: process.env.COMMENT_TABLE ?? '',
  BasketVote: process.env.VOTE_TABLE ?? '',
  ReceivedBasket: process.env.RECEIVED_TABLE ?? '',
  Notification: process.env.NOTIFICATION_TABLE ?? '',
  Block: process.env.BLOCK_TABLE ?? '',
  ContentReport: process.env.REPORT_TABLE ?? '',
};

// 신고·차단을 운영팀 메일로 보내는 SNS 주제 (backend.ts). 없으면 메일 없이 표에만 남긴다.
const sns = new SNSClient({});
const REPORT_TOPIC_ARN = process.env.REPORT_TOPIC_ARN ?? '';
async function alert(subject: string, message: string) {
  if (!REPORT_TOPIC_ARN) return;
  // SNS 메일 제목은 100자까지, 줄바꿈 불가.
  await sns.send(
    new PublishCommand({
      TopicArn: REPORT_TOPIC_ARN,
      Subject: subject.replace(/\s+/g, ' ').slice(0, 100),
      Message: message,
    }),
  );
}

const db: Db = {
  async get(table, key) {
    const res = await ddb.send(new GetCommand({ TableName: TABLES[table], Key: key }));
    return res.Item as Row | undefined;
  },
  async put(table, item) {
    await ddb.send(new PutCommand({ TableName: TABLES[table], Item: item }));
  },
  async del(table, key) {
    await ddb.send(new DeleteCommand({ TableName: TABLES[table], Key: key }));
  },
  query(table, keyName, keyValue) {
    return queryAll(ddb, {
      TableName: TABLES[table],
      KeyConditionExpression: '#k = :v',
      ExpressionAttributeNames: { '#k': keyName },
      ExpressionAttributeValues: { ':v': keyValue },
    });
  },
  queryIndex(table, indexName, keyName, keyValue) {
    return queryAll(ddb, {
      TableName: TABLES[table],
      IndexName: indexName,
      KeyConditionExpression: '#k = :v',
      ExpressionAttributeNames: { '#k': keyName },
      ExpressionAttributeValues: { ':v': keyValue },
    });
  },
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Args = Record<string, any>;

export const handler = async (event: AmplifyFunctionEvent<Args>): Promise<unknown> => {
  const fieldName = fieldNameOf(event);
  // 호출한 사람은 토큰에서만 가져온다. (앱이 보낸 값은 믿지 않는다)
  const caller = (event.identity as AppSyncIdentityCognito | null)?.sub;
  if (!caller) throw new Error('UNAUTHENTICATED');
  const env = { db, alert };
  const a = event.arguments;

  try {
    switch (fieldName) {
      case 'sendBasket':
        return await sendBasket(env, caller, {
          threadId: a.threadId,
          recipientIds: a.recipientIds,
          items: a.items,
          memo: a.memo,
          allowMultipleVotes: a.allowMultipleVotes,
          voteEnabled: a.voteEnabled,
        });
      case 'addBasketComment':
        return await addComment(env, caller, {
          threadId: a.threadId,
          text: a.text,
          parentId: a.parentId,
          participantIds: a.participantIds,
          memo: a.memo,
        });
      case 'editBasketComment':
        return await updateComment(env, caller, {
          threadId: a.threadId,
          commentId: a.commentId,
          text: a.text,
        });
      case 'removeBasketComment':
        return await deleteComment(env, caller, {
          threadId: a.threadId,
          commentId: a.commentId,
        });
      case 'voteBasket':
        return await voteBasket(env, caller, {
          threadId: a.threadId,
          productIds: a.productIds,
        });
      case 'notifyFollow':
        return await notifyFollow(env, caller, { targetId: a.targetId });
      case 'reportContent':
        return await reportContent(env, caller, {
          targetType: a.targetType,
          targetUserId: a.targetUserId,
          threadId: a.threadId,
          commentId: a.commentId,
          basketId: a.basketId,
          reason: a.reason,
          detail: a.detail,
        });
      case 'blockUser':
        return await blockUser(env, caller, { targetId: a.targetId });
      case 'deleteMyContent':
        return await deleteMyContent(env, caller);
      default:
        throw new Error(`Unknown field: ${fieldName}`);
    }
  } catch (e) {
    // 약속된 오류 코드는 그대로, 그 밖의 오류는 내부 내용을 숨긴다.
    if (e instanceof ActionError) throw new Error(e.code);
    console.error('social-actions failed', fieldName, e);
    throw new Error('INTERNAL');
  }
};
