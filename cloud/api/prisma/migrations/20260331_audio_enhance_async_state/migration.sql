ALTER TABLE "Meeting"
  ADD COLUMN IF NOT EXISTS "audioEnhancedNotesAttempts" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "audioEnhancedNotesRequestedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "audioEnhancedNotesStartedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "audioEnhancedNotesRequestPayload" TEXT;
