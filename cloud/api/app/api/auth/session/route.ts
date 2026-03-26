import { NextRequest } from 'next/server';

import { createRequestContext, jsonResponse } from '@/lib/api-error';
import { requireAuthenticatedRequest } from '@/lib/api-auth';

export async function GET(req: NextRequest) {
  const context = createRequestContext(req, '/api/auth/session');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  return jsonResponse(context, {
    user: auth.user,
    workspace: auth.workspace,
    session: {
      expiresAt: auth.session.expiresAt,
    },
  });
}
