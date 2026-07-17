import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { pool, withTransaction } from '../config/database.js';
import { mapPost, postSelect } from '../db/posts.js';
import { HttpError } from '../middleware/errors.js';
import { requireUser } from '../middleware/user.js';
import { signPostImages } from '../services/oss.js';

const router = Router();

function text(value, max, required = false) {
  const result = typeof value === 'string' ? value.trim() : '';
  if (required && !result) throw new HttpError(400, 'Missing required text field');
  if (result.length > max) throw new HttpError(400, `Text exceeds ${max} characters`);
  return result;
}

function optionalNumber(value, { min = -Infinity, max = Infinity } = {}) {
  if (value == null || value === '') return null;
  const result = Number(value);
  if (!Number.isFinite(result) || result < min || result > max) {
    throw new HttpError(400, 'Invalid numeric field');
  }
  return result;
}

function publicCoordinates(location) {
  const latitude = optionalNumber(location?.latitude, { min: -90, max: 90 });
  const longitude = optionalNumber(location?.longitude, { min: -180, max: 180 });
  const privacy = ['EXACT', 'APPROXIMATE', 'PRIVATE'].includes(location?.privacy)
    ? location.privacy
    : 'PRIVATE';
  if (privacy === 'PRIVATE' || latitude == null || longitude == null) {
    return { privacy, latitude, longitude, publicLatitude: null, publicLongitude: null };
  }
  if (privacy === 'APPROXIMATE') {
    return {
      privacy,
      latitude,
      longitude,
      publicLatitude: Number(latitude.toFixed(3)),
      publicLongitude: Number(longitude.toFixed(3))
    };
  }
  return { privacy, latitude, longitude, publicLatitude: latitude, publicLongitude: longitude };
}

async function fetchPost(id, userId, connection = pool) {
  const query = postSelect(userId);
  const [rows] = await connection.execute(
    `${query.sql} WHERE p.id = ? AND p.visibility = 'PUBLIC'
      AND p.review_status = 'APPROVED' AND p.deleted_at IS NULL LIMIT 1`,
    [...query.params, id]
  );
  if (!rows[0]) throw new HttpError(404, 'Post not found');
  return signPostImages(mapPost(rows[0]));
}

router.get('/', requireUser, async (request, response) => {
  const limit = Math.min(Math.max(Number(request.query.limit) || 20, 1), 50);
  const offset = Math.max(Number(request.query.offset) || 0, 0);
  const query = postSelect(request.user.id);
  const [rows] = await pool.execute(
    `${query.sql} WHERE p.visibility = 'PUBLIC' AND p.review_status = 'APPROVED'
      AND p.deleted_at IS NULL ORDER BY p.created_at DESC LIMIT ${limit} OFFSET ${offset}`,
    query.params
  );
  response.json({ items: rows.map(mapPost).map(signPostImages), limit, offset, hasMore: rows.length === limit });
});

router.get('/:id', requireUser, async (request, response) => {
  response.json(await fetchPost(request.params.id, request.user.id));
});

