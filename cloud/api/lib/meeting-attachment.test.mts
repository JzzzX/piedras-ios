import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';

import {
  buildMeetingAttachmentFileURL,
  deleteMeetingAttachmentFile,
  deleteMeetingAttachmentsDir,
  getMeetingAttachmentStorageConfig,
  hasMeetingAttachmentFile,
  partitionMeetingAttachmentsByFile,
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

test('getMeetingAttachmentStorageConfig marks production fallback storage as not persistent', () => {
  const storage = getMeetingAttachmentStorageConfig({
    env: {},
    cwd: '/srv/piedras',
    nodeEnv: 'production',
  });

  assert.equal(storage.rootPath, path.join('/srv/piedras', 'storage', 'meeting-attachments'));
  assert.equal(storage.configured, false);
  assert.equal(storage.persistent, false);
  assert.match(storage.message, /MEETING_ATTACHMENT_STORAGE_ROOT/);
});

test('partitionMeetingAttachmentsByFile keeps only attachments with stored files', async () => {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'piedras-meeting-attachment-partition-'));
  const originalRoot = process.env.MEETING_ATTACHMENT_STORAGE_ROOT;

  process.env.MEETING_ATTACHMENT_STORAGE_ROOT = tempRoot;

  try {
    await saveMeetingAttachmentFile('meeting-3', 'attachment-available', Buffer.from('available'));

    const result = await partitionMeetingAttachmentsByFile('meeting-3', [
      { id: 'attachment-available', originalName: 'available.jpg' },
      { id: 'attachment-missing', originalName: 'missing.jpg' },
    ]);

    assert.deepEqual(result.available, [
      { id: 'attachment-available', originalName: 'available.jpg' },
    ]);
    assert.deepEqual(result.missing, [
      { id: 'attachment-missing', originalName: 'missing.jpg' },
    ]);
  } finally {
    if (originalRoot === undefined) {
      delete process.env.MEETING_ATTACHMENT_STORAGE_ROOT;
    } else {
      process.env.MEETING_ATTACHMENT_STORAGE_ROOT = originalRoot;
    }
    await rm(tempRoot, { recursive: true, force: true });
  }
});
