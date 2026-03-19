#!/usr/bin/env node

const crypto = require('node:crypto');
const http = require('node:http');
const { URL } = require('node:url');
const zlib = require('node:zlib');
const next = require('next');
const { WebSocketServer, WebSocket } = require('ws');

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOSTNAME || '0.0.0.0';
const SESSION_SECRET = process.env.ASR_PROXY_SESSION_SECRET || '';
const DOUBAO_APP_ID = process.env.DOUBAO_ASR_APP_ID || '';
const DOUBAO_ACCESS_TOKEN = process.env.DOUBAO_ASR_ACCESS_TOKEN || '';
const DOUBAO_RESOURCE_ID = process.env.DOUBAO_ASR_RESOURCE_ID || 'volc.seedasr.sauc.duration';
const DOUBAO_WS_URL =
  process.env.DOUBAO_ASR_WS_URL || 'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async';
const DEFAULT_SAMPLE_RATE = 16_000;
const DEFAULT_CHANNELS = 1;

const VERSION_AND_HEADER = 0x11;
const FULL_CLIENT_REQUEST = 0x10;
const AUDIO_ONLY_REQUEST = 0x21;
const AUDIO_ONLY_LAST_REQUEST = 0x23;
const JSON_GZIP = 0x11;
const RAW_GZIP = 0x01;

const proxyStats = {
  startedAt: new Date().toISOString(),
  totalConnections: 0,
  activeConnections: 0,
  lastReadyAt: null,
  lastPartialAt: null,
  lastFinalAt: null,
  lastUpstreamCloseAt: null,
  lastCloseAt: null,
  lastCloseReason: null,
  lastCloseSeverity: null,
  lastError: null,
};

function toParsedUrl(req) {
  const requestURL = new URL(req.url || '/', `http://${req.headers.host || '127.0.0.1'}`);

  return {
    pathname: requestURL.pathname,
    query: Object.fromEntries(requestURL.searchParams.entries()),
    search: requestURL.search,
    hash: requestURL.hash,
    href: requestURL.href,
    path: `${requestURL.pathname}${requestURL.search}`,
  };
}

function normalizePath(value, fallback) {
  const input = String(value || fallback || '').trim();
  const normalized = input.startsWith('/') ? input : `/${input}`;
  return normalized.replace(/\/{2,}/g, '/');
}

const proxyHealthPath = normalizePath(process.env.ASR_PROXY_HEALTH_PATH, '/asr-proxy/healthz');
const proxyWSPaths = Array.from(
  new Set([
    normalizePath(process.env.ASR_PROXY_WS_PATH, '/ws/asr'),
    '/asr-proxy/ws/asr',
  ])
);

function log(event, detail = {}) {
  console.log(
    JSON.stringify({
      scope: 'cloud-api-proxy',
      event,
      timestamp: new Date().toISOString(),
      ...detail,
    })
  );
}

function ensureEnvReady() {
  const missing = [];

  if (!SESSION_SECRET) missing.push('ASR_PROXY_SESSION_SECRET');
  if (!DOUBAO_APP_ID) missing.push('DOUBAO_ASR_APP_ID');
  if (!DOUBAO_ACCESS_TOKEN) missing.push('DOUBAO_ASR_ACCESS_TOKEN');
  if (!DOUBAO_RESOURCE_ID) missing.push('DOUBAO_ASR_RESOURCE_ID');

  if (missing.length > 0) {
    throw new Error(`Doubao ASR proxy env missing: ${missing.join(', ')}`);
  }
}

function fromBase64URL(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padding = normalized.length % 4 === 0 ? '' : '='.repeat(4 - (normalized.length % 4));
  return Buffer.from(`${normalized}${padding}`, 'base64');
}

function verifySessionToken(token) {
  const [payloadPart, signaturePart] = String(token || '').split('.');
  if (!payloadPart || !signaturePart) {
    throw new Error('session_token 缺失或格式无效');
  }

  const expectedSignature = crypto
    .createHmac('sha256', SESSION_SECRET)
    .update(payloadPart)
    .digest();
  const actualSignature = fromBase64URL(signaturePart);

  if (
    actualSignature.length !== expectedSignature.length ||
    !crypto.timingSafeEqual(actualSignature, expectedSignature)
  ) {
    throw new Error('session_token 签名无效');
  }

  const payload = JSON.parse(fromBase64URL(payloadPart).toString('utf8'));

  if (payload.provider !== 'doubao-proxy') {
    throw new Error('session_token provider 不匹配');
  }

  if (typeof payload.expiresAt !== 'number' || Date.now() >= payload.expiresAt) {
    throw new Error('session_token 已过期');
  }

  return payload;
}

