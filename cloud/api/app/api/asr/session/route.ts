import crypto from 'node:crypto';
import { NextRequest, NextResponse } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import {
  getAsrRuntimeStatus,
  getAsrStatus,
  resolveAsrProxyPublicBaseURL,
  resolveAsrProxyWSPath,
} from '@/lib/asr';
import { buildAsrSessionContext } from '@/lib/asr-live-session';

interface AsrSessionRequest {
  sampleRate?: number;
  channels?: number;
  workspaceId?: string;
  meetingId?: string;
}

const DOUBAO_PACKET_DURATION_MS = 200;
const DOUBAO_SESSION_LIFETIME_MS = 10 * 60 * 1000;

function toBase64URL(value: Buffer | string) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function createProxySessionToken(payload: Record<string, unknown>) {
  const secret = process.env.ASR_PROXY_SESSION_SECRET;

  if (!secret) {
    throw new Error('ASR_PROXY_SESSION_SECRET 未配置');
  }

  const encodedPayload = toBase64URL(JSON.stringify(payload));
  const signature = crypto
    .createHmac('sha256', secret)
    .update(encodedPayload)
    .digest();

  return `${encodedPayload}.${toBase64URL(signature)}`;
}

function resolveProxyWSURL(req: NextRequest, sessionToken: string) {
  const requestBaseURL = new URL(req.nextUrl.origin);
  const explicitBaseURL = resolveAsrProxyPublicBaseURL(requestBaseURL.protocol.replace(/:$/, ''));
  const baseURL =
    requestBaseURL.hostname === 'localhost' || requestBaseURL.hostname === '127.0.0.1'
      ? explicitBaseURL ?? requestBaseURL
      : requestBaseURL;
  const wsProtocol = baseURL.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsURL = new URL(resolveAsrProxyWSPath(), `${wsProtocol}//${baseURL.host}`);
  wsURL.searchParams.set('session_token', sessionToken);
  return wsURL.toString();
}

function stripMarkup(value: string | null | undefined) {
  return String(value || '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function resolveSessionContext(
  auth: { workspace: { id: string; name: string } },
  payload: AsrSessionRequest
) {
  const meetingId = payload.meetingId?.trim() || null;
  if (!meetingId) {
    return buildAsrSessionContext({
      workspaceName: auth.workspace.name,
      meetingTitle: '',
      recentTranscriptTexts: [],
      noteSummary: '',
      maxTranscriptEntries: 3,
    });
  }

  const meeting = await prisma.meeting.findFirst({
    where: {
      id: meetingId,
      workspaceId: auth.workspace.id,
    },
    select: {
      title: true,
      userNotes: true,
      enhancedNotes: true,
      segments: {
        where: { isFinal: true },
        orderBy: { endTime: 'desc' },
        take: 3,
        select: { text: true },
      },
    },
  });

  return buildAsrSessionContext({
    workspaceName: auth.workspace.name,
    meetingTitle: meeting?.title ?? '',
    recentTranscriptTexts: meeting?.segments.map((segment) => segment.text) ?? [],
    noteSummary: stripMarkup(meeting?.enhancedNotes || meeting?.userNotes),
    maxTranscriptEntries: 3,
  });
}

function buildDoubaoSession(
  req: NextRequest,
  payload: AsrSessionRequest,
  status: Awaited<ReturnType<typeof getAsrRuntimeStatus>>,
  contextJson: string
) {
  const now = Date.now();
  const sessionToken = createProxySessionToken({
    provider: 'doubao-proxy',
    sampleRate: payload.sampleRate ?? 16_000,
    channels: payload.channels ?? 1,
    workspaceId: payload.workspaceId ?? null,
    meetingId: payload.meetingId ?? null,
    contextJson,
    issuedAt: now,
    expiresAt: now + DOUBAO_SESSION_LIFETIME_MS,
  });

  return {
    provider: 'doubao-proxy',
    status,
    request: {
      sampleRate: payload.sampleRate ?? 16_000,
      channels: payload.channels ?? 1,
      includeSystemAudio: false,
    },
    session: {
      wsUrl: resolveProxyWSURL(req, sessionToken),
      sampleRate: payload.sampleRate ?? 16_000,
      channels: payload.channels ?? 1,
      codec: 'pcm_s16le',
      packetDurationMs: DOUBAO_PACKET_DURATION_MS,
    },
    message: '豆包 ASR 代理会话已创建',
  };
}

export async function POST(req: NextRequest) {
  const authContext = createRequestContext(req, '/api/asr/session');
  const auth = await requireAuthenticatedRequest(req, authContext);
  if (auth instanceof Response) {
    return auth;
  }

  const configuredStatus = getAsrStatus();
  const payload = (await req.json()) as AsrSessionRequest;

  if (!configuredStatus.configured) {
    return NextResponse.json(
      {
        error: `${configuredStatus.provider} 配置不完整`,
        status: configuredStatus,
      },
      { status: 400 }
    );
  }

  if (configuredStatus.mode !== 'doubao') {
    return NextResponse.json(
      {
        error: 'cloud/api 固定走豆包 ASR，请将 ASR_MODE 设置为 doubao',
        status: configuredStatus,
      },
      { status: 400 }
    );
  }

  try {
    const runtimeStatus = await getAsrRuntimeStatus();
    if (!runtimeStatus.ready) {
      return NextResponse.json(
        {
          error: runtimeStatus.message,
          status: runtimeStatus,
        },
        { status: 503 }
      );
    }

    const contextJson = await resolveSessionContext(auth, payload);
    return NextResponse.json(
      buildDoubaoSession(
        req,
        {
          ...payload,
          workspaceId: auth.workspace.id,
        },
        runtimeStatus,
        contextJson
      )
    );
  } catch (error) {
    return NextResponse.json(
      {
        error: error instanceof Error ? error.message : '创建豆包 ASR 会话失败',
      },
      { status: 500 }
    );
  }
}
