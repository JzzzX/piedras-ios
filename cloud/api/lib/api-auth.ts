import type { NextRequest } from 'next/server';

import { errorResponse, type ApiRequestContext } from './api-error';
import { hashSessionToken } from './auth';
import { prisma } from './db';
import { ensureDefaultWorkspaceForUser } from './user-workspace-db';

const BEARER_PREFIX = 'Bearer ';
const INTERNAL_ADMIN_SECRET_HEADER = 'x-admin-secret';

export interface AuthenticatedRequestContext {
  user: {
    id: string;
    email: string;
  };
  session: {
    id: string;
    expiresAt: Date;
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

  await prisma.authSession.deleteMany({
    where: { tokenHash: hashSessionToken(token) },
  });
}
