export interface Invoice {
  number: string;
  totalCents: number;
}

// One CSV line per invoice, for the accounting export.
export function invoiceLine(invoice: Invoice): string {
  return [invoice.number, (invoice.totalCents / 100).toFixed(2)].join(';');
}
