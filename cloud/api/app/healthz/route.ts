import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { getAsrRuntimeStatus } from "@/lib/asr";
import { getConfiguredProviders } from "@/lib/llm-provider";
import { getLlmRuntimeStatus } from "@/lib/llm-health";

export async function GET() {
  let database = false;

  try {
    await prisma.$queryRaw`SELECT 1`;
    database = true;
  } catch {
    database = false;
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

  return NextResponse.json({
    ok: database,
    database,
    llmProviders: getConfiguredProviders(),
    asr,
    llm,
    checkedAt: new Date().toISOString(),
  });
}
