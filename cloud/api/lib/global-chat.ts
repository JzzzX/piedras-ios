import { Prisma } from '@prisma/client';
import { prisma } from './db';

export interface GlobalChatFilters {
  dateFrom?: string;
  dateTo?: string;
  collectionId?: string;
  workspaceId?: string;
}

export interface GlobalKnowledgeSource {
  ref: string;
  type: 'meeting' | 'asset';
  meetingId?: string;
  assetId?: string;
  title: string;
  date: string;
  score: number;
  snippets: string[];
}

export interface GlobalRetrievalResult {
  sources: GlobalKnowledgeSource[];
  context: string;
}

interface MeetingCandidate {
  meetingId: string;
  title: string;
  date: string;
  userNotes: string;
  enhancedNotes: string;
  segmentsText: string;
}

interface AssetCandidate {
  assetId: string;
  title: string;
  date: string;
  assetType: string;
  extractedText: string;
  collectionName: string;
}

const STOP_WORDS = new Set([
  '我们',
  '你们',
  '这个',
  '那个',
  '哪些',
  '什么',
  '一下',
  '关于',
  '请问',
  '帮我',
  '会议',
  '总结',
  '分析',
  '问题',
  '情况',
]);

const VECTOR_DIM = 384;
const vectorCache = new Map<string, Float32Array>();

function splitKeywords(question: string): string[] {
  const matched = question
    .toLowerCase()
    .match(/[a-z0-9]{2,}|[\u4e00-\u9fa5]{2,}/g);

  if (!matched) return [];
  return Array.from(
    new Set(
      matched
        .map((w) => w.trim())
        .filter((w) => w.length >= 2 && !STOP_WORDS.has(w))
    )
  );
}

function parseDateBoundary(value?: string, endOfDay?: boolean): Date | null {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  if (endOfDay) {
    date.setHours(23, 59, 59, 999);
  } else {
    date.setHours(0, 0, 0, 0);
  }
  return date;
}

function compactText(input: string, max = 220): string {
  const text = input.replace(/\s+/g, ' ').trim();
  if (text.length <= max) return text;
  return `${text.slice(0, max)}...`;
}

function hashToken(input: string): number {
  let hash = 2166136261;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash +=
      (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }
  return hash >>> 0;
}

function normalizeVector(vec: Float32Array): Float32Array {
  let norm = 0;
  for (let i = 0; i < vec.length; i++) {
    norm += vec[i] * vec[i];
  }
  const denom = Math.sqrt(norm) || 1;
  for (let i = 0; i < vec.length; i++) {
    vec[i] /= denom;
  }
  return vec;
}

function tokenizeForVector(text: string): string[] {
  const source = text.toLowerCase();
  const tokens: string[] = [];

  const words = source.match(/[a-z0-9]{2,}|[\u4e00-\u9fa5]{2,}/g) || [];
  tokens.push(...words);

  const chars = Array.from(source.replace(/\s+/g, ''));
  for (let i = 0; i < chars.length; i++) {
    tokens.push(chars[i]);
    if (i < chars.length - 1) {
      tokens.push(`${chars[i]}${chars[i + 1]}`);
    }
    if (i < chars.length - 2) {
      tokens.push(`${chars[i]}${chars[i + 1]}${chars[i + 2]}`);
    }
  }

  return tokens;
}

function vectorizeText(text: string): Float32Array {
  const key = text.slice(0, 8000);
  const cached = vectorCache.get(key);
  if (cached) return cached;

  const tokens = tokenizeForVector(key);
  const vec = new Float32Array(VECTOR_DIM);

  for (const token of tokens) {
    const h1 = hashToken(token);
    const h2 = hashToken(`${token}#`);
    const idx = h1 % VECTOR_DIM;
    const sign = h2 % 2 === 0 ? 1 : -1;
    vec[idx] += sign;
  }

  const normalized = normalizeVector(vec);
  vectorCache.set(key, normalized);
  return normalized;
}

function cosineSimilarity(a: Float32Array, b: Float32Array): number {
  let dot = 0;
  for (let i = 0; i < VECTOR_DIM; i++) {
    dot += a[i] * b[i];
  }
  // 本地哈希向量存在负值，映射到 [0, 1]
  return (dot + 1) / 2;
}

function buildSearchableText(candidate: MeetingCandidate): string {
  return [
    candidate.title,
    candidate.enhancedNotes,
    candidate.userNotes,
    candidate.segmentsText.slice(0, 2400),
  ]
    .filter(Boolean)
    .join('\n');
}

function buildAssetSearchableText(candidate: AssetCandidate): string {
  return [candidate.title, candidate.collectionName, candidate.extractedText]
    .filter(Boolean)
    .join('\n');
}

