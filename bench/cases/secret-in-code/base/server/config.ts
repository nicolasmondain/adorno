function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`missing environment variable: ${name}`);
  }
  return value;
}

export const config = {
  port: Number(process.env.PORT ?? 3000),
  mongoUrl: requireEnv('MONGO_URL'),
  paymentsBaseUrl: process.env.PAYMENTS_BASE_URL ?? 'https://payments.example.test',
  paymentsApiKey: requireEnv('PAYMENTS_API_KEY'),
};
