import type { Db } from "mongodb";

export async function markInvoicePaid(db: Db, invoiceId: string, paidAt: string): Promise<void> {
  const result = await db
    .collection<{ _id: string; status: string; paidAt?: Date }>("invoices")
    .updateOne({ _id: invoiceId, status: "open" }, { $set: { status: "paid", paidAt: new Date(paidAt) } });
  if (result.matchedCount === 0) {
    throw new Error(`invoice ${invoiceId} is not open`);
  }
}
