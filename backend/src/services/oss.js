import OSS from 'ali-oss';
import { randomUUID } from 'node:crypto';
import { extname } from 'node:path';
import { env } from '../config/env.js';
import { HttpError } from '../middleware/errors.js';

export function isOSSConfigured() {
  return Boolean(env.oss.region && env.oss.bucket && env.oss.accessKeyId && env.oss.accessKeySecret);
}

function client() {
  if (!isOSSConfigured()) throw new HttpError(503, 'OSS is not configured');
  return new OSS({
    region: env.oss.region,
    bucket: env.oss.bucket,
    endpoint: env.oss.endpoint || undefined,
    accessKeyId: env.oss.accessKeyId,
    accessKeySecret: env.oss.accessKeySecret,
    secure: env.oss.secure
  });
}

function safeExtension(fileName, mimeType) {
  const allowed = new Map([
    ['image/jpeg', '.jpg'],
    ['image/png', '.png'],
    ['image/heic', '.heic'],
    ['image/heif', '.heif'],
    ['image/webp', '.webp']
  ]);
  const fromMime = allowed.get(mimeType);
  if (fromMime) return fromMime;
  const extension = extname(fileName || '').toLowerCase();
  return [...allowed.values()].includes(extension) ? extension : '.jpg';
}

export function createUploadSignature({ userId, fileName, mimeType, variant = 'original' }) {
  if (!['original', 'display', 'thumbnail'].includes(variant)) {
    throw new HttpError(400, 'Invalid image variant');
  }
  const extension = safeExtension(fileName, mimeType);
  const now = new Date();
  const objectKey = [
    'photos',
    String(now.getUTCFullYear()),
    String(now.getUTCMonth() + 1).padStart(2, '0'),
    userId,
    `${randomUUID()}-${variant}${extension}`
  ].join('/');

  const oss = client();
  const uploadUrl = oss.signatureUrl(objectKey, {
    method: 'PUT',
    expires: 10 * 60,
    'Content-Type': mimeType
  });
  const publicBase = env.oss.publicBaseUrl.replace(/\/$/, '');
  const objectUrl = publicBase
    ? `${publicBase}/${objectKey}`
    : `https://${env.oss.bucket}.${env.oss.region}.aliyuncs.com/${objectKey}`;

  return { objectKey, uploadUrl, objectUrl, expiresIn: 600, method: 'PUT', headers: { 'Content-Type': mimeType } };
}

export function createDownloadUrl(objectKey) {
  if (!objectKey) return null;
  return client().signatureUrl(objectKey, {
    method: 'GET',
    expires: 60 * 60
  });
}

export function signPostImages(post) {
  if (!post.image?.objectKey || !isOSSConfigured()) return post;
  const signedURL = createDownloadUrl(post.image.objectKey);
  return {
    ...post,
    image: {
      ...post.image,
      originalUrl: signedURL,
      displayUrl: signedURL,
      thumbnailUrl: signedURL
    }
  };
}