router.post('/', requireUser, async (request, response) => {
  const body = request.body || {};
  const kind = body.kind === 'ASSIGNMENT' ? 'ASSIGNMENT' : 'ORIGINAL';
  const originalId = kind === 'ASSIGNMENT' ? text(body.originalId, 36, true) : null;
  const image = body.image || {};
  const metadata = body.metadata || {};
  const location = body.location || {};
  const coordinates = publicCoordinates(location);
  const postId = randomUUID();

  await withTransaction(async connection => {
    if (originalId) {
      const [originals] = await connection.execute(
        `SELECT id FROM posts WHERE id = ? AND allow_remake = TRUE AND visibility = 'PUBLIC'
          AND review_status = 'APPROVED' AND deleted_at IS NULL FOR UPDATE`,
        [originalId]
      );
      if (!originals[0]) throw new HttpError(400, 'Original post cannot be remade');
    }

    await connection.execute(
      `INSERT INTO posts (
        id, author_id, kind, original_post_id, title, description,
        image_object_key, image_url, display_image_url, thumbnail_url,
        allow_remake, shooting_notes, editing_notes, reused_notes, adjusted_notes, assignment_notes
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        postId,
        request.user.id,
        kind,
        originalId,
        text(body.title, 120, true),
        text(body.description, 10000),
        text(image.objectKey, 512) || null,
        text(image.originalUrl, 1000) || null,
        text(image.displayUrl, 1000) || null,
        text(image.thumbnailUrl, 1000) || null,
        body.allowRemake !== false,
        text(body.shootingNotes, 10000),
        text(body.editingNotes, 10000),
        text(body.reusedNotes, 10000),
        text(body.adjustedNotes, 10000),
        text(body.assignmentNotes, 10000)
      ]
    );

    await connection.execute(
      `INSERT INTO capture_metadata (
        post_id, camera_make, camera_model, camera_display, lens_model,
        focal_length_mm, aperture, shutter_seconds, iso, exposure_compensation, captured_at, source
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        postId,
        text(metadata.cameraMake, 120),
        text(metadata.cameraModel, 160),
        text(metadata.camera, 240),
        text(metadata.lens, 240),
        optionalNumber(metadata.focalLengthMm, { min: 0 }),
        optionalNumber(metadata.aperture, { min: 0 }),
        optionalNumber(metadata.shutterSeconds, { min: 0 }),
        optionalNumber(metadata.iso, { min: 0, max: 10000000 }),
        optionalNumber(metadata.exposureCompensation, { min: -20, max: 20 }),
        metadata.capturedAt || null,
        ['EXIF', 'USER_CONFIRMED', 'MANUAL'].includes(metadata.source) ? metadata.source : 'MANUAL'
      ]
    );

    await connection.execute(
      `INSERT INTO post_locations (
        post_id, place_name, city, district, privacy_level, latitude, longitude,
        public_latitude, public_longitude, shooting_advice
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        postId,
        text(location.name, 200),
        text(location.city, 80),
        text(location.district, 100),
        coordinates.privacy,
        coordinates.latitude,
        coordinates.longitude,
        coordinates.publicLatitude,
        coordinates.publicLongitude,
        text(location.advice, 300)
      ]
    );

    if (originalId) {
      await connection.execute(
        `INSERT INTO remake_plans
          (id, user_id, original_post_id, status, completed_assignment_id, completed_at)
          VALUES (?, ?, ?, 'COMPLETED', ?, CURRENT_TIMESTAMP(3))
          ON DUPLICATE KEY UPDATE status = 'COMPLETED',
            completed_assignment_id = VALUES(completed_assignment_id),
            completed_at = CURRENT_TIMESTAMP(3)`,
        [randomUUID(), request.user.id, originalId, postId]
      );
    }
  });

  response.status(201).json(await fetchPost(postId, request.user.id));
});

router.put('/:id/like', requireUser, async (request, response) => {
  const result = await withTransaction(async connection => {
    const [posts] = await connection.execute(
      'SELECT id FROM posts WHERE id = ? AND deleted_at IS NULL FOR UPDATE',
      [request.params.id]
    );
    if (!posts[0]) throw new HttpError(404, 'Post not found');
    const [likes] = await connection.execute(
      'SELECT user_id FROM post_likes WHERE user_id = ? AND post_id = ?',
      [request.user.id, request.params.id]
    );
    if (likes[0]) {
      await connection.execute('DELETE FROM post_likes WHERE user_id = ? AND post_id = ?', [
        request.user.id,
        request.params.id
      ]);
      await connection.execute(
        'UPDATE posts SET like_count = GREATEST(like_count - 1, 0) WHERE id = ?',
        [request.params.id]
      );
      return false;
    }
    await connection.execute('INSERT INTO post_likes (user_id, post_id) VALUES (?, ?)', [
      request.user.id,
      request.params.id
    ]);
    await connection.execute('UPDATE posts SET like_count = like_count + 1 WHERE id = ?', [
      request.params.id
    ]);
    return true;
  });
  const post = await fetchPost(request.params.id, request.user.id);
  response.json({ liked: result, likeCount: post.likeCount });
});

router.get('/:id/comments', requireUser, async (request, response) => {
  const [rows] = await pool.execute(
    `SELECT c.id, c.content, c.parent_id AS parentId, c.created_at AS createdAt,
      u.id AS authorId, u.nickname AS authorName, u.avatar_url AS authorAvatar
      FROM comments c JOIN users u ON u.id = c.author_id
      WHERE c.post_id = ? AND c.status = 'VISIBLE' ORDER BY c.created_at ASC LIMIT 200`,
    [request.params.id]
  );
  response.json({
    items: rows.map(row => ({
      id: row.id,
      content: row.content,
      parentId: row.parentId,
      createdAt: row.createdAt,
      author: { id: row.authorId, name: row.authorName, avatarUrl: row.authorAvatar }
    }))
  });
});

router.post('/:id/comments', requireUser, async (request, response) => {
  const content = text(request.body?.content, 1000, true);
  const commentId = randomUUID();
  await withTransaction(async connection => {
    const [posts] = await connection.execute(
      'SELECT id FROM posts WHERE id = ? AND deleted_at IS NULL FOR UPDATE',
      [request.params.id]
    );
    if (!posts[0]) throw new HttpError(404, 'Post not found');
    await connection.execute(
      'INSERT INTO comments (id, post_id, author_id, content) VALUES (?, ?, ?, ?)',
      [commentId, request.params.id, request.user.id, content]
    );
    await connection.execute('UPDATE posts SET comment_count = comment_count + 1 WHERE id = ?', [
      request.params.id
    ]);
  });
  response.status(201).json({
    id: commentId,
    content,
    author: {
      id: request.user.id,
      name: request.user.nickname,
      avatarUrl: request.user.avatarUrl
    }
  });
});

router.put('/:id/plan', requireUser, async (request, response) => {
  const planned = await withTransaction(async connection => {
    const [posts] = await connection.execute(
      `SELECT id FROM posts WHERE id = ? AND allow_remake = TRUE AND kind = 'ORIGINAL'
        AND deleted_at IS NULL`,
      [request.params.id]
    );
    if (!posts[0]) throw new HttpError(400, 'Post cannot be added to remake plans');
    const [plans] = await connection.execute(
      'SELECT id, status FROM remake_plans WHERE user_id = ? AND original_post_id = ?',
      [request.user.id, request.params.id]
    );
    if (plans[0]?.status === 'COMPLETED') return true;
    if (plans[0]) {
      await connection.execute('DELETE FROM remake_plans WHERE id = ?', [plans[0].id]);
      return false;
    }
    await connection.execute(
      'INSERT INTO remake_plans (id, user_id, original_post_id) VALUES (?, ?, ?)',
      [randomUUID(), request.user.id, request.params.id]
    );
    return true;
  });
  response.json({ planned });
});

export default router;
