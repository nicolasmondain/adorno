import type { Db } from "mongodb";
import { markInvoicePaid } from "../services/invoices.js";

type PaymentEvent = { type: string; data: { invoiceId: string; paidAt: string } };
type Response = { status: (code: number) => Response; send: (body?: string) => void };
type Logger = { error: (context: object, message: string) => void };

// The payment provider retries a delivery until it gets a 2xx: a 500 makes it try again later.
export async function handlePaymentWebhook(event: PaymentEvent, res: Response, db: Db, logger: Logger) {
  if (event.type !== "payment.succeeded") {
    res.status(204).send();
    return;
  }
  try {
    markInvoicePaid(db, event.data.invoiceId, event.data.paidAt);
    res.status(200).send("ok");
  } catch (error) {
    logger.error({ err: error, invoiceId: event.data.invoiceId }, "payment webhook failed");
    res.status(500).send();
  }
}
