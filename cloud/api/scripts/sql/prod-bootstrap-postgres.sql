BEGIN;

CREATE TABLE IF NOT EXISTS "Workspace" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "icon" TEXT NOT NULL DEFAULT 'folder',
    "color" TEXT NOT NULL DEFAULT '#94a3b8',
    "workflowMode" TEXT NOT NULL DEFAULT 'general',
    "modeLabel" TEXT NOT NULL DEFAULT '',
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Workspace_pkey" PRIMARY KEY ("id")
);

INSERT INTO "Workspace" (
    "id",
    "name",
    "description",
    "icon",
    "color",
    "workflowMode",
    "modeLabel",
    "sortOrder",
    "createdAt",
    "updatedAt"
)
SELECT
    '00000000-0000-0000-0000-000000000001',
    '默认空间',
    '系统自动创建的默认空间',
    'folder',
    '#94a3b8',
    'general',
    '',
    0,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
WHERE NOT EXISTS (
    SELECT 1 FROM "Workspace"
);

ALTER TABLE "Folder"
    ADD COLUMN IF NOT EXISTS "candidateStatus" TEXT NOT NULL DEFAULT 'new',
    ADD COLUMN IF NOT EXISTS "description" TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS "handoffSummary" TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS "icon" TEXT NOT NULL DEFAULT 'folder',
    ADD COLUMN IF NOT EXISTS "nextFocus" TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS "nextInterviewer" TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS "workspaceId" TEXT;

ALTER TABLE "Meeting"
    ADD COLUMN IF NOT EXISTS "audioDuration" INTEGER,
    ADD COLUMN IF NOT EXISTS "audioEnhancedNotes" TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS "audioEnhancedNotesError" TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS "audioEnhancedNotesModel" TEXT,
    ADD COLUMN IF NOT EXISTS "audioEnhancedNotesProvider" TEXT,
    ADD COLUMN IF NOT EXISTS "audioEnhancedNotesStatus" TEXT NOT NULL DEFAULT 'idle',
    ADD COLUMN IF NOT EXISTS "audioEnhancedNotesUpdatedAt" TIMESTAMP(3),
    ADD COLUMN IF NOT EXISTS "audioMimeType" TEXT,
    ADD COLUMN IF NOT EXISTS "audioUpdatedAt" TIMESTAMP(3),
    ADD COLUMN IF NOT EXISTS "enhanceRecipeId" TEXT,
    ADD COLUMN IF NOT EXISTS "handoffNote" TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS "interviewerName" TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS "recommendation" TEXT NOT NULL DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS "roundLabel" TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS "workspaceId" TEXT;

ALTER TABLE "PromptTemplate"
    ADD COLUMN IF NOT EXISTS "starterQuestion" TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS "surfaces" TEXT NOT NULL DEFAULT 'both';

UPDATE "Folder"
SET "workspaceId" = '00000000-0000-0000-0000-000000000001'
WHERE "workspaceId" IS NULL OR "workspaceId" = '';

UPDATE "Meeting"
SET "workspaceId" = '00000000-0000-0000-0000-000000000001'
WHERE "workspaceId" IS NULL OR "workspaceId" = '';

ALTER TABLE "Folder"
    ALTER COLUMN "workspaceId" SET NOT NULL;

ALTER TABLE "Meeting"
    ALTER COLUMN "workspaceId" SET NOT NULL;

CREATE TABLE IF NOT EXISTS "WorkspaceAsset" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "originalName" TEXT NOT NULL,
    "assetType" TEXT NOT NULL,
    "mimeType" TEXT NOT NULL,
    "fileSize" INTEGER NOT NULL,
    "storageKey" TEXT NOT NULL,
    "extractedText" TEXT NOT NULL DEFAULT '',
    "extractionStatus" TEXT NOT NULL DEFAULT 'preview',
    "extractionError" TEXT NOT NULL DEFAULT '',
    "workspaceId" TEXT NOT NULL,
    "collectionId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "WorkspaceAsset_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "CustomVocabularyTerm" (
    "id" TEXT NOT NULL,
    "term" TEXT NOT NULL,
    "scope" TEXT NOT NULL,
    "workspaceId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CustomVocabularyTerm_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "AsrVocabularySyncState" (
    "id" TEXT NOT NULL,
    "remoteVocabularyId" TEXT,
    "contentHash" TEXT NOT NULL DEFAULT '',
    "lastSyncedAt" TIMESTAMP(3),
    "lastError" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AsrVocabularySyncState_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "GlobalChatSession" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "scope" TEXT NOT NULL,
    "filters" TEXT NOT NULL DEFAULT '{}',
    "workspaceId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GlobalChatSession_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "GlobalChatMessage" (
    "id" TEXT NOT NULL,
    "role" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "timestamp" DOUBLE PRECISION NOT NULL,
    "templateId" TEXT,
    "sessionId" TEXT NOT NULL,

    CONSTRAINT "GlobalChatMessage_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "WorkspaceAsset_workspaceId_collectionId_updatedAt_idx"
ON "WorkspaceAsset"("workspaceId", "collectionId", "updatedAt");

CREATE INDEX IF NOT EXISTS "CustomVocabularyTerm_scope_workspaceId_idx"
ON "CustomVocabularyTerm"("scope", "workspaceId");

CREATE UNIQUE INDEX IF NOT EXISTS "CustomVocabularyTerm_scope_workspaceId_term_key"
ON "CustomVocabularyTerm"("scope", "workspaceId", "term");

CREATE INDEX IF NOT EXISTS "GlobalChatSession_updatedAt_idx"
ON "GlobalChatSession"("updatedAt");

CREATE INDEX IF NOT EXISTS "GlobalChatSession_workspaceId_idx"
ON "GlobalChatSession"("workspaceId");

CREATE INDEX IF NOT EXISTS "GlobalChatMessage_sessionId_timestamp_idx"
ON "GlobalChatMessage"("sessionId", "timestamp");

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'Meeting_workspaceId_fkey'
    ) THEN
        ALTER TABLE "Meeting"
            ADD CONSTRAINT "Meeting_workspaceId_fkey"
            FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id")
            ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'Folder_workspaceId_fkey'
    ) THEN
        ALTER TABLE "Folder"
            ADD CONSTRAINT "Folder_workspaceId_fkey"
            FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id")
            ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'WorkspaceAsset_workspaceId_fkey'
    ) THEN
        ALTER TABLE "WorkspaceAsset"
            ADD CONSTRAINT "WorkspaceAsset_workspaceId_fkey"
            FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id")
            ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'WorkspaceAsset_collectionId_fkey'
    ) THEN
        ALTER TABLE "WorkspaceAsset"
            ADD CONSTRAINT "WorkspaceAsset_collectionId_fkey"
            FOREIGN KEY ("collectionId") REFERENCES "Folder"("id")
            ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'CustomVocabularyTerm_workspaceId_fkey'
    ) THEN
        ALTER TABLE "CustomVocabularyTerm"
            ADD CONSTRAINT "CustomVocabularyTerm_workspaceId_fkey"
            FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id")
            ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'GlobalChatSession_workspaceId_fkey'
    ) THEN
        ALTER TABLE "GlobalChatSession"
            ADD CONSTRAINT "GlobalChatSession_workspaceId_fkey"
            FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id")
            ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'GlobalChatMessage_sessionId_fkey'
    ) THEN
        ALTER TABLE "GlobalChatMessage"
            ADD CONSTRAINT "GlobalChatMessage_sessionId_fkey"
            FOREIGN KEY ("sessionId") REFERENCES "GlobalChatSession"("id")
            ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

COMMIT;
