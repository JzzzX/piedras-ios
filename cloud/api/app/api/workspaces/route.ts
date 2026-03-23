import { NextRequest } from 'next/server';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import { ensureDefaultWorkspace } from '@/lib/default-workspace';

export async function GET(req: NextRequest) {
  const context = createRequestContext(req, '/api/workspaces');

  try {
    let workspaces = await prisma.workspace.findMany({
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
    });

    if (workspaces.length === 0) {
      workspaces = [await ensureDefaultWorkspace()];
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

    const lastWorkspace = await prisma.workspace.findFirst({
      orderBy: { sortOrder: 'desc' },
      select: { sortOrder: true },
    });

    const workspace = await prisma.workspace.create({
      data: {
        name,
        description: body.description?.trim() || '',
        icon: body.icon?.trim() || 'folder',
        color: body.color?.trim() || '#94a3b8',
        workflowMode: body.workflowMode === 'interview' ? 'interview' : 'general',
        modeLabel: body.modeLabel?.trim() || '',
        sortOrder: (lastWorkspace?.sortOrder || 0) + 1,
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
