import { execFile } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { promisify } from 'node:util';

import { getMeetingAudioStorageConfig, type MeetingAudioStorageConfig } from './meeting-audio.ts';
import { getCachedRuntimeHealth, toErrorMessage } from './runtime-health.ts';

const execFileAsync = promisify(execFile);

export interface AudioFinalizationRuntimeStatus {
  configured: boolean;
  ready: boolean;
  ffmpegAvailable: boolean;
  storageReady: boolean;
  storagePersistent: boolean;
  storagePath: string;
  checkedAt: string | null;
  lastError: string | null;
  message: string;
}

interface AudioFinalizationRuntimeStatusInput {
  storage: MeetingAudioStorageConfig;
  storageWriteOK: boolean;
  storageError: string | null;
  ffmpegAvailable: boolean;
  ffmpegMessage: string | null;
  checkedAt: string | null;
}

export function buildAudioFinalizationRuntimeStatus(
  input: AudioFinalizationRuntimeStatusInput
): AudioFinalizationRuntimeStatus {
  const storageReady = input.storage.configured && input.storageWriteOK;
  const ready = storageReady && input.ffmpegAvailable;

  let lastError: string | null = null;
  let message = '音频补转写就绪';

  if (!input.storage.configured) {
    lastError = input.storage.message;
    message = input.storage.message;
  } else if (!input.storageWriteOK) {
    lastError = input.storageError ?? '会议音频目录不可写';
    message = `会议音频目录不可用：${lastError}`;
  } else if (!input.ffmpegAvailable) {
    lastError = input.ffmpegMessage ?? 'ffmpeg 不可用';
    message = `音频补转写不可用：${lastError}`;
  } else if (input.storage.persistent) {
    message = `音频补转写就绪（持久化目录：${input.storage.rootPath}）`;
  } else {
    message = `音频补转写就绪（本地目录：${input.storage.rootPath}）`;
  }

  return {
    configured: input.storage.configured,
    ready,
    ffmpegAvailable: input.ffmpegAvailable,
    storageReady,
    storagePersistent: input.storage.persistent,
    storagePath: input.storage.rootPath,
    checkedAt: input.checkedAt,
    lastError,
    message,
  };
}

export async function getAudioFinalizationRuntimeStatus(): Promise<AudioFinalizationRuntimeStatus> {
  const storage = getMeetingAudioStorageConfig();
  const cacheKey = `audio-finalization:${process.env.NODE_ENV || 'development'}:${storage.rootPath}:${storage.configured}`;

  return getCachedRuntimeHealth(cacheKey, 30_000, async () => {
    const checkedAt = new Date().toISOString();

    let storageWriteOK = false;
    let storageError: string | null = null;
    try {
      await mkdir(storage.rootPath, { recursive: true });
      storageWriteOK = true;
    } catch (error) {
      storageError = toErrorMessage(error);
    }

    let ffmpegAvailable = false;
    let ffmpegMessage: string | null = null;
    try {
      await execFileAsync('ffmpeg', ['-version'], {
        timeout: 3_000,
      });
      ffmpegAvailable = true;
    } catch (error) {
      ffmpegMessage = toErrorMessage(error);
    }

    return buildAudioFinalizationRuntimeStatus({
      storage,
      storageWriteOK,
      storageError,
      ffmpegAvailable,
      ffmpegMessage,
      checkedAt,
    });
  });
}
