// workspace/changes 事件摘要回归（v3.2.14 改动审阅）。
//
// App 只靠这一条事件知道「本轮有改动，去 /api/changes/summary 拉摘要」，所以事件里
// 必须保留 type + seq，并透传轮号；宿主没给 data 时也不能抛（否则整条事件流断掉）。
//
// 运行：node --test test/changes-event.test.mjs
// 注意：lib/index.js 顶层 import 了宿主服务包（schemastery / dsh-llm / …）。在没有完整
// dsh profile 的机器上导入会失败——此时整组用例 skip 并打印原因，而不是伪装成通过。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
let mod = null;
let skip = false;
try {
  mod = await import(pathToFileURL(join(here, '..', 'lib', 'index.js')).href);
} catch (error) {
  skip = `插件依赖不可用（${error?.code ?? 'import-failed'}）：${error?.message ?? error}`;
}

test('workspace/changes 透传轮号与 seq', { skip }, () => {
  const summary = mod.summarizeEvent({ seq: 42, type: 'workspace/changes', data: { turn: 7 } });
  assert.equal(summary.type, 'workspace/changes');
  assert.equal(summary.seq, 42);
  assert.deepEqual(summary.data, { turn: 7 });
});

test('缺 data / 坏轮号时不抛，也不造轮号', { skip }, () => {
  const missing = mod.summarizeEvent({ seq: 43, type: 'workspace/changes' });
  assert.equal(missing.seq, 43);
  assert.equal(missing.data, undefined);

  const bad = mod.summarizeEvent({ seq: 44, type: 'workspace/changes', data: { turn: 'x' } });
  assert.deepEqual(bad.data, {});
});

test('改动事件进入时间线（不被 REPLAY_IGNORED_TYPES 吞掉）', { skip }, () => {
  assert.equal(mod.isTimelineRecord({ seq: 45, type: 'workspace/changes', data: { turn: 1 } }), true);
});
