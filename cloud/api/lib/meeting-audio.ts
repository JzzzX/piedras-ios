import { createReadStream } from 'node:fs';
import { mkdir, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';

const AUDIO_FILE_NAME = 'audio.bin';
const STORAGE_ROOT_ENV_KEY = 'MEETING_AUDIO_STORAGE_ROOT';
const DEFAULT_STORAGE_SEGMENTS = ['storage', 'meetings'] as const;

export interface MeetingAudioStorageConfig {
  rootPath: string;
  configured: boolean;
  persistent: boolean;
  message: string;
}

interface MeetingAudioStorageConfigOptions {
  env?: NodeJS.ProcessEnv;
  cwd?: string;
  nodeEnv?: string;
}

export function resolveMeetingAudioStorageRoot(
  options: Pick<MeetingAudioStorageConfigOptions, 'env' | 'cwd'> = {}
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

export function getMeetingAudioStorageConfig(
  options: MeetingAudioStorageConfigOptions = {}
): MeetingAudioStorageConfig {
  const env = options.env ?? process.env;
  const nodeEnv = options.nodeEnv ?? env.NODE_ENV ?? 'development';
  const configuredRoot = env[STORAGE_ROOT_ENV_KEY]?.trim();
  const rootPath = resolveMeetingAudioStorageRoot(options);

  if (configuredRoot) {
    return {
      rootPath,
      configured: true,
      persistent: true,
      message: `会议音频使用持久化目录：${rootPath}`,
    };
  }

  if (nodeEnv === 'production') {
    return {
      rootPath,
      configured: false,
      persistent: false,
      message: `${STORAGE_ROOT_ENV_KEY} 未配置，生产环境重启后会议音频可能丢失`,
    };
  }

  return {
    rootPath,
    configured: true,
    persistent: false,
    message: `未配置 ${STORAGE_ROOT_ENV_KEY}，当前使用本地目录：${rootPath}`,
  };
}

function getMeetingAudioDir(meetingId: string) {
  return path.join(resolveMeetingAudioStorageRoot(), meetingId);
}

export function getMeetingAudioPath(meetingId: string) {
  return path.join(getMeetingAudioDir(meetingId), AUDIO_FILE_NAME);
}

export async function saveMeetingAudioFile(meetingId: string, buffer: Buffer) {
  const dir = getMeetingAudioDir(meetingId);
  await mkdir(dir, { recursive: true });
  const filePath = getMeetingAudioPath(meetingId);
  await writeFile(filePath, buffer);
  return filePath;
}

export async function deleteMeetingAudioFile(meetingId: string) {
  await rm(getMeetingAudioDir(meetingId), { recursive: true, force: true });
}

export async function hasMeetingAudioFile(meetingId: string) {
  try {
    await stat(getMeetingAudioPath(meetingId));
    return true;
  } catch {
    return false;
  }
}

export async function buildMeetingAudioResponse(
  meetingId: string,
  mimeType: string,
  rangeHeader: string | null
) {
  const filePath = getMeetingAudioPath(meetingId);
  const fileStat = await stat(filePath);
  const totalSize = fileStat.size;

  if (!rangeHeader) {
    const stream = Readable.toWeb(createReadStream(filePath)) as ReadableStream<Uint8Array>;
    return new Response(stream, {
      status: 200,
      headers: {
        'Content-Type': mimeType,
        'Content-Length': String(totalSize),
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-store',
      },
    });
  }

  const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader);
  if (!match) {
    return new Response('Invalid Range', { status: 416 });
  }

  const start = match[1] ? Number.parseInt(match[1], 10) : 0;
  const end = match[2] ? Number.parseInt(match[2], 10) : totalSize - 1;

  if (Number.isNaN(start) || Number.isNaN(end) || start > end || end >= totalSize) {
    return new Response('Invalid Range', {
      status: 416,
      headers: {
        'Content-Range': `bytes */${totalSize}`,
      },
    });
  }

  const stream = Readable.toWeb(createReadStream(filePath, { start, end })) as ReadableStream<Uint8Array>;
  return new Response(stream, {
    status: 206,
    headers: {
      'Content-Type': mimeType,
      'Content-Length': String(end - start + 1),
      'Content-Range': `bytes ${start}-${end}/${totalSize}`,
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'no-store',
    },
  });
}
