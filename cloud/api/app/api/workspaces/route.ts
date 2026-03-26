import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import { ensureDefaultWorkspaceForUser } from '@/lib/user-workspace-db';

export async function GET(req: NextRequest) {
  const context = createRequestContext(req, '/api/workspaces');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    let workspaces = await prisma.workspace.findMany({
      where: { ownerUserId: auth.user.id },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
    });

    if (workspaces.length === 0) {
      workspaces = [await ensureDefaultWorkspaceForUser(prisma, { userId: auth.user.id })];
    }

    return jsonResponse(context, workspaces);
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `加载工作区失败：${error.message}` : '加载工作区失败，请稍后重试。',
      error
    );
  }
}

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/workspaces');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const body = (await req.json()) as {
      name?: string;
      description?: string;
      icon?: string;
      color?: string;
      workflowMode?: 'general' | 'interview';
      modeLabel?: string;
    };
    const name = body.name?.trim();

    if (!name) {
      return errorResponse(context, 400, '工作区名称不能为空');
    }

    const existingWorkspace = await prisma.workspace.findFirst({
      where: { ownerUserId: auth.user.id },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
    });

    if (existingWorkspace) {
      return errorResponse(context, 409, '当前账号已存在默认工作区');
    }

    const workspace = await prisma.workspace.create({
      data: {
        name,
        description: body.description?.trim() || '',
        icon: body.icon?.trim() || 'folder',
        color: body.color?.trim() || '#94a3b8',
        workflowMode: body.workflowMode === 'interview' ? 'interview' : 'general',
        modeLabel: body.modeLabel?.trim() || '',
        sortOrder: 1,
        ownerUserId: auth.user.id,
      },
    });

    return jsonResponse(context, workspace);
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `创建工作区失败：${error.message}` : '创建工作区失败，请稍后重试。',
      error
    );
  }
}
