#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';

const targetSampleRate = 16000;
const defaultChunkDurationMS = 100;
const defaultBackendBaseURL = process.env.COCO_INTERVIEW_BACKEND_URL ?? 'https://api.coco-interview.example.com';
const defaultBearerToken = process.env.COCO_INTERVIEW_BEARER_TOKEN ?? process.env.COCO_INTERVIEW_AUTH_TOKEN ?? '';

const [, , inputFilePath, backendBaseURL = defaultBackendBaseURL, bearerToken = defaultBearerToken] = process.argv;

if (!inputFilePath || !bearerToken) {
  console.error('Usage: node scripts/asr_smoke_test.mjs <wav-file> [backend-base-url] [bearer-token]');
  console.error('Or set COCO_INTERVIEW_BEARER_TOKEN in the environment.');
  process.exit(1);
}

function clampPCM(sample) {
  const clamped = Math.max(-1, Math.min(1, sample));
  return clamped < 0 ? Math.round(clamped * 0x8000) : Math.round(clamped * 0x7fff);
}

function parseWavFile(buffer) {
  if (buffer.toString('ascii', 0, 4) !== 'RIFF' || buffer.toString('ascii', 8, 12) !== 'WAVE') {
    throw new Error('Only RIFF/WAVE files are supported.');
  }

  let offset = 12;
  let formatCode = 0;
  let channels = 0;
  let sampleRate = 0;
  let bitsPerSample = 0;
  let dataStart = -1;
  let dataSize = 0;

  while (offset + 8 <= buffer.length) {
    const chunkID = buffer.toString('ascii', offset, offset + 4);
    const chunkSize = buffer.readUInt32LE(offset + 4);
    const chunkStart = offset + 8;

    if (chunkID === 'fmt ') {
      formatCode = buffer.readUInt16LE(chunkStart);
      channels = buffer.readUInt16LE(chunkStart + 2);
      sampleRate = buffer.readUInt32LE(chunkStart + 4);
      bitsPerSample = buffer.readUInt16LE(chunkStart + 14);
    } else if (chunkID === 'data') {
      dataStart = chunkStart;
      dataSize = chunkSize;
    }

    offset = chunkStart + chunkSize + (chunkSize % 2);
  }

  if (formatCode !== 1) {
    throw new Error(`Unsupported WAV format code: ${formatCode}. Expected PCM.`);
  }

  if (bitsPerSample !== 16) {
    throw new Error(`Unsupported WAV bit depth: ${bitsPerSample}. Expected 16-bit PCM.`);
  }

  if (channels < 1 || sampleRate < 1 || dataStart < 0 || dataSize < 2) {
    throw new Error('Incomplete WAV metadata.');
  }

  const pcmBytes = buffer.subarray(dataStart, dataStart + dataSize);
  const pcm = new Int16Array(pcmBytes.buffer, pcmBytes.byteOffset, Math.floor(pcmBytes.byteLength / 2));

  return {
    channels,
    sampleRate,
    pcm,
  };
}

function mixToMonoAndResample(sourcePCM, channels, sourceSampleRate, destinationSampleRate) {
  const frameCount = Math.floor(sourcePCM.length / channels);
  const mono = new Float32Array(frameCount);

  for (let frameIndex = 0; frameIndex < frameCount; frameIndex += 1) {
    let sum = 0;
    for (let channelIndex = 0; channelIndex < channels; channelIndex += 1) {
      const sample = sourcePCM[frameIndex * channels + channelIndex] / 0x8000;
      sum += sample;
    }
    mono[frameIndex] = sum / channels;
  }

  if (sourceSampleRate === destinationSampleRate) {
    return Int16Array.from(mono, clampPCM);
  }

  const ratio = sourceSampleRate / destinationSampleRate;
  const destinationFrameCount = Math.max(1, Math.round(frameCount / ratio));
  const resampled = new Int16Array(destinationFrameCount);

  for (let frameIndex = 0; frameIndex < destinationFrameCount; frameIndex += 1) {
    const sourceIndex = frameIndex * ratio;
    const leftIndex = Math.floor(sourceIndex);
    const rightIndex = Math.min(leftIndex + 1, frameCount - 1);
    const weight = sourceIndex - leftIndex;
    const interpolated = mono[leftIndex] * (1 - weight) + mono[rightIndex] * weight;
    resampled[frameIndex] = clampPCM(interpolated);
  }

  return resampled;
}

