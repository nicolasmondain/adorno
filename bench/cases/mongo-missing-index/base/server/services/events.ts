import type { Db, ObjectId } from 'mongodb';

export interface TrackedEvent {
  _id: ObjectId;
  accountId: ObjectId;
  contactId: ObjectId;
  campaignId: ObjectId | null;
  type: 'sent' | 'opened' | 'clicked' | 'replied';
  createdAt: Date;
}

const PAGE_SIZE = 50;

export async function listContactEvents(db: Db, accountId: ObjectId, contactId: ObjectId): Promise<TrackedEvent[]> {
  return db
    .collection<TrackedEvent>('events')
    .find({ accountId, contactId })
    .sort({ createdAt: -1 })
    .limit(PAGE_SIZE)
    .toArray();
}