function int32Buffer(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeInt32BE(value, 0);
  return buffer;
}

function uint32Buffer(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32BE(value >>> 0, 0);
  return buffer;
}

function encodeJSONFrame(messageTypeByte, payload) {
  const json = Buffer.from(JSON.stringify(payload), 'utf8');
  const compressed = zlib.gzipSync(json);
  return Buffer.concat([
    Buffer.from([VERSION_AND_HEADER, messageTypeByte, JSON_GZIP, 0x00]),
    uint32Buffer(compressed.length),
    compressed,
  ]);
}

function encodeAudioFrame(sequence, audioBytes, isLast) {
  const compressed = zlib.gzipSync(audioBytes);
  return Buffer.concat([
    Buffer.from([VERSION_AND_HEADER, isLast ? AUDIO_ONLY_LAST_REQUEST : AUDIO_ONLY_REQUEST, RAW_GZIP, 0x00]),
    int32Buffer(sequence),
    uint32Buffer(compressed.length),
    compressed,
  ]);
}

function decodeServerFrame(raw) {
  const buffer = Buffer.isBuffer(raw) ? raw : Buffer.from(raw);

  if (buffer.length < 8) {
    throw new Error('豆包响应帧长度不足');
  }

  const headerSize = (buffer[0] & 0x0f) * 4;
  const messageType = (buffer[1] & 0xf0) >> 4;
  const messageFlags = buffer[1] & 0x0f;
  const serialization = (buffer[2] & 0xf0) >> 4;
  const compression = buffer[2] & 0x0f;

  let offset = headerSize;
  let sequence = null;
  let errorCode = null;

  if (messageType === 0x09 && (messageFlags === 0x01 || messageFlags === 0x03)) {
    sequence = buffer.readInt32BE(offset);
    offset += 4;
  } else if (messageType === 0x09 && messageFlags === 0x04) {
    sequence = buffer.readInt32BE(offset);
    offset += 4;

    const traceIdLength = buffer.readUInt32BE(offset);
    offset += 4;

    if (traceIdLength > 0 && traceIdLength <= buffer.length - offset - 4) {
      offset += traceIdLength;
    } else {
      throw new Error(`豆包响应 trace id 长度异常: ${traceIdLength}`);
    }
  } else if (messageType === 0x0f) {
    errorCode = buffer.readInt32BE(offset);
    offset += 4;
  }

  const payloadSize = buffer.readUInt32BE(offset);
  offset += 4;
  const payloadBuffer = buffer.subarray(offset, offset + payloadSize);

  let payload = payloadBuffer;
  if (compression === 0x01 && payload.length > 0) {
    payload = zlib.gunzipSync(payload);
  }

  let json = null;
  if (serialization === 0x01 && payload.length > 0) {
    json = JSON.parse(payload.toString('utf8'));
  }

  return {
    messageType,
    messageFlags,
    sequence,
    errorCode,
    json,
  };
}

function collectTextFragments(value, bucket) {
  if (!value) return;

  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed) bucket.push(trimmed);
    return;
  }

  if (Array.isArray(value)) {
    value.forEach((item) => collectTextFragments(item, bucket));
    return;
  }

  if (typeof value === 'object') {
    ['text', 'utterance', 'transcript', 'voice_text_str', 'result', 'sentence'].forEach((key) => {
      if (key in value) {
        collectTextFragments(value[key], bucket);
      }
    });
  }
}

function maybeBoolean(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (['true', '1', 'yes', 'final'].includes(normalized)) return true;
    if (['false', '0', 'no', 'partial'].includes(normalized)) return false;
  }
  return null;
}

function maybeNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function pickCandidateObjects(payload) {
  const bucket = [];

  const visit = (value) => {
    if (!value || typeof value !== 'object') return;
    bucket.push(value);
    ['result', 'payload_msg', 'payload', 'message', 'data'].forEach((key) => {
      if (value[key] && typeof value[key] === 'object') {
        bucket.push(value[key]);
      }
    });
  };

  visit(payload);
  return bucket;
}

