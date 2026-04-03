import type { Collection, Prisma, PrismaClient } from '@prisma/client';

const DEFAULT_COLLECTION_NAME = 'Notes';
const DEFAULT_COLLECTION_DESCRIPTION = 'Piedras default notes collection';
const DEFAULT_COLLECTION_ICON = 'tray.full';
const DEFAULT_COLLECTION_COLOR = '#0f766e';

type CollectionDatabase = PrismaClient | Prisma.TransactionClient;

interface SerializedCollection {
  id: string;
  name: string;
  isDefault: boolean;
}

function nextSortOrder(lastSortOrder: number | null | undefined) {
  return (lastSortOrder ?? 0) + 1;
}

function isDefaultCollection(collection: Pick<Collection, 'name' | 'description'>) {
  return (
    collection.name === DEFAULT_COLLECTION_NAME
    && collection.description === DEFAULT_COLLECTION_DESCRIPTION
  );
}

export function serializeCollection(
  collection: Pick<Collection, 'id' | 'name'>,
  defaultCollectionID: string
): SerializedCollection {
  return {
    id: collection.id,
    name: collection.name,
    isDefault: collection.id == defaultCollectionID,
  };
}

export async function ensureDefaultCollectionForWorkspace(
  db: CollectionDatabase,
  input: { workspaceId: string }
): Promise<Collection> {
  const existing = await db.collection.findFirst({
    where: {
      workspaceId: input.workspaceId,
      name: DEFAULT_COLLECTION_NAME,
      description: DEFAULT_COLLECTION_DESCRIPTION,
    },
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
  });

  if (existing) {
    return existing;
  }

  return db.collection.create({
    data: {
      workspaceId: input.workspaceId,
      name: DEFAULT_COLLECTION_NAME,
      description: DEFAULT_COLLECTION_DESCRIPTION,
      icon: DEFAULT_COLLECTION_ICON,
      color: DEFAULT_COLLECTION_COLOR,
      sortOrder: 0,
    },
  });
}

export async function createCollectionForWorkspace(
  db: CollectionDatabase,
  input: { workspaceId: string; name: string }
): Promise<Collection> {
  const lastCollection = await db.collection.findFirst({
    where: { workspaceId: input.workspaceId },
    orderBy: [{ sortOrder: 'desc' }, { createdAt: 'desc' }],
    select: { sortOrder: true },
  });

  return db.collection.create({
    data: {
      workspaceId: input.workspaceId,
      name: input.name.trim(),
      description: '',
      icon: 'folder',
      color: '#94a3b8',
      sortOrder: nextSortOrder(lastCollection?.sortOrder),
    },
  });
}

export async function ensureWorkspaceCollectionsHydrated(
  db: CollectionDatabase,
  input: { workspaceId: string }
): Promise<{ defaultCollection: Collection; collections: Collection[] }> {
  const defaultCollection = await ensureDefaultCollectionForWorkspace(db, input);

  await db.meeting.updateMany({
    where: {
      workspaceId: input.workspaceId,
      collectionId: null,
    },
    data: {
      collectionId: defaultCollection.id,
    },
  });

  const collections = await db.collection.findMany({
    where: { workspaceId: input.workspaceId },
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
  });

  const normalizedCollections = collections.some(isDefaultCollection)
    ? collections
    : [defaultCollection, ...collections];

  return {
    defaultCollection,
    collections: normalizedCollections,
  };
}
