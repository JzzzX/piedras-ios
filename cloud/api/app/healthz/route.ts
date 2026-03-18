import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { getAsrRuntimeStatus } from "@/lib/asr";
import { getConfiguredProviders } from "@/lib/llm-provider";

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

  return NextResponse.json({
    ok: database,
    database,
    llmProviders: getConfiguredProviders(),
    asr,
    checkedAt: new Date().toISOString(),
  });
}
