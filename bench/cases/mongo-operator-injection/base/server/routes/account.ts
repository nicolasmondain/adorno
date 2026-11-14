import { Router } from 'express';
import type { Db } from 'mongodb';

export interface Account {
  _id: string;
  name: string;
  plan: 'free' | 'pro';
  apiToken: string;
}

export function accountRouter(db: Db): Router {
  const router = Router();

  router.get('/health', (_req, res) => {
    res.json({ ok: true });
  });

  return router;
}
