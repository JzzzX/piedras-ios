import { randomUUID } from 'node:crypto';

type HeaderSource = Pick<Request, 'headers'> | undefined;

export interface ApiRequestContext {
  requestId: string;
  route: string;
}

export interface ApiErrorResponseOptions {
  logLevel?: 'error' | 'warn' | 'silent';
}

export class ApiRouteError extends Error {
  status: number;
  logLevel: ApiErrorResponseOptions['logLevel'];

  constructor(
    status: number,
    message: string,
    options?: {
      cause?: unknown;
      logLevel?: ApiErrorResponseOptions['logLevel'];
    }
  ) {
    super(message, { cause: options?.cause });
    this.name = 'ApiRouteError';
    this.status = status;
    this.logLevel = options?.logLevel ?? 'error';
  }
}

function incomingRequestId(source: HeaderSource): string | null {
  const value = source?.headers.get('x-request-id')?.trim();
  return value ? value : null;
}

export function createRequestContext(source: HeaderSource, route: string): ApiRequestContext {
  return {
    route,
    requestId: incomingRequestId(source) || randomUUID(),
  };
}

export function withRequestHeaders(
  context: ApiRequestContext,
  headers?: HeadersInit
): Headers {
  const resolvedHeaders = new Headers(headers);
  resolvedHeaders.set('X-Request-Id', context.requestId);
  return resolvedHeaders;
}

export function logApiError(
  context: ApiRequestContext,
  status: number,
  cause?: unknown,
  options?: ApiErrorResponseOptions
) {
  const detail =
    cause instanceof Error ? cause.message : typeof cause === 'string' ? cause : undefined;

  const message =
    `[api-error] route=${context.route} requestId=${context.requestId} status=${status}` +
    (detail ? ` detail=${detail}` : '');
  const logLevel = options?.logLevel ?? 'error';

  if (logLevel !== 'silent') {
    const args = cause === undefined ? [message] : [message, cause];
    if (logLevel === 'warn') {
      console.warn(...args);
    } else {
      console.error(...args);
    }
  }
}
