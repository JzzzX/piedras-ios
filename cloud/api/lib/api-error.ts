import { randomUUID } from 'node:crypto';
import { NextResponse } from 'next/server';

type HeaderSource = Pick<Request, 'headers'> | undefined;

export interface ApiRequestContext {
  requestId: string;
  route: string;
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

export function jsonResponse(
  context: ApiRequestContext,
  body: unknown,
  init?: ResponseInit
) {
  return NextResponse.json(body, {
    ...init,
    headers: withRequestHeaders(context, init?.headers),
  });
}

export function textResponse(
  context: ApiRequestContext,
  body: BodyInit | null,
  init?: ResponseInit
) {
  return new Response(body, {
    ...init,
    headers: withRequestHeaders(context, init?.headers),
  });
}

export function errorResponse(
  context: ApiRequestContext,
  status: number,
  error: string,
  cause?: unknown
) {
  const detail =
    cause instanceof Error ? cause.message : typeof cause === 'string' ? cause : undefined;

  console.error(
    `[api-error] route=${context.route} requestId=${context.requestId} status=${status}` +
      (detail ? ` detail=${detail}` : ''),
    cause
  );

  return jsonResponse(
    context,
    {
      error,
      requestId: context.requestId,
      route: context.route,
    },
    { status }
  );
}
