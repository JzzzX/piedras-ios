import type { Collection, Prisma, PrismaClient } from '@prisma/client';

const DEFAULT_COLLECTION_NAME = 'Default Folder';
export const DEFAULT_COLLECTION_DESCRIPTION = '椰子面试默认笔记文件夹';
const DEFAULT_COLLECTION_ICON = 'tray.full';
const DEFAULT_COLLECTION_COLOR = '#0f766e';
const RECENTLY_DELETED_COLLECTION_NAME = 'Recently Deleted';
export const RECENTLY_DELETED_COLLECTION_DESCRIPTION = '椰子面试最近删除文件夹';
const RECENTLY_DELETED_COLLECTION_ICON = 'trash';
const RECENTLY_DELETED_COLLECTION_COLOR = '#9f1239';
const RECENTLY_DELETED_COLLECTION_SORT_ORDER = 999;

type CollectionDatabase = PrismaClient | Prisma.TransactionClient;

interface SerializedCollection {
  id: string;
  name: string;
  isDefault: boolean;
  isRecentlyDeleted: boolean;
}

function nextSortOrder(lastSortOrder: number | null | undefined) {
  return (lastSortOrder ?? 0) + 1;
}

function needsDefaultCollectionNormalization(
  collection: Pick<Collection, 'name' | 'description' | 'icon' | 'color' | 'sortOrder'>
) {
  return (
    collection.name !== DEFAULT_COLLECTION_NAME
    || collection.description !== DEFAULT_COLLECTION_DESCRIPTION
    || collection.icon !== DEFAULT_COLLECTION_ICON
    || collection.color !== DEFAULT_COLLECTION_COLOR
    || collection.sortOrder !== 0
  );
}

export function serializeCollection(
  collection: Pick<Collection, 'id' | 'name'>,
  defaultCollectionID: string,
  recentlyDeletedCollectionID: string
): SerializedCollection {
  return {
    id: collection.id,
    name: collection.name,
    isDefault: collection.id == defaultCollectionID,
    isRecentlyDeleted: collection.id == recentlyDeletedCollectionID,
  };
}

export async function ensureDefaultCollectionForWorkspace(
  db: CollectionDatabase,
  input: { workspaceId: string }
): Promise<Collection> {
  const existing = await db.collection.findFirst({
    where: {
      workspaceId: input.workspaceId,
      description: DEFAULT_COLLECTION_DESCRIPTION,
    },
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
  });

  if (existing) {
    if (!needsDefaultCollectionNormalization(existing)) {
      return existing;
    }

    return db.collection.update({
      where: { id: existing.id },
      data: {
        name: DEFAULT_COLLECTION_NAME,
        description: DEFAULT_COLLECTION_DESCRIPTION,
        icon: DEFAULT_COLLECTION_ICON,
        color: DEFAULT_COLLECTION_COLOR,
        sortOrder: 0,
      },
    });
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

export async function ensureRecentlyDeletedCollectionForWorkspace(
  db: CollectionDatabase,
  input: { workspaceId: string }
): Promise<Collection> {
  const existing = await db.collection.findFirst({
    where: {
      workspaceId: input.workspaceId,
      description: RECENTLY_DELETED_COLLECTION_DESCRIPTION,
    },
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
  });

  if (existing) {
    if (
      existing.name === RECENTLY_DELETED_COLLECTION_NAME
      && existing.description === RECENTLY_DELETED_COLLECTION_DESCRIPTION
      && existing.icon === RECENTLY_DELETED_COLLECTION_ICON
      && existing.color === RECENTLY_DELETED_COLLECTION_COLOR
      && existing.sortOrder === RECENTLY_DELETED_COLLECTION_SORT_ORDER
    ) {
      return existing;
    }

    return db.collection.update({
      where: { id: existing.id },
      data: {
        name: RECENTLY_DELETED_COLLECTION_NAME,
        description: RECENTLY_DELETED_COLLECTION_DESCRIPTION,
        icon: RECENTLY_DELETED_COLLECTION_ICON,
        color: RECENTLY_DELETED_COLLECTION_COLOR,
        sortOrder: RECENTLY_DELETED_COLLECTION_SORT_ORDER,
      },
    });
  }

  return db.collection.create({
    data: {
      workspaceId: input.workspaceId,
      name: RECENTLY_DELETED_COLLECTION_NAME,
      description: RECENTLY_DELETED_COLLECTION_DESCRIPTION,
      icon: RECENTLY_DELETED_COLLECTION_ICON,
      color: RECENTLY_DELETED_COLLECTION_COLOR,
      sortOrder: RECENTLY_DELETED_COLLECTION_SORT_ORDER,
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
): Promise<{ defaultCollection: Collection; recentlyDeletedCollection: Collection; collections: Collection[] }> {
  const defaultCollection = await ensureDefaultCollectionForWorkspace(db, input);
  const recentlyDeletedCollection = await ensureRecentlyDeletedCollectionForWorkspace(db, input);

  await db.meeting.updateMany({
    where: {
      workspaceId: input.workspaceId,
      collectionId: null,
      deletedAt: null,
    },
    data: {
      collectionId: defaultCollection.id,
    },
  });

  const collections = await db.collection.findMany({
    where: { workspaceId: input.workspaceId },
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
  });

  const normalizedCollections = collections.some((collection) => collection.id === defaultCollection.id)
    ? collections.map((collection) => (collection.id === defaultCollection.id ? defaultCollection : collection))
    : [defaultCollection, ...collections];

  return {
    defaultCollection,
    recentlyDeletedCollection,
    collections: normalizedCollections,
  };
}

export async function deleteCollectionForWorkspace(
  db: CollectionDatabase,
  input: { workspaceId: string; collectionId: string }
): Promise<{
  deletedCollectionId: string;
  reassignedMeetingCount: number;
  reassignedWorkspaceAssetCount: number;
  repairedPreviousCollectionCount: number;
}> {
  const defaultCollection = await ensureDefaultCollectionForWorkspace(db, { workspaceId: input.workspaceId });
  const recentlyDeletedCollection = await ensureRecentlyDeletedCollectionForWorkspace(db, {
    workspaceId: input.workspaceId,
  });

  if (input.collectionId === defaultCollection.id || input.collectionId === recentlyDeletedCollection.id) {
    throw new Error('Cannot delete a system collection');
  }

  const collection = await db.collection.findUnique({
    where: { id: input.collectionId },
  });

  if (!collection || collection.workspaceId !== input.workspaceId) {
    throw new Error('Collection not found');
  }

  const reassignedMeetings = await db.meeting.updateMany({
    where: {
      workspaceId: input.workspaceId,
      collectionId: input.collectionId,
      deletedAt: null,
    },
    data: {
      collectionId: defaultCollection.id,
    },
  });

  const repairedPreviousCollection = await db.meeting.updateMany({
    where: {
      workspaceId: input.workspaceId,
      previousCollectionId: input.collectionId,
      deletedAt: { not: null },
    },
    data: {
      previousCollectionId: defaultCollection.id,
    },
  });

  const reassignedWorkspaceAssets = await db.workspaceAsset.updateMany({
    where: {
      workspaceId: input.workspaceId,
      collectionId: input.collectionId,
    },
    data: {
      collectionId: defaultCollection.id,
    },
  });

  await db.collection.delete({
    where: { id: input.collectionId },
  });

  return {
    deletedCollectionId: input.collectionId,
    reassignedMeetingCount: reassignedMeetings.count,
    reassignedWorkspaceAssetCount: reassignedWorkspaceAssets.count,
    repairedPreviousCollectionCount: repairedPreviousCollection.count,
  };
}
