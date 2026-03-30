const assert = require('node:assert/strict');
const test = require('node:test');

const {
  createStartupBootstrapController,
  getStartupBootstrapSnapshotForTests,
  resetStartupBootstrapStateForTests,
} = require('./startup-bootstrap-controller.cjs');

test('startup bootstrap controller marks failure and schedules retry when bootstrap throws', async () => {
  resetStartupBootstrapStateForTests();

  const scheduled = [];
  const controller = createStartupBootstrapController({
    bootstrap: async () => {
      throw new Error('database offline');
    },
    retryDelayMS: 4_000,
    setTimeoutFn: (callback, delay) => {
      scheduled.push({ callback, delay });
      return { delay };
    },
    clearTimeoutFn: () => {},
    now: () => new Date('2026-03-30T06:00:00.000Z'),
  });

  await controller.start();

  const snapshot = getStartupBootstrapSnapshotForTests();
  assert.equal(snapshot.ready, false);
  assert.equal(snapshot.status, 'failed');
  assert.equal(snapshot.lastError, 'database offline');
  assert.equal(snapshot.attempts, 1);
  assert.equal(snapshot.retryScheduled, true);
  assert.equal(scheduled.length, 1);
  assert.equal(scheduled[0].delay, 4_000);
});

test('startup bootstrap controller marks ready after a successful retry', async () => {
  resetStartupBootstrapStateForTests();

  let attempt = 0;
  let scheduledRetry = null;
  const controller = createStartupBootstrapController({
    bootstrap: async () => {
      attempt += 1;
      if (attempt === 1) {
        throw new Error('database offline');
      }

      return {
        schemaStatus: {
          ready: true,
          missingItems: [],
        },
        legacyUsers: [{ email: 'legacy-main@piedras.local' }],
      };
    },
    retryDelayMS: 1_000,
    setTimeoutFn: (callback) => {
      scheduledRetry = callback;
      return callback;
    },
    clearTimeoutFn: () => {},
    now: () => new Date('2026-03-30T06:00:00.000Z'),
  });

  await controller.start();
  await scheduledRetry();

  const snapshot = getStartupBootstrapSnapshotForTests();
  assert.equal(snapshot.ready, true);
  assert.equal(snapshot.status, 'ready');
  assert.equal(snapshot.lastError, null);
  assert.equal(snapshot.schemaReady, true);
  assert.deepEqual(snapshot.missingItems, []);
  assert.deepEqual(snapshot.legacyUsers, ['legacy-main@piedras.local']);
  assert.equal(snapshot.retryScheduled, false);
  assert.equal(snapshot.attempts, 2);
});
