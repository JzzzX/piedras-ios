ALTER TABLE "Meeting"
  ADD COLUMN IF NOT EXISTS "audioCloudSyncEnabled" BOOLEAN NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS "MeetingAttachment" (
  "id" TEXT NOT NULL,
  "originalName" TEXT NOT NULL,
  "mimeType" TEXT NOT NULL,
  "fileSize" INTEGER NOT NULL DEFAULT 0,
  "extractedText" TEXT NOT NULL DEFAULT '',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "meetingId" TEXT NOT NULL,

  CONSTRAINT "MeetingAttachment_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "MeetingAttachment_meetingId_updatedAt_idx"
  ON "MeetingAttachment"("meetingId", "updatedAt");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'MeetingAttachment_meetingId_fkey'
  ) THEN
    ALTER TABLE "MeetingAttachment"
      ADD CONSTRAINT "MeetingAttachment_meetingId_fkey"
      FOREIGN KEY ("meetingId") REFERENCES "Meeting"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
