import { resolve } from 'node:path';
import dotenv from 'dotenv';

dotenv.config({ path: resolve(process.cwd(), '.env.local') });
dotenv.config({ path: resolve(process.cwd(), '.env') });

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function boolean(name, fallback = false) {
  const value = process.env[name];
  if (value == null || value === '') return fallback;
  return value.toLowerCase() === 'true';
}

export const env = {
  port: Number(process.env.PORT || 8080),
  db: {
    host: required('DB_HOST'),
    port: Number(process.env.DB_PORT || 3306),
    user: required('DB_USER'),
    password: required('DB_PASSWORD'),
    database: required('DB_NAME'),
    ssl: boolean('DB_SSL')
  },
  oss: {
    region: process.env.OSS_REGION?.trim() || '',
    bucket: process.env.OSS_BUCKET?.trim() || '',
    endpoint: process.env.OSS_ENDPOINT?.trim() || '',
    accessKeyId: process.env.OSS_ACCESS_KEY_ID?.trim() || '',
    accessKeySecret: process.env.OSS_ACCESS_KEY_SECRET?.trim() || '',
    secure: boolean('OSS_SECURE', true),
    publicBaseUrl: process.env.OSS_PUBLIC_BASE_URL?.trim() || ''
  },
  allowedOrigins: (process.env.ALLOWED_ORIGINS || '')
    .split(',')
    .map(value => value.trim())
    .filter(Boolean)
};
