import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';

import {
  buildMeetingAttachmentFileURL,
  deleteMeetingAttachmentFile,
  deleteMeetingAttachmentsDir,
  hasMeetingAttachmentFile,
  saveMeetingAttachmentFile,
  saveMeetingAttachmentStream,
} from './meeting-attachment.ts';

test('saveMeetingAttachmentFile stores attachments under configured storage root', async () => {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'piedras-meeting-attachment-'));
  const originalRoot = process.env.MEETING_ATTACHMENT_STORAGE_ROOT;

  process.env.MEETING_ATTACHMENT_STORAGE_ROOT = tempRoot;

  try {
    const filePath = await saveMeetingAttachmentFile('meeting-1', 'attachment-1', Buffer.from('hello attachment'));

    assert.equal(filePath, path.join(tempRoot, 'meeting-1', 'attachment-1', 'attachment.bin'));
    assert.equal(await hasMeetingAttachmentFile('meeting-1', 'attachment-1'), true);
    assert.equal((await readFile(filePath, 'utf8')).toString(), 'hello attachment');
    assert.equal(
      buildMeetingAttachmentFileURL('meeting-1', 'attachment-1'),
      '/api/meetings/meeting-1/attachments/attachment-1'
    );

    await deleteMeetingAttachmentFile('meeting-1', 'attachment-1');
    assert.equal(await hasMeetingAttachmentFile('meeting-1', 'attachment-1'), false);
  } finally {
    if (originalRoot === undefined) {
      delete process.env.MEETING_ATTACHMENT_STORAGE_ROOT;
    } else {
      process.env.MEETING_ATTACHMENT_STORAGE_ROOT = originalRoot;
    }
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test('saveMeetingAttachmentStream writes attachment payloads from a stream', async () => {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'piedras-meeting-attachment-stream-'));
  const originalRoot = process.env.MEETING_ATTACHMENT_STORAGE_ROOT;

  process.env.MEETING_ATTACHMENT_STORAGE_ROOT = tempRoot;

  try {
    const filePath = await saveMeetingAttachmentStream(
      'meeting-2',
      'attachment-2',
      new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode('hello '));
          controller.enqueue(new TextEncoder().encode('stream'));
          controller.close();
        },
      })
    );

    assert.equal(filePath, path.join(tempRoot, 'meeting-2', 'attachment-2', 'attachment.bin'));
    assert.equal(await hasMeetingAttachmentFile('meeting-2', 'attachment-2'), true);
    assert.equal((await readFile(filePath, 'utf8')).toString(), 'hello stream');

    await deleteMeetingAttachmentsDir('meeting-2');
    assert.equal(await hasMeetingAttachmentFile('meeting-2', 'attachment-2'), false);
  } finally {
    if (originalRoot === undefined) {
      delete process.env.MEETING_ATTACHMENT_STORAGE_ROOT;
    } else {
      process.env.MEETING_ATTACHMENT_STORAGE_ROOT = originalRoot;
    }
    await rm(tempRoot, { recursive: true, force: true });
  }
});