function scoreByKeywords(candidate: MeetingCandidate, keywords: string[]): number {
  if (keywords.length === 0) return 0;

  const titleText = candidate.title.toLowerCase();
  const notesText = candidate.userNotes.toLowerCase();
  const enhancedText = candidate.enhancedNotes.toLowerCase();
  const transcriptText = candidate.segmentsText.toLowerCase();

  let total = 0;
  const maxPerKeyword = 1.6;
  for (const kw of keywords) {
    let kwScore = 0;
    if (titleText.includes(kw)) kwScore += 0.8;
    if (enhancedText.includes(kw)) kwScore += 0.5;
    if (notesText.includes(kw)) kwScore += 0.35;
    if (transcriptText.includes(kw)) kwScore += 0.25;
    total += Math.min(kwScore, maxPerKeyword);
  }

  return total / (keywords.length * maxPerKeyword);
}

function scoreAssetByKeywords(candidate: AssetCandidate, keywords: string[]): number {
  if (keywords.length === 0) return 0;

  const titleText = candidate.title.toLowerCase();
  const bodyText = candidate.extractedText.toLowerCase();
  const collectionText = candidate.collectionName.toLowerCase();

  let total = 0;
  for (const kw of keywords) {
    let kwScore = 0;
    if (titleText.includes(kw)) kwScore += 0.8;
    if (collectionText.includes(kw)) kwScore += 0.35;
    if (bodyText.includes(kw)) kwScore += 0.55;
    total += Math.min(kwScore, 1.6);
  }

  return total / (keywords.length * 1.6);
}

