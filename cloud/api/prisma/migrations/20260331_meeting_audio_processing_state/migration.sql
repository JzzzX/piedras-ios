ALTER TABLE "Meeting"
ADD COLUMN "audioProcessingState" TEXT NOT NULL DEFAULT 'idle',
ADD COLUMN "audioProcessingError" TEXT NOT NULL DEFAULT '',
ADD COLUMN "audioProcessingAttempts" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "audioProcessingRequestedAt" TIMESTAMP(3),
ADD COLUMN "audioProcessingStartedAt" TIMESTAMP(3),
ADD COLUMN "audioProcessingCompletedAt" TIMESTAMP(3);
