export interface ProviderInvoice {
  id: string;
  amountCents: number;
  issuedAt: string;
}

export type FetchInvoices = (billingId: string) => Promise<ProviderInvoice[]>;

const BASE_URL = process.env.BILLING_BASE_URL ?? 'https://billing.example.test';

export const fetchInvoices: FetchInvoices = async (billingId) => {
  const response = await fetch(`${BASE_URL}/customers/${encodeURIComponent(billingId)}/invoices`);
  if (!response.ok) {
    throw new Error(`billing provider answered ${response.status} for ${billingId}`);
  }
  return response.json();
};
