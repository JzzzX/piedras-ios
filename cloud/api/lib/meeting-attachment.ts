import { createReadStream, createWriteStream } from 'node:fs';
import { mkdir, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';

const ATTACHMENT_FILE_NAME = 'attachment.bin';
const STORAGE_ROOT_ENV_KEY = 'MEETING_ATTACHMENT_STORAGE_ROOT';
const DEFAULT_STORAGE_SEGMENTS = ['storage', 'meeting-attachments'] as const;

export interface MeetingAttachmentStorageConfig {
  rootPath: string;
  configured: boolean;
  persistent: boolean;
  message: string;
}

interface MeetingAttachmentStorageConfigOptions {
  env?: NodeJS.ProcessEnv;
  cwd?: string;
  nodeEnv?: string;
}

export function resolveMeetingAttachmentStorageRoot(
  options: Pick<MeetingAttachmentStorageConfigOptions, 'env' | 'cwd'> = {}
) {
  const env = options.env ?? process.env;
  const cwd = options.cwd ?? process.cwd();
  const configuredRoot = env[STORAGE_ROOT_ENV_KEY]?.trim();

  if (configuredRoot) {
    return path.isAbsolute(configuredRoot)
      ? configuredRoot
      : path.resolve(cwd, configuredRoot);
  }

  return path.join(cwd, ...DEFAULT_STORAGE_SEGMENTS);
}

export function getMeetingAttachmentStorageConfig(
  options: MeetingAttachmentStorageConfigOptions = {}
): MeetingAttachmentStorageConfig {
  const env = options.env ?? process.env;
  const nodeEnv = options.nodeEnv ?? env.NODE_ENV ?? 'development';
  const configuredRoot = env[STORAGE_ROOT_ENV_KEY]?.trim();
  const rootPath = resolveMeetingAttachmentStorageRoot(options);

  if (configuredRoot) {
    return {
      rootPath,
      configured: true,
      persistent: true,
      message: `资料区附件使用持久化目录：${rootPath}`,
    };
  }

  if (nodeEnv === 'production') {
    return {
      rootPath,
      configured: false,
      persistent: false,
      message: `${STORAGE_ROOT_ENV_KEY} 未配置，生产环境重启后资料区附件可能丢失`,
    };
  }

  return {
    rootPath,
    configured: true,
    persistent: false,
    message: `未配置 ${STORAGE_ROOT_ENV_KEY}，当前使用本地目录：${rootPath}`,
  };
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

export async function partitionMeetingAttachmentsByFile<T extends { id: string }>(
  meetingId: string,
  attachments: readonly T[]
) {
  const availability = await Promise.all(
    attachments.map(async (attachment) => ({
      attachment,
      exists: await hasMeetingAttachmentFile(meetingId, attachment.id),
    }))
  );

  return availability.reduce(
    (result, entry) => {
      if (entry.exists) {
        result.available.push(entry.attachment);
      } else {
        result.missing.push(entry.attachment);
      }

      return result;
    },
    { available: [] as T[], missing: [] as T[] }
  );
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
