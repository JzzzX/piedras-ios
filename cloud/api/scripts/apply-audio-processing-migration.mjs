import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const sql = `
ALTER TABLE "Meeting"
ADD COLUMN IF NOT EXISTS "audioProcessingState" TEXT NOT NULL DEFAULT 'idle',
ADD COLUMN IF NOT EXISTS "audioProcessingError" TEXT NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS "audioProcessingAttempts" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "audioProcessingRequestedAt" TIMESTAMP(3),
ADD COLUMN IF NOT EXISTS "audioProcessingStartedAt" TIMESTAMP(3),
ADD COLUMN IF NOT EXISTS "audioProcessingCompletedAt" TIMESTAMP(3),
ADD COLUMN IF NOT EXISTS "audioEnhancedNotesAttempts" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "audioEnhancedNotesRequestedAt" TIMESTAMP(3),
ADD COLUMN IF NOT EXISTS "audioEnhancedNotesStartedAt" TIMESTAMP(3),
ADD COLUMN IF NOT EXISTS "audioEnhancedNotesRequestPayload" TEXT;
`;

try {
  await prisma.$executeRawUnsafe(sql);
  console.log('audio-processing-and-audio-ai-columns-ready');
} finally {
  await prisma.$disconnect();
}
