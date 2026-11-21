export type Invoice = { number: string; customerName: string; issuedAt: Date; totalCents: number; currency: string };

const HEADER = ["number", "customer", "issued_at", "total_cents", "currency"];

function escape(value: string | number): string {
  const text = String(value);
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function toRow(invoice: Invoice): string {
  return [invoice.number, invoice.customerName, invoice.issuedAt.toISOString(), invoice.totalCents, invoice.currency]
    .map(escape)
    .join(",");
}

// invoices: those of one month, oldest first
export function invoicesToCsv(invoices: Invoice[]): string {
  const lines = [HEADER.join(",")];
  for (let i = 0; i < invoices.length - 1; i += 1) {
    lines.push(toRow(invoices[i]));
  }
  return `${lines.join("\n")}\n`;
}
