import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import {
  createCollectionForWorkspace,
  ensureWorkspaceCollectionsHydrated,
  serializeCollection,
} from '@/lib/user-collection-db';

export async function GET(req: NextRequest) {
  const context = createRequestContext(req, '/api/collections');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const { defaultCollection, collections } = await ensureWorkspaceCollectionsHydrated(prisma, {
      workspaceId: auth.workspace.id,
    });

    return jsonResponse(
      context,
      collections.map((collection) => serializeCollection(collection, defaultCollection.id))
    );
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `加载文件夹失败：${error.message}` : '加载文件夹失败，请稍后重试。',
      error
    );
  }
}

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/collections');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const body = (await req.json()) as {
      name?: string;
    };
    const name = body.name?.trim();

    if (!name) {
      return errorResponse(context, 400, '文件夹名称不能为空');
    }

    const { defaultCollection } = await ensureWorkspaceCollectionsHydrated(prisma, {
      workspaceId: auth.workspace.id,
    });
    const collection = await createCollectionForWorkspace(prisma, {
      workspaceId: auth.workspace.id,
      name,
    });

    return jsonResponse(context, serializeCollection(collection, defaultCollection.id));
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `创建文件夹失败：${error.message}` : '创建文件夹失败，请稍后重试。',
      error
    );
  }
}
