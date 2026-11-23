import type { Db } from "mongodb";
import { invoicesToCsv, type Invoice } from "../exports/invoicesCsv.js";

// GET /exports/invoices?month=2026-10: the CSV accounting imports at each month end
export async function exportMonth(db: Db, accountId: string, month: string): Promise<string> {
  const start = new Date(`${month}-01T00:00:00Z`);
  const end = new Date(start);
  end.setUTCMonth(end.getUTCMonth() + 1);
  const invoices = await db
    .collection<Invoice & { accountId: string }>("invoices")
    .find({ accountId, issuedAt: { $gte: start, $lt: end } })
    .sort({ issuedAt: 1 })
    .toArray();
  return invoicesToCsv(invoices);
}
