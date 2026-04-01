import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AIHUBMIX_PRESETS,
  DEFAULT_LLM_SETTINGS,
  applyLlmPreset,
} from './llm-config.ts';

test('AiHubMix preset defaults to gemini-3-flash-preview', () => {
  assert.equal(AIHUBMIX_PRESETS.aihubmix.defaultModel, 'gemini-3-flash-preview');
  assert.equal(DEFAULT_LLM_SETTINGS.model, 'gemini-3-flash-preview');
});

test('applyLlmPreset uses the AiHubMix default model', () => {
  const config = applyLlmPreset('aihubmix', 'test-key');

  assert.equal(config.model, 'gemini-3-flash-preview');
  assert.equal(config.baseUrl, 'https://aihubmix.com/v1');
  assert.equal(config.path, '/chat/completions');
});
