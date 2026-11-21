const test = require('node:test');
const assert = require('node:assert');
const { runCode, verifyItems } = require('./verify');

const output = (subject, code, right, wrong = ['x1', 'x2', 'x3']) => ({
  subject,
  difficulty: 1,
  kind: 'What does this print?',
  prompt: 'What is the output?',
  code,
  check: 'output',
  options: [right, ...wrong],
  answer: 0,
  explanation: 'Because.',
});

test('runs Python and JavaScript and reports errors', async () => {
  assert.equal(await runCode('python', 'print(2 + 3)'), '5');
  assert.equal(await runCode('python', 'print([1, 2])'), '[1, 2]');
  assert.equal(await runCode('python', 'print(1 / 0)'), 'Error');
  assert.equal(await runCode('javascript', 'console.log(2 + 3)'), '5');
  assert.equal(await runCode('javascript', 'console.log([4, 6])'), '[4, 6]');
  assert.equal(await runCode('javascript', 'nope()'), 'Error');
  assert.equal(
    await runCode('javascript', 'console.log("a");setTimeout(()=>console.log("b"),0);Promise.resolve().then(()=>console.log("c"));console.log("d")'),
    'a d c b',
  );
});

test('generated code cannot reach the key, modules or run forever', async () => {
  process.env.OPENAI_API_KEY = 'secret';
  assert.equal(await runCode('javascript', 'console.log(typeof process, typeof require)'), 'undefined undefined');
  assert.equal(await runCode('javascript', 'while (true) {}', 8000), 'Error');
  delete process.env.OPENAI_API_KEY;
});

test('a wrong answer is rejected and a right one published', async () => {
  const { good, rejected } = await verifyItems(
    [
      output('python', 'print(2 + 2)', '4'),
      output('python', 'print(2 + 2)', '5'),
      output('python', 'print(3 + 3)', '7'),
    ],
    'python',
    1,
  );
  assert.equal(good.length, 1);
  assert.equal(good[0].check, undefined);
  assert.equal(rejected.length, 2);
  assert.match(rejected[1].problem, /prints 6/);
});

test('blank, bug and order forms are proved too', async () => {
  const base = { subject: 'python', difficulty: 1, explanation: 'Because.', prompt: 'p', kind: 'k' };
  const { good, rejected } = await verifyItems(
    [
      { ...base, check: 'blank', code: '___(1)', expected: '1', options: ['print', 'echo', 'log', 'say'], answer: 0 },
      { ...base, check: 'blank', code: '___(2)', expected: '2', options: ['echo', 'print', 'log', 'say'], answer: 0 },
      { ...base, check: 'bug', code: 'print(1', fixed: 'print(1)', expected: '1', options: ['Line 1', 'Line 2', 'Line 3', 'Line 4'], answer: 0 },
      { ...base, check: 'bug', code: 'print(3)', fixed: 'print(3)', expected: '3', options: ['Line 1', 'Line 2', 'Line 3', 'Line 4'], answer: 0 },
      { ...base, lines: ['x = 1', 'y = 2', 'print(x + y)'], expected: '3', options: [], answer: 0 },
      { ...base, lines: ['print(x)', 'x = 1', 'y = 2'], expected: '1', options: [], answer: 0 },
    ],
    'python',
    1,
  );
  assert.deepEqual(good.length, 3);
  assert.equal(rejected.length, 3);
});

test('malformed language questions are rejected', async () => {
  const base = { subject: 'de', difficulty: 1, kind: 'Grammar', prompt: 'Ich helfe ___ Mann.', explanation: 'Dativ.' };
  const { good, rejected } = await verifyItems(
    [
      { ...base, options: ['dem', 'den', 'der', 'das'], answer: 0 },
      { ...base, prompt: 'a', options: ['dem', 'dem', 'der', 'das'], answer: 0 },
      { ...base, prompt: 'b', options: ['dem', 'den', 'der', 'das'], answer: 7 },
      { ...base, difficulty: 3, prompt: 'c', options: ['dem', 'den', 'der', 'das'], answer: 0 },
    ],
    'de',
    1,
  );
  assert.equal(good.length, 1);
  assert.equal(rejected.length, 3);
});
