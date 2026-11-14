import { config } from '../config.ts';

export interface Charge {
  id: string;
  amountCents: number;
  status: 'pending' | 'succeeded' | 'failed';
}

export async function createCharge(customerId: string, amountCents: number): Promise<Charge> {
  const response = await fetch(`${config.paymentsBaseUrl}/charges`, {
    method: 'POST',
    headers: { authorization: `Bearer ${config.paymentsApiKey}`, 'content-type': 'application/json' },
    body: JSON.stringify({ customerId, amountCents }),
  });
  if (!response.ok) {
    throw new Error(`payments provider answered ${response.status}`);
  }
  return response.json();
}
