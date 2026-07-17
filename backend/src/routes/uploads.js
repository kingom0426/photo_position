import { Router } from 'express';
import { requireUser } from '../middleware/user.js';
import { createUploadSignature } from '../services/oss.js';

const router = Router();

router.post('/presign', requireUser, (request, response) => {
  const { fileName = 'photo.jpg', mimeType = 'image/jpeg', variant = 'original' } =
    request.body || {};
  response.json(
    createUploadSignature({
      userId: request.user.id,
      fileName,
      mimeType,
      variant
    })
  );
});

export default router;
