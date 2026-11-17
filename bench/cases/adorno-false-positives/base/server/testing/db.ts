import { MongoClient, type Db } from 'mongodb';
import { MongoMemoryServer } from 'mongodb-memory-server';

// Runs `fn` against a fresh in-memory database, dropped afterwards.
export async function withDb<T>(fn: (db: Db) => Promise<T>): Promise<T> {
  const server = await MongoMemoryServer.create();
  const client = await MongoClient.connect(server.getUri());
  try {
    return await fn(client.db('bench'));
  } finally {
    await client.close();
    await server.stop();
  }
}
