import { NextRequest } from 'next/server';

import { createRequestContext, jsonResponse } from '@/lib/api-error';
import { revokeAuthenticatedSession } from '@/lib/api-auth';

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/auth/logout');

  await revokeAuthenticatedSession(req);

  return jsonResponse(context, { success: true });
}
