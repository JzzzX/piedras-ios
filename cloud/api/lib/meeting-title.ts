import type { PromptOptions } from './types';

const SHORT_MEMO_THRESHOLD_SECONDS = 45;
const MAX_TITLE_LENGTH = 18;

const LEADING_PHRASES = [
  '我们今天主要讨论一下',
  '我们今天主要聊一下',
  '今天主要讨论一下',
  '今天主要聊一下',
  '我们今天讨论一下',
  '我们今天聊一下',
  '今天讨论一下',
  '今天聊一下',
  '我们来聊聊',
  '我想聊聊',
  '我们先看一下',
  '我们先聊一下',
  '我们先聊聊',
  '我们先把',
  '先看一下',
  '先聊一下',
  '先聊聊',
  '先把',
  '主要是关于',
  '就是关于',
  '关于',
  '主要聊',
  '讨论',
  '聊一下',
  '聊聊',
  '说一下',
  '想说',
  '就是说',
  '就是',
  '那个',
  '这个',
  '嗯',
  '啊',
];

const TRAILING_PHRASES = ['的安排', '这个安排', '这件事情', '这个事情', '这个问题', '的问题', '一下'];

const LOW_SIGNAL_GENERATED_EXACT = new Set([
  '测试',
  '语音测试',
  '录音测试',
  '会议测试',
  '今天',
  '现在',
  '日期确认',
  '时间确认',
  '效果如何',
  '看看效果',
]);

const LOW_SIGNAL_CANDIDATE_EXACT = new Set([
  '测试',
  '会议测试',
  '今天',
  '现在',
  '日期确认',
  '时间确认',
  '效果如何',
  '看看效果',
]);

export function normalizePromptOptions(input?: Partial<PromptOptions>): PromptOptions {
  return {
    meetingType: input?.meetingType || '通用',
    outputStyle: input?.outputStyle || '平衡',
    includeActionItems: input?.includeActionItems ?? true,
  };
}

export function buildTitleSystemPrompt(meetingType: string): string {
  return `你是一位会议标题生成助手。请根据会议转写内容生成一个简短、清晰、可读的中文会议标题。

要求：
1. 只输出标题本身，不要解释。
2. 长度尽量控制在 8-18 个汉字，理想长度 10-16。
3. 标题必须是议题型短标题，像“录音链路验证与语音测试”这种名词短语，不要写成完整句子。
4. 不要使用书名号、引号、句号等多余标点。
5. 不要把日期、时间、测试口令、口癖或“今天是/现在进行/看一下效果”这类过程性表达写进标题。
6. 避免“会议记录”“语音测试”“进行测试”这类泛词标题，优先提炼真正的讨论主题或验证对象。
7. 当前会议类型：${meetingType}。会议类型只作为理解上下文，不要机械地拼进标题。`;
}

function recordingTitle(dateInput?: string): string {
  const date = dateInput ? new Date(dateInput) : new Date();
  const formatter = new Intl.DateTimeFormat('zh-CN', {
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });

  return `${formatter.format(date)} 录音`;
}

