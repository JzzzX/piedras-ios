import type { Prisma, PrismaClient } from '@prisma/client';

type MeetingTrashDatabase = PrismaClient | Prisma.TransactionClient;

interface PurgeExpiredTrashedMeetingsOptions {
  now?: Date;
  retentionDays?: number;
  deleteMeetingAudio: (meetingId: string) => Promise<void>;
  deleteMeetingAttachments: (meetingId: string) => Promise<void>;
}

export async function purgeExpiredTrashedMeetings(
  db: MeetingTrashDatabase,
  options: PurgeExpiredTrashedMeetingsOptions
): Promise<{ deletedMeetingCount: number }> {
  const now = options.now ?? new Date();
  const retentionDays = options.retentionDays ?? 7;
  const cutoff = new Date(now.getTime() - retentionDays * 24 * 60 * 60 * 1000);

  const expiredMeetings = await db.meeting.findMany({
    where: {
      deletedAt: {
        lt: cutoff,
      },
    },
    select: {
      id: true,
    },
  });

  for (const meeting of expiredMeetings) {
    await options.deleteMeetingAudio(meeting.id);
    await options.deleteMeetingAttachments(meeting.id);
    await db.meeting.delete({
      where: { id: meeting.id },
    });
  }

  return {
    deletedMeetingCount: expiredMeetings.length,
  };
}
