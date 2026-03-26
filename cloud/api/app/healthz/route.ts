import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { getAsrRuntimeStatus } from "@/lib/asr";
import { getConfiguredProviders } from "@/lib/llm-provider";
import { getLlmRuntimeStatus } from "@/lib/llm-health";
import { getAudioFinalizationRuntimeStatus } from "@/lib/recording-runtime-health";

export async function GET(req: NextRequest) {
  const mode = req.nextUrl.searchParams.get('mode')?.toLowerCase();
  let database = false;

  try {
    await prisma.$queryRaw`SELECT 1`;
    database = true;
  } catch {
    database = false;
  }

  if (mode === 'basic') {
    return NextResponse.json({
      ok: database,
      database,
      checkedAt: new Date().toISOString(),
    });
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
  const recordingReady = database && asr.ready && audioFinalization.ready;

  return NextResponse.json({
    ok: recordingReady,
    database,
    llmProviders: getConfiguredProviders(),
    asr,
    audioFinalization,
    recordingReady,
    llm,
    checkedAt: new Date().toISOString(),
  });
}
