import assert from 'node:assert/strict';
import test from 'node:test';

import {
  DEFAULT_LLM_SETTINGS,
  OPENAI_COMPATIBLE_PRESETS,
  applyOpenAIPreset,
} from './llm-config.ts';

test('AiHubMix preset defaults to gemini-3-flash-preview', () => {
  assert.equal(OPENAI_COMPATIBLE_PRESETS.aihubmix.defaultModel, 'gemini-3-flash-preview');
  assert.equal(DEFAULT_LLM_SETTINGS.openaiModel, 'gemini-3-flash-preview');
});

test('applyOpenAIPreset uses the new AiHubMix default model', () => {
  const config = applyOpenAIPreset('aihubmix', 'test-key');

  assert.equal(config.openaiModel, 'gemini-3-flash-preview');
  assert.equal(config.openaiBaseUrl, 'https://aihubmix.com/v1');
  assert.equal(config.openaiPath, '/chat/completions');
});
