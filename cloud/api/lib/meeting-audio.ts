import { createReadStream } from 'node:fs';
import { mkdir, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';

const STORAGE_ROOT = path.join(process.cwd(), 'storage', 'meetings');
const AUDIO_FILE_NAME = 'audio.bin';

function getMeetingAudioDir(meetingId: string) {
  return path.join(STORAGE_ROOT, meetingId);
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
