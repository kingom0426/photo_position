import { pool } from '../config/database.js';
import { HttpError } from './errors.js';

export async function requireUser(request, response, next) {
  try {
    const userId = request.get('x-user-id')?.trim();
    if (!userId) throw new HttpError(401, 'Missing x-user-id header');

    const [rows] = await pool.execute(
      'SELECT id, nickname, avatar_url AS avatarUrl, city FROM users WHERE id = ? AND status = ? LIMIT 1',
      [userId, 'ACTIVE']
    );
    if (!rows[0]) throw new HttpError(401, 'Unknown or inactive user');
    request.user = rows[0];
    next();
  } catch (error) {
    next(error);
  }
}
