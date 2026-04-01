export interface TranscriptSegment {
  id: string;
  speaker: string;
  text: string;
  startTime: number;
  endTime: number;
  isFinal: boolean;
}

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: number;
  recipeId?: string;
  templateId?: string;
}

export type RecipeSurface = 'chat' | 'meeting' | 'both';

export type LlmSelection = 'aihubmix';
export type LlmPreset = 'aihubmix' | 'custom';

export interface LlmSettings {
  provider: LlmSelection;
  preset: LlmPreset;
  apiKey: string;
  model: string;
  baseUrl: string;
  path: string;
}

export type LlmRuntimeConfig =
  | { provider: 'aihubmix'; apiKey?: string; model?: string; baseUrl?: string; path?: string }
  | undefined;

export type MeetingType =
  | '通用'
  | '访谈'
  | '演讲'
  | '头脑风暴'
  | '项目周会'
  | '需求评审'
  | '销售沟通'
  | '面试复盘';

export type OutputStyle = '简洁' | '平衡' | '详细' | '行动导向';

export interface PromptOptions {
  meetingType: MeetingType;
  outputStyle: OutputStyle;
  includeActionItems: boolean;
}

export interface RecordingOptions {
  autoStopEnabled: boolean;
  autoStopMinutes: number;
}

export interface Workspace {
  id: string;
  name: string;
  description: string;
  icon: string;
  color: string;
  workflowMode: WorkspaceWorkflowMode;
  modeLabel: string;
  sortOrder: number;
}

export interface WorkspaceOverviewItem extends Workspace {
  meetingCount: number;
  latestMeetingAt?: string | null;
}

export type WorkspaceWorkflowMode = 'general' | 'interview';
export type CandidateStatus =
  | 'new'
  | 'screening'
  | 'interviewing'
  | 'offer'
  | 'hold'
  | 'rejected';
export type InterviewRecommendation =
  | 'strong_yes'
  | 'yes'
  | 'mixed'
  | 'no'
  | 'pending';

export type CustomVocabularyScope = 'global' | 'workspace';

export interface AsrVocabularySyncStatus {
  supported: boolean;
  mode: 'browser' | 'aliyun' | 'doubao';
  ready: boolean;
  remoteVocabularyId: string | null;
  lastSyncedAt: string | null;
  lastError: string | null;
  message: string;
}

export interface Collection {
  id: string;
  name: string;
  description: string;
  icon: string;
  color: string;
  handoffSummary: string;
  candidateStatus: CandidateStatus;
  nextInterviewer: string;
  nextFocus: string;
  sortOrder: number;
  workspaceId?: string;
  createdAt?: string;
  updatedAt?: string;
}

export type WorkspaceAssetType = 'pdf' | 'image';
export type WorkspaceAssetExtractionStatus = 'preview' | 'queued' | 'processing' | 'ready' | 'failed';

export interface WorkspaceAsset {
  id: string;
  name: string;
  originalName: string;
  assetType: WorkspaceAssetType;
  mimeType: string;
  fileSize: number;
  storageKey: string;
  extractedText: string;
  extractionStatus: WorkspaceAssetExtractionStatus;
  extractionError: string;
  workspaceId: string;
  collectionId?: string | null;
  collection?: Pick<Collection, 'id' | 'name' | 'icon' | 'color'> | null;
  createdAt: string;
  updatedAt: string;
}

export type RecipeKind = 'quick' | 'prompt';

export interface Recipe {
  id: string;
  name: string;
  command: string;
  icon: string;
  description: string;
  prompt: string;
  starterQuestion?: string;
  surfaces: RecipeSurface;
  category: string;
  scope?: GlobalChatScope;
  accent?: 'lime' | 'amber' | 'sky' | 'violet';
  isSystem?: boolean;
  sortOrder?: number;
}

export type Template = Recipe;

export type GlobalChatScope = 'my_notes' | 'all_meetings';

export interface GlobalChatFilters {
  dateFrom?: string;
  dateTo?: string;
  collectionId?: string;
}

export interface GlobalChatSessionSummary {
  id: string;
  title: string;
  scope: GlobalChatScope;
  workspaceId: string | null;
  workspace?: Pick<Workspace, 'id' | 'name' | 'icon' | 'color'> | null;
  filters: GlobalChatFilters;
  updatedAt: string;
  createdAt: string;
}

export interface GlobalChatSessionDetail extends GlobalChatSessionSummary {
  messages: ChatMessage[];
}

export interface Meeting {
  id: string;
  title: string;
  date: number;
  status: 'idle' | 'recording' | 'paused' | 'ended';
  segments: TranscriptSegment[];
  userNotes: string;
  enhancedNotes: string;
  audioEnhancedNotes?: string;
  audioEnhancedNotesStatus?: string;
  audioEnhancedNotesError?: string;
  audioEnhancedNotesUpdatedAt?: string | null;
  audioEnhancedNotesProvider?: string | null;
  audioEnhancedNotesModel?: string | null;
  enhanceRecipeId?: string | null;
  roundLabel: string;
  interviewerName: string;
  recommendation: InterviewRecommendation;
  handoffNote: string;
  speakers: Record<string, string>;
  chatMessages: ChatMessage[];
  duration: number;
  audioCloudSyncEnabled?: boolean;
  audioMimeType?: string | null;
  audioDuration?: number | null;
  audioUpdatedAt?: string | null;
  audioUrl?: string | null;
  hasAudio?: boolean;
  noteAttachments?: Array<{
    id: string;
    mimeType: string;
    url: string;
    originalName?: string;
    extractedText?: string;
    createdAt: string;
    updatedAt: string;
  }>;
  noteAttachmentsTextContext?: string;
  audioProcessingState?: 'idle' | 'queued' | 'processing' | 'completed' | 'failed';
  audioProcessingError?: string | null;
  audioProcessingAttempts?: number;
  audioProcessingRequestedAt?: string | null;
  audioProcessingStartedAt?: string | null;
  audioProcessingCompletedAt?: string | null;
}
