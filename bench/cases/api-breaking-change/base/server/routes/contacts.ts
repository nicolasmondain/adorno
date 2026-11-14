import { Router } from 'express';
import type { Db } from 'mongodb';

export interface Contact {
  _id: string;
  accountId: string;
  email: string;
  createdAt: Date;
}

// `res.locals.accountId` is set by the API key middleware mounted before this router.
export function contactsRouter(db: Db): Router {
  const router = Router();
  const contacts = db.collection<Contact>('contacts');

  // Public API v1, documented in docs/api-reference/contacts.md.
  router.get('/v1/contacts', async (req, res) => {
    const accountId: string = res.locals.accountId;
    const limit = Math.min(Number(req.query.limit) || 50, 200);
    const [items, total] = await Promise.all([
      contacts.find({ accountId }).sort({ createdAt: -1 }).limit(limit).toArray(),
      contacts.countDocuments({ accountId }),
    ]);
    res.json({ items, total });
  });

  return router;
}
