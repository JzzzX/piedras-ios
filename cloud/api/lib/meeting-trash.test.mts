import assert from 'node:assert/strict';
import test from 'node:test';

import { purgeExpiredTrashedMeetings } from './meeting-trash.ts';

test('purgeExpiredTrashedMeetings deletes only notes trashed longer than retention and cleans storage', async () => {
  const deletedMeetingIds: string[] = [];
  const deletedAudioIds: string[] = [];
  const deletedAttachmentIds: string[] = [];

  const fakeDb = {
    meeting: {
      findMany: async ({ where }: any) => {
        assert.equal(where.deletedAt.lt instanceof Date, true);
        return [
          { id: 'meeting-expired-1' },
          { id: 'meeting-expired-2' },
        ];
      },
      delete: async ({ where }: any) => {
        deletedMeetingIds.push(where.id);
        return { id: where.id };
      },
    },
  };

  const result = await purgeExpiredTrashedMeetings(fakeDb as any, {
    now: new Date('2026-04-08T00:00:00.000Z'),
    retentionDays: 7,
    deleteMeetingAudio: async (meetingId) => {
      deletedAudioIds.push(meetingId);
    },
    deleteMeetingAttachments: async (meetingId) => {
      deletedAttachmentIds.push(meetingId);
    },
  });

  assert.deepEqual(result, {
    deletedMeetingCount: 2,
  });
  assert.deepEqual(deletedMeetingIds, ['meeting-expired-1', 'meeting-expired-2']);
  assert.deepEqual(deletedAudioIds, ['meeting-expired-1', 'meeting-expired-2']);
  assert.deepEqual(deletedAttachmentIds, ['meeting-expired-1', 'meeting-expired-2']);
});

