import crypto from 'node:crypto';
import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';

export interface FinalizedTranscriptSegment {
  speaker: string;
  text: string;
  startTime: number;
  endTime: number;
  isFinal: boolean;
  order: number;
}

export interface FinalizedTranscript {
  speakers: Record<string, string>;
  segments: FinalizedTranscriptSegment[];
}

interface DiarizedUtterance {
  text?: string;
  utterance?: string;
  start_time?: number;
  startTime?: number;
  end_time?: number;
  endTime?: number;
  additions?: {
    speaker?: string | number | null;
  } | null;
  speaker?: string | number | null;
}

interface DiarizedPayload {
  result?: {
    text?: string;
    utterances?: DiarizedUtterance[];
  };
}

const execFileAsync = promisify(execFile);
const VOLCENGINE_FLASH_RECOGNIZE_URL =
  process.env.VOLCENGINE_FILE_ASR_URL?.trim() ||
  'https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash';
const VOLCENGINE_FILE_RESOURCE_ID =
  process.env.VOLCENGINE_FILE_ASR_RESOURCE_ID?.trim() || 'volc.bigasr.auc_turbo';
const VOLCENGINE_FILE_APP_ID =
  process.env.VOLCENGINE_FILE_ASR_APP_ID?.trim() || process.env.DOUBAO_ASR_APP_ID?.trim() || '';
const VOLCENGINE_FILE_ACCESS_TOKEN =
  process.env.VOLCENGINE_FILE_ASR_ACCESS_TOKEN?.trim() || process.env.DOUBAO_ASR_ACCESS_TOKEN?.trim() || '';
const VOLCENGINE_FILE_SSD_VERSION = process.env.VOLCENGINE_FILE_ASR_SSD_VERSION?.trim() || '200';
const EMPTY_TRANSCRIPT_FAILURE_MARKERS = [
  '离线转写未返回可用内容',
  'normal silence audio',
  'no valid speech in audio',
];

export function normalizeDiarizedTranscript(payload: DiarizedPayload): FinalizedTranscript {
  const utterances = payload.result?.utterances ?? [];
  const speakerKeys = new Map<string, string>();
  const speakers: Record<string, string> = {};
  const segments: FinalizedTranscriptSegment[] = [];

  const keyForProviderSpeaker = (providerSpeaker: string) => {
    const normalized = providerSpeaker.trim() || 'unknown';
    const existing = speakerKeys.get(normalized);
    if (existing) return existing;

    const nextKey = `spk_${speakerKeys.size + 1}`;
    speakerKeys.set(normalized, nextKey);
    speakers[nextKey] = `说话人 ${speakerKeys.size}`;
    return nextKey;
  };

  utterances.forEach((utterance, index) => {
    const text = (utterance.text ?? utterance.utterance ?? '').trim();
    if (!text) return;

    const providerSpeaker = String(utterance.additions?.speaker ?? utterance.speaker ?? 'unknown');
    const speakerKey = keyForProviderSpeaker(providerSpeaker);
    const startTime = Number(utterance.start_time ?? utterance.startTime ?? 0);
    const endTime = Math.max(Number(utterance.end_time ?? utterance.endTime ?? startTime), startTime);

    segments.push({
      speaker: speakerKey,
      text,
      startTime,
      endTime,
      isFinal: true,
      order: index,
    });
  });

  if (segments.length === 0) {
    const fallbackText = payload.result?.text?.trim() ?? '';
    if (fallbackText) {
      speakers.spk_1 = '说话人 1';
      segments.push({
        speaker: 'spk_1',
        text: fallbackText,
        startTime: 0,
        endTime: 0,
        isFinal: true,
        order: 0,
      });
    }
  }

  return { speakers, segments };
}

export async function finalizeMeetingTranscriptFromAudio(params: {
  audioPath: string;
  mimeType?: string | null;
  requestId?: string;
  userId?: string;
}): Promise<FinalizedTranscript> {
  ensureVolcengineFileAsrConfigured();

  const preparedAudio = await transcodeAudioForDiarization(params.audioPath);
  try {
    const audioBase64 = (await readFile(preparedAudio.outputPath)).toString('base64');
    const response = await fetch(VOLCENGINE_FLASH_RECOGNIZE_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Api-App-Key': VOLCENGINE_FILE_APP_ID,
        'X-Api-Access-Key': VOLCENGINE_FILE_ACCESS_TOKEN,
        'X-Api-Resource-Id': VOLCENGINE_FILE_RESOURCE_ID,
        'X-Api-Request-Id': params.requestId ?? crypto.randomUUID(),
        'X-Api-Sequence': '-1',
      },
      body: JSON.stringify({
        user: {
          uid: params.userId ?? 'coco-interview-cloud-api',
        },
        audio: {
          format: 'mp3',
          data: audioBase64,
        },
        request: {
          model_name: 'bigmodel',
          enable_itn: true,
          enable_punc: true,
          show_utterances: true,
          enable_speaker_info: true,
          ssd_version: VOLCENGINE_FILE_SSD_VERSION,
        },
      }),
    });

    const statusCode = response.headers.get('X-Api-Status-Code') || '';
    const payload = (await response.json().catch(() => ({}))) as DiarizedPayload & {
      error?: string;
      message?: string;
    };

    if (!response.ok || (statusCode && statusCode !== '20000000')) {
      const detail =
        payload.error ||
        payload.message ||
        response.headers.get('X-Api-Message') ||
        `HTTP ${response.status}`;
      throw new Error(`离线转写失败：${detail}`);
    }

    const normalized = normalizeDiarizedTranscript(payload);
    if (normalized.segments.length === 0) {
      throw new Error('离线转写未返回可用内容。');
    }

    return normalized;
  } finally {
    await preparedAudio.cleanup();
  }
}

export function isEmptyTranscriptFinalizationFailure(error: unknown): boolean {
  let message = '';

  if (typeof error === 'string') {
    message = error;
  } else if (error instanceof Error) {
    message = error.message;
  }

  const normalized = message.trim().toLowerCase();
  if (!normalized) {
    return false;
  }

  return EMPTY_TRANSCRIPT_FAILURE_MARKERS.some((marker) => normalized.includes(marker.toLowerCase()));
}

function ensureVolcengineFileAsrConfigured() {
  const missing: string[] = [];
  if (!VOLCENGINE_FILE_APP_ID) {
    missing.push('VOLCENGINE_FILE_ASR_APP_ID or DOUBAO_ASR_APP_ID');
  }
  if (!VOLCENGINE_FILE_ACCESS_TOKEN) {
    missing.push('VOLCENGINE_FILE_ASR_ACCESS_TOKEN or DOUBAO_ASR_ACCESS_TOKEN');
  }

  if (missing.length > 0) {
    throw new Error(`离线说话人分离配置缺失：${missing.join(', ')}`);
  }
}

async function transcodeAudioForDiarization(inputPath: string) {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), 'coco-interview-diarization-'));
  const outputPath = path.join(tempDir, 'meeting-upload.mp3');

  try {
    await execFileAsync('ffmpeg', [
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-c:a',
      'libmp3lame',
      '-b:a',
      '64k',
      outputPath,
    ]);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`音频转码失败：${detail}`);
  }

  return {
    outputPath,
    cleanup: async () => {
      await rm(tempDir, { recursive: true, force: true });
    },
  };
}
