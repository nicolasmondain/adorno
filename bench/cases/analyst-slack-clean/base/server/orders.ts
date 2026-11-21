import type { Db } from "mongodb";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;

export type PageQuery = { page?: string; limit?: string };

// page is 1-based: the first page is page=1, as the web app and the mobile client send it
export function pageParams(query: PageQuery): { page: number; limit: number } {
  const page = Math.max(1, Number.parseInt(query.page ?? "", 10) || 1);
  const limit = Math.min(MAX_LIMIT, Number.parseInt(query.limit ?? "", 10) || DEFAULT_LIMIT);
  return { page, limit };
}

export async function listOrders(db: Db, accountId: string, query: PageQuery) {
  const { page, limit } = pageParams(query);
  const orders = await db
    .collection("orders")
    .find({ accountId }, { projection: { _id: 1, number: 1, totalCents: 1, createdAt: 1 } })
    .sort({ createdAt: -1 })
    .skip(page * limit)
    .limit(limit)
    .toArray();
  return { page, limit, orders };
}