function pickSnippets(
  candidate: MeetingCandidate,
  queryVector: Float32Array,
  keywords: string[]
): string[] {
  const lines = [
    ...candidate.enhancedNotes.split(/\r?\n/),
    ...candidate.userNotes.split(/\r?\n/),
    ...candidate.segmentsText.split(/[。！？\n]/),
  ]
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(0, 80);

  const byKeyword = lines
    .filter((line) => keywords.some((kw) => line.toLowerCase().includes(kw)))
    .slice(0, 3)
    .map((line) => compactText(line));

  if (byKeyword.length > 0) return byKeyword;

  const rankedByVector = lines
    .map((line) => ({
      line,
      score: cosineSimilarity(queryVector, vectorizeText(line)),
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, 3)
    .map((item) => compactText(item.line));

  if (rankedByVector.length > 0) return rankedByVector;

  const fallback = [
    compactText(candidate.title, 80),
    compactText(candidate.enhancedNotes, 180),
    compactText(candidate.userNotes, 180),
    compactText(candidate.segmentsText, 180),
  ].filter((v) => v && v !== '...');

  return fallback.slice(0, 2);
}

function pickAssetSnippets(
  candidate: AssetCandidate,
  queryVector: Float32Array,
  keywords: string[]
): string[] {
  const lines = candidate.extractedText
    .split(/\r?\n|[。！？]/)
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(0, 80);

  const byKeyword = lines
    .filter((line) => keywords.some((kw) => line.toLowerCase().includes(kw)))
    .slice(0, 3)
    .map((line) => compactText(line));

  if (byKeyword.length > 0) return byKeyword;

  const rankedByVector = lines
    .map((line) => ({
      line,
      score: cosineSimilarity(queryVector, vectorizeText(line)),
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, 3)
    .map((item) => compactText(item.line));

  if (rankedByVector.length > 0) return rankedByVector;

  return [compactText(candidate.extractedText, 180)].filter(Boolean);
}

function buildWhere(filters: GlobalChatFilters): Prisma.MeetingWhereInput {
  const where: Prisma.MeetingWhereInput = {};

  const from = parseDateBoundary(filters.dateFrom, false);
  const to = parseDateBoundary(filters.dateTo, true);
  if (from || to) {
    const dateFilter: Prisma.DateTimeFilter = {};
    if (from) dateFilter.gte = from;
    if (to) dateFilter.lte = to;
    where.date = dateFilter;
  }

  if (filters.collectionId) {
    where.collectionId = filters.collectionId === '__ungrouped' ? null : filters.collectionId;
  }

  if (filters.workspaceId) {
    where.workspaceId = filters.workspaceId;
  }

  return where;
}

function buildAssetWhere(filters: GlobalChatFilters): Prisma.WorkspaceAssetWhereInput {
  const where: Prisma.WorkspaceAssetWhereInput = {};

  const from = parseDateBoundary(filters.dateFrom, false);
  const to = parseDateBoundary(filters.dateTo, true);
  if (from || to) {
    const createdAtFilter: Prisma.DateTimeFilter = {};
    if (from) createdAtFilter.gte = from;
    if (to) createdAtFilter.lte = to;
    where.createdAt = createdAtFilter;
  }

  if (filters.collectionId) {
    where.collectionId = filters.collectionId === '__ungrouped' ? null : filters.collectionId;
  }

  if (filters.workspaceId) {
    where.workspaceId = filters.workspaceId;
  }

  return where;
}

export async function retrieveGlobalMeetingContext(
  question: string,
  filters: GlobalChatFilters
): Promise<GlobalRetrievalResult> {
  const q = question.trim();
  const keywords = splitKeywords(q);
  const meetingWhere = buildWhere(filters);
  const assetWhere = buildAssetWhere(filters);

  const meetings = await prisma.meeting.findMany({
    where: meetingWhere,
    orderBy: { date: 'desc' },
    take: 80,
    select: {
      id: true,
      title: true,
      date: true,
      userNotes: true,
      enhancedNotes: true,
      segments: {
        orderBy: { order: 'asc' },
        select: { text: true, isFinal: true },
      },
    },
  });

  const assets = await prisma.workspaceAsset.findMany({
    // 资料库当前为预览模式，不参与 AI 检索。
    where: {
      ...assetWhere,
      id: '__asset_preview_mode_disabled__',
    },
    orderBy: { updatedAt: 'desc' },
    take: 80,
    select: {
      id: true,
      name: true,
      assetType: true,
      extractedText: true,
      createdAt: true,
      collection: {
        select: { name: true },
      },
    },
  });

  const queryVector = vectorizeText(q);

  const rankedMeetings = meetings
    .map((meeting) => {
      const candidate: MeetingCandidate = {
        meetingId: meeting.id,
        title: (meeting.title || '').trim() || '未命名会议',
        date: meeting.date.toISOString(),
        userNotes: (meeting.userNotes || '').trim(),
        enhancedNotes: (meeting.enhancedNotes || '').trim(),
        segmentsText: meeting.segments
          .filter((s) => s.isFinal)
          .map((s) => s.text)
          .join(' '),
      };

      const searchableText = buildSearchableText(candidate);
      const vectorScore = cosineSimilarity(queryVector, vectorizeText(searchableText));
      const keywordScore = scoreByKeywords(candidate, keywords);

      const hybridScore =
        keywords.length > 0 ? vectorScore * 0.45 + keywordScore * 0.55 : vectorScore;

      const snippets = pickSnippets(candidate, queryVector, keywords);

      return {
        type: 'meeting' as const,
        meetingId: candidate.meetingId,
        title: candidate.title,
        date: candidate.date,
        score: Number(hybridScore.toFixed(6)),
        vectorScore,
        keywordScore,
        snippets,
      };
    })
    .sort((a, b) => b.score - a.score || b.date.localeCompare(a.date));

  const rankedAssets = assets
    .map((asset) => {
      const candidate: AssetCandidate = {
        assetId: asset.id,
        title: (asset.name || '').trim() || '未命名资料',
        date: asset.createdAt.toISOString(),
        assetType: asset.assetType,
        extractedText: (asset.extractedText || '').trim(),
        collectionName: asset.collection?.name || '工作区共享',
      };

      const searchableText = buildAssetSearchableText(candidate);
      const vectorScore = cosineSimilarity(queryVector, vectorizeText(searchableText));
      const keywordScore = scoreAssetByKeywords(candidate, keywords);
      const hybridScore =
        keywords.length > 0 ? vectorScore * 0.45 + keywordScore * 0.55 : vectorScore;
      const snippets = pickAssetSnippets(candidate, queryVector, keywords);

      return {
        type: 'asset' as const,
        assetId: candidate.assetId,
        title: candidate.title,
        date: candidate.date,
        score: Number(hybridScore.toFixed(6)),
        vectorScore,
        keywordScore,
        snippets,
      };
    })
    .filter((asset) => asset.snippets.length > 0)
    .sort((a, b) => b.score - a.score || b.date.localeCompare(a.date));

  const ranked = [...rankedMeetings, ...rankedAssets].sort(
    (a, b) => b.score - a.score || b.date.localeCompare(a.date)
  );

  const selected = ranked.filter((m) => m.score > 0.15).slice(0, 5);
  const fallback = ranked.slice(0, 3);
  const used = selected.length > 0 ? selected : fallback;

  const sources: GlobalKnowledgeSource[] = used.map((m, idx) => ({
    ref: `S${idx + 1}`,
    type: m.type,
    ...(m.type === 'meeting' ? { meetingId: m.meetingId } : { assetId: m.assetId }),
    title: m.title,
    date: m.date,
    score: m.score,
    snippets: m.snippets,
  }));

  const context = sources
    .map((s) => {
      const dateText = new Date(s.date).toLocaleString('zh-CN', { hour12: false });
      const snippetText = s.snippets.map((line) => `- ${line}`).join('\n');
      const typeLabel = s.type === 'meeting' ? '会议' : '资料';
      return `[${s.ref}] ${typeLabel}：${s.title}（${dateText}）\n${snippetText}`;
    })
    .join('\n\n');

  return { sources, context };
}