function extractRecognitionUpdate(payload, fallbackEndTimeMs) {
  const candidates = pickCandidateObjects(payload);
  const textParts = [];
  let isFinal = null;
  let startTimeMs = null;
  let endTimeMs = null;

  for (const candidate of candidates) {
    if (Array.isArray(candidate.utterances)) {
      for (const utterance of candidate.utterances) {
        collectTextFragments(utterance, textParts);
        if (isFinal === null) {
          isFinal = maybeBoolean(utterance.definite ?? utterance.is_final ?? utterance.final);
        }
        if (startTimeMs === null) {
          startTimeMs =
            maybeNumber(utterance.start_time) ??
            maybeNumber(utterance.startTime) ??
            maybeNumber(utterance.begin_time) ??
            maybeNumber(utterance.beginTime) ??
            maybeNumber(utterance.start_ms);
        }
        if (endTimeMs === null) {
          endTimeMs =
            maybeNumber(utterance.end_time) ??
            maybeNumber(utterance.endTime) ??
            maybeNumber(utterance.end_ms);
        }
      }
    }

    if (Array.isArray(candidate.results)) {
      candidate.results.forEach((item) => collectTextFragments(item, textParts));
    }

    collectTextFragments(candidate, textParts);

    if (isFinal === null) {
      isFinal = maybeBoolean(candidate.definite ?? candidate.is_final ?? candidate.final);
    }

    if (startTimeMs === null) {
      startTimeMs =
        maybeNumber(candidate.start_time) ??
        maybeNumber(candidate.startTime) ??
        maybeNumber(candidate.begin_time) ??
        maybeNumber(candidate.beginTime) ??
        maybeNumber(candidate.start_ms);
    }

    if (endTimeMs === null) {
      endTimeMs =
        maybeNumber(candidate.end_time) ??
        maybeNumber(candidate.endTime) ??
        maybeNumber(candidate.end_ms);
    }
  }

  const text = Array.from(new Set(textParts)).join(' ').trim();
  if (!text) {
    return null;
  }

  const end = endTimeMs ?? fallbackEndTimeMs;
  const start = startTimeMs ?? Math.max(0, end - 1_500);

  return {
    text,
    isFinal: isFinal === true,
    startTimeMs: start,
    endTimeMs: Math.max(end, start),
  };
}

function makeConnectHeaders() {
  return {
    'X-Api-App-Key': DOUBAO_APP_ID,
    'X-Api-Access-Key': DOUBAO_ACCESS_TOKEN,
    'X-Api-Resource-Id': DOUBAO_RESOURCE_ID,
    'X-Api-Connect-Id': crypto.randomUUID(),
  };
}

function makeStartPayload(sessionPayload) {
  return {
    user: {
      uid: `piedras-${crypto.randomUUID()}`,
      did: 'piedras-ios',
      platform: 'iOS',
      sdk_version: 'piedras-proxy/1.0',
      app_version: '1.0',
    },
    audio: {
      format: 'pcm',
      codec: 'raw',
      rate: sessionPayload.sampleRate || DEFAULT_SAMPLE_RATE,
      bits: 16,
      channel: sessionPayload.channels || DEFAULT_CHANNELS,
    },
    request: {
      model_name: 'bigmodel',
      enable_itn: true,
      enable_punc: true,
      result_type: 'single',
      end_window_size: 800,
      show_utterances: true,
    },
  };
}

function sendJSON(ws, payload) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(payload));
  }
}

function closePair(client, upstream, code = 1000, reason = 'closed') {
  if (upstream && upstream.readyState !== WebSocket.CLOSED) {
    try {
      upstream.close();
    } catch {
      upstream.terminate();
    }
  }

  if (client.readyState === WebSocket.OPEN || client.readyState === WebSocket.CLOSING) {
    try {
      client.close(code, reason);
    } catch {}
  }
}

function noteClose(reason, severity = 'info') {
  proxyStats.lastCloseAt = new Date().toISOString();
  proxyStats.lastCloseReason = reason;
  proxyStats.lastCloseSeverity = severity;
}

function isIdleTimeoutError(errorCode, detail) {
  const normalizedDetail = String(detail || '').toLowerCase();
  return (
    Number(errorCode) === 45000081 ||
    normalizedDetail.includes('timeout waiting next packet') ||
    normalizedDetail.includes('waiting next packet timeout')
  );
}