export function sanitizeGeneratedTitle(rawTitle: string): string {
  return rawTitle
    .replace(/[\n\r#>*`]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, MAX_TITLE_LENGTH);
}

function cleanTranscript(transcript: string): string {
  return transcript
    .replace(/\[[^\]]+\]\s*:?/g, ' ')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n');
}

function compactTranscript(transcript: string): string {
  return cleanTranscript(transcript)
    .replace(/[，。！？、,.!?:：；;（）()“”"'‘’·\-\[\]]+/g, ' ')
    .replace(/\s+/g, '')
    .trim();
}

function stripLeadingPhrases(input: string): string {
  let value = input.trim();
  let didStrip = true;

  while (didStrip) {
    didStrip = false;
    for (const phrase of LEADING_PHRASES) {
      if (value.startsWith(phrase)) {
        value = value.slice(phrase.length).trim();
        didStrip = true;
      }
    }
  }

  return value;
}

function stripTrailingPhrases(input: string): string {
  let value = input.trim();
  let didStrip = true;

  while (didStrip) {
    didStrip = false;
    for (const phrase of TRAILING_PHRASES) {
      if (value.endsWith(phrase)) {
        value = value.slice(0, -phrase.length).trim();
        didStrip = true;
      }
    }
  }

  return value;
}

function normalizeCandidateSentence(sentence: string): string {
  let value = sentence
    .replace(/[，。！？、,.!?:：；;（）()“”"'‘’·\-\[\]]+/g, ' ')
    .replace(/\s+/g, '')
    .trim();

  value = value
    .replace(/今天是?\d{2,4}年\d{1,2}月\d{1,2}日/g, '')
    .replace(/\d{2,4}年\d{1,2}月\d{1,2}日/g, '')
    .replace(/现在进行/g, '')
    .replace(/进行语音测试/g, '语音测试')
    .replace(/看一下这个转[写息]的效果如何/g, '转写效果验证')
    .replace(/看一下转[写息]的效果如何/g, '转写效果验证')
    .replace(/看一下效果如何/g, '效果验证')
    .replace(/转[写息]的效果如何/g, '转写效果验证')
    .replace(/这个转[写息]效果验证/g, '转写效果验证')
    .replace(/效果如何/g, '效果验证');

  return stripTrailingPhrases(stripLeadingPhrases(value));
}

function isDateLike(text: string): boolean {
  return /\d{2,4}年\d{1,2}月\d{1,2}日/.test(text) || /\d{1,2}月\d{1,2}日/.test(text);
}

function isLowSignalCandidate(text: string): boolean {
  if (!text || text.length < 4) return true;
  if (LOW_SIGNAL_CANDIDATE_EXACT.has(text)) return true;
  if (isDateLike(text)) return true;
  if (/^(今天|现在|这是|目前)/.test(text)) return true;
  if (/(进行测试|正在测试|测试一下|看一下|效果如何)/.test(text)) return true;
  if (/^[0-9年月日:\- ]+$/.test(text)) return true;
  return false;
}

function buildKeyPhraseTitle(transcript: string): string | null {
  const sentences = cleanTranscript(transcript)
    .split(/[。！？!?；;\n]+/)
    .map((sentence) => normalizeCandidateSentence(sentence))
    .filter((sentence) => !isLowSignalCandidate(sentence))
    .slice(0, 5);

  if (sentences.length >= 2 && /测试/.test(sentences[0]) && /验证/.test(sentences[1])) {
    return sanitizeGeneratedTitle(`${sentences[0]}与${sentences[1]}`);
  }

  if (sentences.length > 0) {
    return sanitizeGeneratedTitle(sentences[0]);
  }

  return null;
}

function isLowInformation(transcript: string): boolean {
  const finalSegments = cleanTranscript(transcript)
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);

  return finalSegments.length < 2 || compactTranscript(transcript).length < 12;
}

export function shouldRejectGeneratedTitle(rawTitle: string): boolean {
  const title = sanitizeGeneratedTitle(rawTitle);
  if (!title) return true;
  if (LOW_SIGNAL_GENERATED_EXACT.has(title)) return true;
  if (isLowSignalCandidate(title)) return true;
  if (/。|！|？/.test(title)) return true;
  if (title.includes('会议于')) return true;
  return false;
}

export function buildHeuristicTitle(
  transcript: string,
  durationSeconds?: number,
  meetingDate?: string
): string {
  const keyPhrase = buildKeyPhraseTitle(transcript);
  if (keyPhrase) {
    return keyPhrase;
  }

  if ((durationSeconds || 0) > 0 && (durationSeconds || 0) <= SHORT_MEMO_THRESHOLD_SECONDS) {
    const minutes = Math.floor((durationSeconds || 0) / 60)
      .toString()
      .padStart(2, '0');
    const seconds = Math.floor((durationSeconds || 0) % 60)
      .toString()
      .padStart(2, '0');
    return `语音备忘 ${minutes}:${seconds}`;
  }

  if (isLowInformation(transcript)) {
    return recordingTitle(meetingDate);
  }

  return recordingTitle(meetingDate);
}