async function readMessageData(data) {
  if (typeof data === 'string') {
    return data;
  }

  if (data instanceof Buffer) {
    return data.toString('utf8');
  }

  if (data instanceof ArrayBuffer) {
    return Buffer.from(data).toString('utf8');
  }

  if (typeof Blob !== 'undefined' && data instanceof Blob) {
    return Buffer.from(await data.arrayBuffer()).toString('utf8');
  }

  return String(data);
}

function waitForSocketOpen(socket) {
  if (socket.readyState === WebSocket.OPEN) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    socket.addEventListener('open', () => resolve(), { once: true });
    socket.addEventListener('error', (event) => reject(event.error ?? new Error('WebSocket failed to open.')), {
      once: true,
    });
  });
}

async function main() {
  const absoluteFilePath = path.resolve(inputFilePath);
  const wavBuffer = await fs.readFile(absoluteFilePath);
  const wav = parseWavFile(wavBuffer);
  const pcm = mixToMonoAndResample(wav.pcm, wav.channels, wav.sampleRate, targetSampleRate);
  const pcmBytes = Buffer.from(pcm.buffer, pcm.byteOffset, pcm.byteLength);

  console.log(`Loaded ${path.basename(absoluteFilePath)} (${wav.sampleRate} Hz -> ${targetSampleRate} Hz, ${pcm.length} samples).`);

  const sessionResponse = await fetch(`${backendBaseURL}/api/asr/session`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${bearerToken}`,
    },
    body: JSON.stringify({
      sampleRate: targetSampleRate,
      channels: 1,
    }),
  });

  const sessionPayload = await sessionResponse.json();
  if (!sessionResponse.ok) {
    throw new Error(sessionPayload.error ?? 'Failed to create ASR session.');
  }

  const descriptor = sessionPayload.session;
  if (!descriptor?.wsUrl) {
    throw new Error('ASR session response is incomplete.');
  }

  const socket = new WebSocket(descriptor.wsUrl);
  const packetDurationMS = Number(descriptor.packetDurationMs) || defaultChunkDurationMS;
  const chunkByteLength = Math.floor((targetSampleRate * 2 * packetDurationMS) / 1000);
  const finals = [];

  let transcriptionReady;
  let transcriptionCompleted;

  const startedPromise = new Promise((resolve, reject) => {
    transcriptionReady = resolve;
    socket.addEventListener('error', (event) => reject(event.error ?? new Error('WebSocket failed.')), {
      once: true,
    });
  });

  const completedPromise = new Promise((resolve, reject) => {
    transcriptionCompleted = resolve;
    socket.addEventListener('error', (event) => reject(event.error ?? new Error('WebSocket failed.')), { once: true });
  });

  socket.addEventListener('message', async (event) => {
    const text = await readMessageData(event.data);
    let payload;

    try {
      payload = JSON.parse(text);
    } catch {
      return;
    }

    switch (payload?.type) {
      case 'ready':
        console.log('ASR proxy ready.');
        transcriptionReady?.();
        break;
      case 'partial':
        if (payload?.text?.trim()) {
          console.log(`[partial] ${payload.text.trim()}`);
        }
        break;
      case 'final':
        if (payload?.text?.trim()) {
          finals.push(payload.text.trim());
          console.log(`[final] ${payload.text.trim()}`);
        }
        break;
      case 'error':
        console.log(`[error] ${payload?.message ?? 'unknown'}`);
        break;
      case 'closed':
        transcriptionCompleted?.();
        break;
      default:
        break;
    }
  });

  await waitForSocketOpen(socket);

  await startedPromise;

  for (let offset = 0; offset < pcmBytes.length; offset += chunkByteLength) {
    const chunk = pcmBytes.subarray(offset, Math.min(offset + chunkByteLength, pcmBytes.length));
    socket.send(chunk);
    await sleep(packetDurationMS);
  }

  socket.send(JSON.stringify({ type: 'stop' }));

  await Promise.race([completedPromise, sleep(5000)]);
  socket.close();

  console.log('');
  console.log('Final transcript:');
  console.log(finals.join('\n') || '(empty)');
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
