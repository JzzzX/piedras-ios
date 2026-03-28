import type { NextRequest } from 'next/server';

import { errorResponse, type ApiRequestContext } from './api-error';
import { resolveSupabaseUserContext } from './auth-context';
import { hashSessionToken } from './auth';
import { prisma } from './db';
import { verifySupabaseAccessToken } from './supabase-auth';
import { ensureDefaultWorkspaceForUser } from './user-workspace-db';

const BEARER_PREFIX = 'Bearer ';
const INTERNAL_ADMIN_SECRET_HEADER = 'x-admin-secret';

export interface AuthenticatedRequestContext {
  user: {
    id: string;
    email: string;
    authUserId?: string | null;
  };
  session: {
    id: string;
    expiresAt: Date;
    provider: 'legacy' | 'supabase';
  };
  workspace: {
    id: string;
    name: string;
  };
}

function readBearerToken(req: NextRequest) {
  const authorization = req.headers.get('authorization')?.trim();
  if (!authorization?.startsWith(BEARER_PREFIX)) {
    return null;
  }

  const token = authorization.slice(BEARER_PREFIX.length).trim();
  return token || null;
}

export function requireInternalAdmin(
  req: NextRequest,
  context: ApiRequestContext
): true | Response {
  const expectedSecret = process.env.ADMIN_API_SECRET?.trim();
  const providedSecret = req.headers.get(INTERNAL_ADMIN_SECRET_HEADER)?.trim();

  if (!expectedSecret) {
    return errorResponse(context, 500, 'ADMIN_API_SECRET 未配置');
  }

  if (!providedSecret || providedSecret !== expectedSecret) {
    return errorResponse(context, 401, '内部接口鉴权失败');
  }

  return true;
}

export async function requireAuthenticatedRequest(
  req: NextRequest,
  context: ApiRequestContext
): Promise<AuthenticatedRequestContext | Response> {
  const token = readBearerToken(req);

  if (!token) {
    return errorResponse(context, 401, '请先登录');
  }

  if (looksLikeJWT(token)) {
    const supabaseIdentity = await verifySupabaseAccessToken(token);
    if (supabaseIdentity) {
      const supabaseContext = await resolveSupabaseUserContext(
        prisma,
        supabaseIdentity,
        (input) => ensureDefaultWorkspaceForUser(prisma, input)
      );

      return {
        user: {
          ...supabaseContext.user,
          authUserId: supabaseIdentity.authUserId,
        },
        session: {
          ...supabaseContext.session,
          provider: 'supabase',
        },
        workspace: supabaseContext.workspace,
      };
    }
  }

  return requireLegacyAuthenticatedRequest(token, context);
}

async function requireLegacyAuthenticatedRequest(
  token: string,
  context: ApiRequestContext
): Promise<AuthenticatedRequestContext | Response> {
  const tokenHash = hashSessionToken(token);
  const authSession = await prisma.authSession.findUnique({
    where: { tokenHash },
    include: {
      user: {
        select: {
          id: true,
          email: true,
        },
      },
    },
  });

  if (!authSession) {
    return errorResponse(context, 401, '登录态已失效，请重新登录');
  }

  if (authSession.expiresAt.getTime() <= Date.now()) {
    await prisma.authSession.deleteMany({
      where: { id: authSession.id },
    });
    return errorResponse(context, 401, '登录态已过期，请重新登录');
  }

  const workspace = await ensureDefaultWorkspaceForUser(prisma, {
    userId: authSession.user.id,
  });

  await prisma.authSession.update({
    where: { id: authSession.id },
    data: { lastUsedAt: new Date() },
  });

  return {
    user: authSession.user,
    session: {
      id: authSession.id,
      expiresAt: authSession.expiresAt,
      provider: 'legacy',
    },
    workspace: {
      id: workspace.id,
      name: workspace.name,
    },
  };
}

export async function revokeAuthenticatedSession(req: NextRequest) {
  const token = readBearerToken(req);
  if (!token) {
    return;
  }

  if (looksLikeJWT(token)) {
    return;
  }

  await prisma.authSession.deleteMany({
    where: { tokenHash: hashSessionToken(token) },
  });
}

function looksLikeJWT(token: string) {
  return token.split('.').length === 3;
}
