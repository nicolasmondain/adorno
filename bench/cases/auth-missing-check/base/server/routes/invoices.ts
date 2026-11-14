import { Router } from 'express';
import type { Db } from 'mongodb';
import { requirePermission, type Member } from '../lib/permissions.ts';

export interface Invoice {
  _id: string;
  accountId: string;
  amount: number;
  status: 'draft' | 'sent' | 'paid';
}

// `res.locals.member` is set by the session middleware mounted before this router.
export function invoicesRouter(db: Db): Router {
  const router = Router();
  const invoices = db.collection<Invoice>('invoices');

  router.get('/invoices/:id', async (req, res) => {
    const member: Member = res.locals.member;
    requirePermission(member, 'invoices:read');
    const invoice = await invoices.findOne({ _id: req.params.id, accountId: member.accountId });
    if (!invoice) {
      res.status(404).json({ error: 'invoice_not_found' });
      return;
    }
    res.json(invoice);
  });

  router.patch('/invoices/:id', async (req, res) => {
    const member: Member = res.locals.member;
    requirePermission(member, 'invoices:write');
    const result = await invoices.updateOne(
      { _id: req.params.id, accountId: member.accountId, status: 'draft' },
      { $set: { amount: Number(req.body.amount) } },
    );
    if (result.matchedCount === 0) {
      res.status(404).json({ error: 'invoice_not_found' });
      return;
    }
    res.status(204).end();
  });

  return router;
}
