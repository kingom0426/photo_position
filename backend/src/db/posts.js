function numeric(value) {
  return value == null ? null : Number(value);
}

export function postSelect(userId = null) {
  return {
    sql: `SELECT
      p.id, p.kind, p.original_post_id AS originalId, p.author_id AS authorId,
      u.nickname AS authorName, u.avatar_url AS authorAvatar, u.city AS authorCity,
      p.title, p.description, p.image_object_key AS imageObjectKey,
      p.image_url AS imageUrl, p.display_image_url AS displayImageUrl,
      p.thumbnail_url AS thumbnailUrl, p.allow_remake AS allowRemake,
      p.shooting_notes AS shootingNotes, p.editing_notes AS editingNotes,
      p.reused_notes AS reusedNotes, p.adjusted_notes AS adjustedNotes,
      p.assignment_notes AS assignmentNotes, p.is_recommended AS isRecommended,
      p.like_count AS likeCount, p.comment_count AS commentCount, p.created_at AS createdAt,
      m.camera_make AS cameraMake, m.camera_model AS cameraModel,
      m.camera_display AS camera, m.lens_model AS lens,
      m.focal_length_mm AS focalLengthMm, m.aperture,
      m.shutter_seconds AS shutterSeconds, m.iso, m.exposure_compensation AS exposureCompensation,
      m.captured_at AS capturedAt, m.source AS metadataSource,
      l.place_name AS placeName, l.city AS locationCity, l.district,
      l.privacy_level AS locationPrivacy, l.public_latitude AS latitude,
      l.public_longitude AS longitude, l.shooting_advice AS shootingAdvice,
      ${userId ? 'EXISTS(SELECT 1 FROM post_likes pl WHERE pl.post_id = p.id AND pl.user_id = ?) AS liked,' : 'FALSE AS liked,'}
      ${userId ? 'EXISTS(SELECT 1 FROM remake_plans rp WHERE rp.original_post_id = p.id AND rp.user_id = ?) AS planned' : 'FALSE AS planned'}
    FROM posts p
    JOIN users u ON u.id = p.author_id
    LEFT JOIN capture_metadata m ON m.post_id = p.id
    LEFT JOIN post_locations l ON l.post_id = p.id`,
    params: userId ? [userId, userId] : []
  };
}

export function mapPost(row) {
  return {
    id: row.id,
    kind: row.kind,
    originalId: row.originalId,
    author: {
      id: row.authorId,
      name: row.authorName,
      avatarUrl: row.authorAvatar,
      city: row.authorCity
    },
    title: row.title,
    description: row.description,
    image: {
      objectKey: row.imageObjectKey,
      originalUrl: row.imageUrl,
      displayUrl: row.displayImageUrl || row.imageUrl,
      thumbnailUrl: row.thumbnailUrl || row.displayImageUrl || row.imageUrl
    },
    allowRemake: Boolean(row.allowRemake),
    shootingNotes: row.shootingNotes,
    editingNotes: row.editingNotes,
    reusedNotes: row.reusedNotes,
    adjustedNotes: row.adjustedNotes,
    assignmentNotes: row.assignmentNotes,
    isRecommended: Boolean(row.isRecommended),
    likeCount: Number(row.likeCount),
    commentCount: Number(row.commentCount),
    liked: Boolean(row.liked),
    planned: Boolean(row.planned),
    createdAt: row.createdAt,
    metadata: {
      cameraMake: row.cameraMake || '',
      cameraModel: row.cameraModel || '',
      camera: row.camera || '',
      lens: row.lens || '',
      focalLengthMm: numeric(row.focalLengthMm),
      aperture: numeric(row.aperture),
      shutterSeconds: numeric(row.shutterSeconds),
      iso: row.iso == null ? null : Number(row.iso),
      exposureCompensation: numeric(row.exposureCompensation),
      capturedAt: row.capturedAt,
      source: row.metadataSource || 'MANUAL'
    },
    location: {
      name: row.placeName || '',
      city: row.locationCity || '',
      district: row.district || '',
      privacy: row.locationPrivacy || 'PRIVATE',
      latitude: numeric(row.latitude),
      longitude: numeric(row.longitude),
      advice: row.shootingAdvice || ''
    }
  };
}
