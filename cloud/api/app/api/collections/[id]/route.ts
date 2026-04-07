import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import { deleteMeetingAttachmentsDir } from '@/lib/meeting-attachment';
import { deleteMeetingAudioFile } from '@/lib/meeting-audio';
import { purgeExpiredTrashedMeetings } from '@/lib/meeting-trash';
import { runWithStartupBootstrapGuard } from '@/lib/startup-bootstrap-route';
import { deleteCollectionForWorkspace } from '@/lib/user-collection-db';

export async function DELETE(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/collections/[id]');
  return runWithStartupBootstrapGuard(context, async () => {
    const auth = await requireAuthenticatedRequest(req, context);

    if (auth instanceof Response) {
      return auth;
    }

    try {
      await purgeExpiredTrashedMeetings(prisma, {
        deleteMeetingAudio: deleteMeetingAudioFile,
        deleteMeetingAttachments: deleteMeetingAttachmentsDir,
      });

      const { id } = await params;
      const result = await deleteCollectionForWorkspace(prisma, {
        workspaceId: auth.workspace.id,
        collectionId: id,
      });

      return jsonResponse(context, result);
    } catch (error) {
      return errorResponse(
        context,
        500,
        error instanceof Error ? `删除文件夹失败：${error.message}` : '删除文件夹失败，请稍后重试。',
        error
      );
    }
  });
}
