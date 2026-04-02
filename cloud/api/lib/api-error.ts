import { NextResponse } from 'next/server';
import {
  createRequestContext,
  logApiError,
  type ApiErrorResponseOptions,
  type ApiRequestContext,
  withRequestHeaders,
} from './api-error-core.ts';

export {
  ApiRouteError,
  createRequestContext,
  withRequestHeaders,
} from './api-error-core.ts';
export type {
  ApiErrorResponseOptions,
  ApiRequestContext,
} from './api-error-core.ts';

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
  cause?: unknown,
  options?: ApiErrorResponseOptions
) {
  logApiError(context, status, cause, options);

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
