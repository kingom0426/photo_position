export class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

export function notFound(request, response) {
  response.status(404).json({ error: 'Not found', path: request.path });
}

export function errorHandler(error, request, response, next) {
  if (response.headersSent) return next(error);
  const status = error.status || 500;
  if (status >= 500) console.error(error);
  response.status(status).json({
    error: status === 500 ? 'Internal server error' : error.message,
    ...(error.details ? { details: error.details } : {})
  });
}
