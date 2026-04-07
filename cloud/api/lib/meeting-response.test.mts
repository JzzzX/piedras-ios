import assert from 'node:assert/strict';
import test from 'node:test';

import { serializeMeetingDetail } from './meeting-response.ts';

test('serializeMeetingDetail includes cloud audio state and note attachments metadata', () => {
  const createdAt = new Date('2026-04-01T08:00:00.000Z');
  const updatedAt = new Date('2026-04-01T09:00:00.000Z');
  const payload = serializeMeetingDetail(
    {
      id: 'meeting-1',
      collectionId: 'collection-notes',
      previousCollectionId: 'collection-archive',
      deletedAt: new Date('2026-04-03T10:00:00.000Z'),
      speakers: '{"spk_1":"主持人"}',
      audioEnhancedNotes: 'legacy experimental summary',
      audioEnhancedNotesStatus: 'ready',
      audioEnhancedNotesError: '',
      audioEnhancedNotesUpdatedAt: updatedAt,
      audioEnhancedNotesProvider: 'demo',
      audioEnhancedNotesModel: 'gemini-3-flash-preview',
      audioUpdatedAt: updatedAt,
      audioProcessingState: 'idle',
      audioProcessingError: '',
      audioProcessingAttempts: 0,
      audioProcessingRequestedAt: null,
      audioProcessingStartedAt: null,
      audioProcessingCompletedAt: null,
      audioCloudSyncEnabled: false,
      noteAttachments: [
        {
          id: 'attachment-1',
          mimeType: 'image/jpeg',
          originalName: 'whiteboard.jpg',
          extractedText: '白板重点',
          createdAt,
          updatedAt,
        },
      ],
    },
    { hasAudio: false }
  );

  assert.equal(payload.audioCloudSyncEnabled, false);
  assert.equal(payload.collectionId, 'collection-notes');
  assert.equal(payload.previousCollectionId, 'collection-archive');
  assert.equal(payload.deletedAt?.toISOString(), '2026-04-03T10:00:00.000Z');
  assert.equal(payload.hasAudio, false);
  assert.equal(payload.audioUrl, null);
  assert.equal(payload.noteAttachmentsTextContext, '白板重点');
  assert.equal('audioEnhancedNotes' in payload, false);
  assert.equal('audioEnhancedNotesStatus' in payload, false);
  assert.equal('audioEnhancedNotesError' in payload, false);
  assert.equal('audioEnhancedNotesUpdatedAt' in payload, false);
  assert.equal('audioEnhancedNotesProvider' in payload, false);
  assert.equal('audioEnhancedNotesModel' in payload, false);
  assert.deepEqual(payload.noteAttachments, [
    {
        id: 'attachment-1',
        mimeType: 'image/jpeg',
        originalName: 'whiteboard.jpg',
        extractedText: '白板重点',
        createdAt: createdAt,
        updatedAt: updatedAt,
        url: '/api/meetings/meeting-1/attachments/attachment-1',
      },
  ]);
});
