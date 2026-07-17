import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import { pool } from './config/database.js';
import { env } from './config/env.js';
import { errorHandler, notFound } from './middleware/errors.js';
import postsRouter from './routes/posts.js';
import uploadsRouter from './routes/uploads.js';
import { isOSSConfigured } from './services/oss.js';

export const app = express();

app.disable('x-powered-by');
app.use(helmet());
app.use(
  cors({
    origin(origin, callback) {
      if (!origin || env.allowedOrigins.length === 0 || env.allowedOrigins.includes(origin)) {
        callback(null, true);
      } else {
        callback(new Error('Origin not allowed'));
      }
    }
  })
);
app.use(express.json({ limit: '1mb' }));

app.get('/api/health', async (_request, response) => {
  await pool.query('SELECT 1');
  response.json({ status: 'ok', database: 'connected', oss: isOSSConfigured() ? 'configured' : 'missing_config' });
});

app.use('/api/posts', postsRouter);
app.use('/api/uploads', uploadsRouter);
app.use(notFound);
app.use(errorHandler);
