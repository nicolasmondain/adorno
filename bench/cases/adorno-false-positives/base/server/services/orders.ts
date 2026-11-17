import type { Db, ObjectId } from 'mongodb';

export interface Order {
  _id: ObjectId;
  accountId: ObjectId;
  customerId: ObjectId;
  total: number;
  createdAt: Date;
}

export interface Customer {
  _id: ObjectId;
  accountId: ObjectId;
  name: string;
}

const PAGE_SIZE = 200;

export async function listOrders(db: Db, accountId: ObjectId): Promise<Order[]> {
  return db
    .collection<Order>('orders')
    .find({ accountId })
    .sort({ createdAt: -1 })
    .limit(PAGE_SIZE)
    .toArray();
}
