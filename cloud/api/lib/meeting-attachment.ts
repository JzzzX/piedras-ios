import { createReadStream, createWriteStream } from 'node:fs';
import { mkdir, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';

const ATTACHMENT_FILE_NAME = 'attachment.bin';
const STORAGE_ROOT_ENV_KEY = 'MEETING_ATTACHMENT_STORAGE_ROOT';
const DEFAULT_STORAGE_SEGMENTS = ['storage', 'meeting-attachments'] as const;

export function resolveMeetingAttachmentStorageRoot() {
  const configuredRoot = process.env[STORAGE_ROOT_ENV_KEY]?.trim();
  const cwd = process.cwd();

  if (configuredRoot) {
    return path.isAbsolute(configuredRoot)
      ? configuredRoot
      : path.resolve(cwd, configuredRoot);
  }

  return path.join(cwd, ...DEFAULT_STORAGE_SEGMENTS);
}

function getMeetingAttachmentDir(meetingId: string, attachmentId: string) {
  return path.join(resolveMeetingAttachmentStorageRoot(), meetingId, attachmentId);
}

export function getMeetingAttachmentPath(meetingId: string, attachmentId: string) {
  return path.join(getMeetingAttachmentDir(meetingId, attachmentId), ATTACHMENT_FILE_NAME);
}

export function buildMeetingAttachmentFileURL(meetingId: string, attachmentId: string) {
  return `/api/meetings/${meetingId}/attachments/${attachmentId}`;
}

export async function saveMeetingAttachmentFile(
  meetingId: string,
  attachmentId: string,
  buffer: Buffer
) {
  const dir = getMeetingAttachmentDir(meetingId, attachmentId);
  await mkdir(dir, { recursive: true });
  const filePath = getMeetingAttachmentPath(meetingId, attachmentId);
  await writeFile(filePath, buffer);
  return filePath;
}

export async function saveMeetingAttachmentStream(
  meetingId: string,
  attachmentId: string,
  stream: Readable | ReadableStream<Uint8Array>
) {
  const dir = getMeetingAttachmentDir(meetingId, attachmentId);
  await mkdir(dir, { recursive: true });
  const filePath = getMeetingAttachmentPath(meetingId, attachmentId);
  const source = stream instanceof Readable ? stream : Readable.fromWeb(stream as any);

  await pipeline(source, createWriteStream(filePath));
  return filePath;
}

export async function hasMeetingAttachmentFile(meetingId: string, attachmentId: string) {
  try {
    await stat(getMeetingAttachmentPath(meetingId, attachmentId));
    return true;
  } catch {
    return false;
  }
}

export async function deleteMeetingAttachmentFile(meetingId: string, attachmentId: string) {
  await rm(getMeetingAttachmentDir(meetingId, attachmentId), { recursive: true, force: true });
}

export async function deleteMeetingAttachmentsDir(meetingId: string) {
  await rm(path.join(resolveMeetingAttachmentStorageRoot(), meetingId), {
    recursive: true,
    force: true,
  });
}

export async function buildMeetingAttachmentResponse(
  meetingId: string,
  attachmentId: string,
  mimeType: string,
  originalName: string
) {
  const filePath = getMeetingAttachmentPath(meetingId, attachmentId);
  const fileStat = await stat(filePath);
  const stream = Readable.toWeb(createReadStream(filePath)) as ReadableStream<Uint8Array>;

  return new Response(stream, {
    status: 200,
    headers: {
      'Content-Type': mimeType,
      'Content-Length': String(fileStat.size),
      'Cache-Control': 'no-store',
      'Content-Disposition': `inline; filename*=UTF-8''${encodeURIComponent(originalName)}`,
    },
  });
}
