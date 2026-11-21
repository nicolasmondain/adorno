import type { Db } from "mongodb";
import { listOrders, type PageQuery } from "./orders.js";

export type Request = { accountId: string; query: PageQuery };

export function routes(db: Db) {
  return {
    "GET /orders": (req: Request) => listOrders(db, req.accountId, req.query),
  };
}
