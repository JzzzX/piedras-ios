import { mkdir } from 'node:fs/promises';

import {
  getMeetingAttachmentStorageConfig,
  type MeetingAttachmentStorageConfig,
} from './meeting-attachment.ts';
import { getCachedRuntimeHealth, toErrorMessage } from './runtime-health.ts';

export interface MeetingAttachmentRuntimeStatus {
  configured: boolean;
  ready: boolean;
  storageReady: boolean;
  storagePersistent: boolean;
  storagePath: string;
  checkedAt: string | null;
  lastError: string | null;
  message: string;
}

interface MeetingAttachmentRuntimeStatusInput {
  storage: MeetingAttachmentStorageConfig;
  storageWriteOK: boolean;
  storageError: string | null;
  checkedAt: string | null;
}

export function buildMeetingAttachmentRuntimeStatus(
  input: MeetingAttachmentRuntimeStatusInput
): MeetingAttachmentRuntimeStatus {
  const storageReady = input.storage.configured && input.storageWriteOK;
  const ready = storageReady;

  let lastError: string | null = null;
  let message = '资料区附件存储就绪';

  if (!input.storage.configured) {
    lastError = input.storage.message;
    message = input.storage.message;
  } else if (!input.storageWriteOK) {
    lastError = input.storageError ?? '资料区附件目录不可写';
    message = `资料区附件目录不可用：${lastError}`;
  } else if (input.storage.persistent) {
    message = `资料区附件存储就绪（持久化目录：${input.storage.rootPath}）`;
  } else {
    message = `资料区附件存储就绪（本地目录：${input.storage.rootPath}）`;
  }

  return {
    configured: input.storage.configured,
    ready,
    storageReady,
    storagePersistent: input.storage.persistent,
    storagePath: input.storage.rootPath,
    checkedAt: input.checkedAt,
    lastError,
    message,
  };
}

export async function getMeetingAttachmentRuntimeStatus(): Promise<MeetingAttachmentRuntimeStatus> {
  const storage = getMeetingAttachmentStorageConfig();
  const cacheKey = `meeting-attachments:${process.env.NODE_ENV || 'development'}:${storage.rootPath}:${storage.configured}`;

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

    return buildMeetingAttachmentRuntimeStatus({
      storage,
      storageWriteOK,
      storageError,
      checkedAt,
    });
  });
}
