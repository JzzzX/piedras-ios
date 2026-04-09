import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { getAsrRuntimeStatus } from "@/lib/asr";
import { buildBackendHealthPayload } from "@/lib/backend-health";
import { getConfiguredProviders } from "@/lib/llm-provider";
import { getMeetingAttachmentRuntimeStatus } from "@/lib/meeting-attachment-runtime-health";
import { getLlmRuntimeStatus } from "@/lib/llm-health";
import { getAudioFinalizationRuntimeStatus } from "@/lib/recording-runtime-health";
import { getStartupBootstrapSnapshot } from "@/lib/startup-bootstrap-state";

export async function GET(req: NextRequest) {
  const requestedMode = req.nextUrl.searchParams.get('mode')?.toLowerCase();
  const pathname = req.nextUrl.pathname;
  const mode =
    requestedMode
    ?? (pathname === '/healthz' ? 'basic' : 'full');
  const startupBootstrap = getStartupBootstrapSnapshot();
  let database = false;

  try {
    await prisma.$queryRaw`SELECT 1`;
    database = true;
  } catch {
    database = false;
  }

  const checkedAt = new Date().toISOString();

  if (mode === 'basic') {
    return NextResponse.json(
      buildBackendHealthPayload({
        mode: 'basic',
        database,
        startupBootstrap,
        checkedAt,
      })
    );
  }

  const asr = await getAsrRuntimeStatus().catch((error) => ({
    ready: false,
    configured: false,
    message: error instanceof Error ? error.message : String(error),
  }));
  const llm = await getLlmRuntimeStatus().catch((error) => ({
    configured: false,
    reachable: false,
    ready: false,
    checkedAt: null,
    lastError: error instanceof Error ? error.message : String(error),
    provider: 'none',
    model: null,
    preset: null,
    message: error instanceof Error ? error.message : String(error),
  }));
  const audioFinalization = await getAudioFinalizationRuntimeStatus().catch((error) => ({
    configured: false,
    ready: false,
    ffmpegAvailable: false,
    storageReady: false,
    storagePersistent: false,
    storagePath: '',
    checkedAt: null,
    lastError: error instanceof Error ? error.message : String(error),
    message: error instanceof Error ? error.message : String(error),
  }));
  const noteAttachments = await getMeetingAttachmentRuntimeStatus().catch((error) => ({
    configured: false,
    ready: false,
    storageReady: false,
    storagePersistent: false,
    storagePath: '',
    checkedAt: null,
    lastError: error instanceof Error ? error.message : String(error),
    message: error instanceof Error ? error.message : String(error),
  }));
  return NextResponse.json(
    buildBackendHealthPayload({
      mode: 'full',
      database,
      llmProviders: getConfiguredProviders(),
      asr,
      audioFinalization,
      noteAttachments,
      llm,
      startupBootstrap,
      checkedAt,
    })
  );
}