function attachAsrProxy(server) {
  ensureEnvReady();

  const wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', (req, socket, head) => {
    const requestURL = new URL(req.url || '/', `http://${req.headers.host || '127.0.0.1'}`);
    if (!proxyWSPaths.includes(requestURL.pathname)) {
      socket.destroy();
      return;
    }

    let sessionPayload;
    try {
      sessionPayload = verifySessionToken(requestURL.searchParams.get('session_token'));
    } catch (error) {
      proxyStats.lastError = error instanceof Error ? error.message : String(error);
      log('session_token_invalid', { error: proxyStats.lastError });
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }

    wss.handleUpgrade(req, socket, head, (client) => {
      client.sessionPayload = sessionPayload;
      wss.emit('connection', client, req);
    });
  });

  wss.on('connection', (client) => {
    const sessionPayload = client.sessionPayload;
    const connectionId = crypto.randomUUID();
    let upstreamSequence = 2;
    let hasSentLastFrame = false;
    let lastAudioEndTimeMs = 0;
    let lastPartialText = '';
    let shouldSendLastFrameWhenUpstreamReady = false;
    let connectionClosed = false;
    let upstreamStartSent = false;
    const pendingAudioFrames = [];

    proxyStats.totalConnections += 1;
    proxyStats.activeConnections += 1;
    proxyStats.lastError = null;
    log('client_connected', {
      connectionId,
      sampleRate: sessionPayload.sampleRate || DEFAULT_SAMPLE_RATE,
      channels: sessionPayload.channels || DEFAULT_CHANNELS,
    });

    let upstream = null;

    const closeSession = ({
      message,
      detail = null,
      severity = 'error',
      notifyClientError = severity === 'error',
      closeCode = severity === 'error' ? 1011 : 1000,
    }) => {
      if (connectionClosed) {
        return;
      }

      connectionClosed = true;

      const composedMessage = detail ? `${message}: ${detail}` : message;
      noteClose(composedMessage, severity);

      if (severity === 'error') {
        proxyStats.lastError = composedMessage;
        log('connection_error', { connectionId, message, detail });
      } else {
        log('connection_closed', { connectionId, message, detail });
      }

      if (notifyClientError) {
        sendJSON(client, { type: 'error', message: composedMessage });
      }

      sendJSON(client, { type: 'closed' });
      closePair(client, upstream, closeCode, message.slice(0, 120));
    };

    const flushPendingAudio = () => {
      if (!upstream || upstream.readyState !== WebSocket.OPEN || !upstreamStartSent || connectionClosed) {
        return;
      }

      while (pendingAudioFrames.length > 0) {
        const audioBytes = pendingAudioFrames.shift();
        try {
          upstream.send(encodeAudioFrame(upstreamSequence, audioBytes, false));
          upstreamSequence += 1;
        } catch (error) {
          closeSession({
            message: '豆包 ASR 音频发送失败',
            detail: error instanceof Error ? error.message : '',
          });
          return;
        }
      }

      if (shouldSendLastFrameWhenUpstreamReady && !hasSentLastFrame) {
        hasSentLastFrame = true;
        shouldSendLastFrameWhenUpstreamReady = false;
        try {
          upstream.send(encodeAudioFrame(-upstreamSequence, Buffer.alloc(0), true));
          upstreamSequence += 1;
        } catch (error) {
          closeSession({
            message: '豆包 ASR 结束帧发送失败',
            detail: error instanceof Error ? error.message : '',
          });
        }
      }
    };

    const ensureUpstream = () => {
      if (upstream || connectionClosed) {
        return;
      }

      upstream = new WebSocket(DOUBAO_WS_URL, {
        headers: makeConnectHeaders(),
      });

      upstream.on('open', () => {
        log('upstream_open', { connectionId });
        try {
          upstream.send(encodeJSONFrame(FULL_CLIENT_REQUEST, makeStartPayload(sessionPayload)));
          upstreamStartSent = true;
          flushPendingAudio();
        } catch (error) {
          closeSession({
            message: '豆包 ASR 初始化失败',
            detail: error instanceof Error ? error.message : '',
          });
        }
      });

      upstream.on('message', (raw) => {
        try {
          const decoded = decodeServerFrame(raw);

          if (decoded.messageType === 0x0f) {
            const errorDetail =
              decoded.json?.message || decoded.json?.error || JSON.stringify(decoded.json || {});

            if (isIdleTimeoutError(decoded.errorCode, errorDetail)) {
              closeSession({
                message: '豆包 ASR 会话空闲超时',
                detail: errorDetail,
                severity: 'info',
                notifyClientError: false,
              });
              return;
            }

            closeSession({
              message: `豆包 ASR 错误 ${decoded.errorCode || ''}`.trim(),
              detail: errorDetail,
            });
            return;
          }

          if (decoded.messageType !== 0x09 || !decoded.json) {
            return;
          }

          const update = extractRecognitionUpdate(decoded.json, lastAudioEndTimeMs || Date.now());
          if (!update) {
            return;
          }

          if (update.isFinal) {
            lastPartialText = '';
            proxyStats.lastFinalAt = new Date().toISOString();
            log('final', {
              connectionId,
              text: update.text.slice(0, 120),
              startTimeMs: update.startTimeMs,
              endTimeMs: update.endTimeMs,
            });
            sendJSON(client, {
              type: 'final',
              text: update.text,
              startTimeMs: update.startTimeMs,
              endTimeMs: update.endTimeMs,
            });
          } else if (update.text !== lastPartialText) {
            lastPartialText = update.text;
            proxyStats.lastPartialAt = new Date().toISOString();
            log('partial', {
              connectionId,
              text: update.text.slice(0, 120),
            });
            sendJSON(client, {
              type: 'partial',
              text: update.text,
            });
          }
        } catch (error) {
          closeSession({
            message: '解析豆包 ASR 响应失败',
            detail: error instanceof Error ? error.message : '',
          });
        }
      });

      upstream.on('error', (error) => {
        closeSession({
          message: '豆包 ASR 连接失败',
          detail: error.message,
        });
      });

      upstream.on('close', () => {
        proxyStats.lastUpstreamCloseAt = new Date().toISOString();
        log('upstream_closed', { connectionId });
        if (connectionClosed) {
          return;
        }

        closeSession({
          message: hasSentLastFrame ? '豆包 ASR 会话已结束' : '豆包 ASR 连接关闭',
          severity: 'info',
          notifyClientError: false,
        });
      });
    };

    proxyStats.lastReadyAt = new Date().toISOString();
    log('proxy_ready', { connectionId });
    sendJSON(client, { type: 'ready' });

    client.on('message', (data, isBinary) => {
      if (isBinary) {
        const audioBytes = Buffer.from(data);
        if (audioBytes.length === 0) {
          return;
        }

        const sampleRate = Number(sessionPayload.sampleRate || DEFAULT_SAMPLE_RATE);
        const channels = Number(sessionPayload.channels || DEFAULT_CHANNELS);
        const bytesPerSecond = sampleRate * channels * 2;
        const durationMs = Math.round((audioBytes.length / bytesPerSecond) * 1000);
        lastAudioEndTimeMs += durationMs;

        pendingAudioFrames.push(audioBytes);
        ensureUpstream();
        flushPendingAudio();
        return;
      }

      try {
        const payload = JSON.parse(Buffer.from(data).toString('utf8'));
        if (payload?.type === 'stop' && !hasSentLastFrame) {
          if (!upstream && pendingAudioFrames.length === 0) {
            closeSession({
              message: 'ASR 会话已结束',
              detail: '客户端在发送音频前主动结束会话',
              severity: 'info',
              notifyClientError: false,
            });
            return;
          }

          shouldSendLastFrameWhenUpstreamReady = true;
          ensureUpstream();
          flushPendingAudio();
        }
      } catch {
        closeSession({
          message: '客户端消息格式错误',
        });
      }
    });

    client.on('close', () => {
      proxyStats.activeConnections = Math.max(0, proxyStats.activeConnections - 1);
      log('client_closed', { connectionId });
      closePair(client, upstream);
    });

    client.on('error', () => {
      proxyStats.activeConnections = Math.max(0, proxyStats.activeConnections - 1);
      log('client_socket_error', { connectionId });
      closePair(client, upstream);
    });
  });
}

async function main() {
  const app = next({
    dev: false,
    dir: __dirname,
  });
  await app.prepare();
  const handle = app.getRequestHandler();

  const server = http.createServer((req, res) => {
    const requestURL = new URL(req.url || '/', `http://${req.headers.host || '127.0.0.1'}`);

    if (requestURL.pathname === proxyHealthPath) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(
        JSON.stringify({
          ok: true,
          ...proxyStats,
        })
      );
      return;
    }

    handle(req, res, toParsedUrl(req));
  });

  attachAsrProxy(server);

  server.listen(PORT, HOST, () => {
    log('listening', {
      host: HOST,
      port: PORT,
      proxyHealthPath,
      proxyWSPaths,
    });
  });
}

main().catch((error) => {
  console.error('[cloud-api] fatal:', error);
  process.exit(1);
});
