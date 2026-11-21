// Checks AI-generated content before anyone sees it. Coding answers are proved
// by running the code in a worker with no access to the API key or network
// modules: Python through Pyodide (WebAssembly), JavaScript through Node's vm.
const { Worker } = require('node:worker_threads');
const path = require('node:path');

const MAX_LINES = 12;
const MAX_LINE_WIDTH = 44;

/** Runs code and returns its output on one line, or 'Error' if it fails. */
function runCode(subject, code, timeoutMs = 20000) {
  return new Promise((resolve) => {
    const worker = new Worker(path.join(__dirname, 'run_worker.js'), {
      workerData: { subject, code },
      // Generated code must never see the OpenAI key.
      env: {},
    });
    const timer = setTimeout(() => {
      worker.terminate();
      resolve('Error');
    }, timeoutMs);
    worker.once('message', (out) => {
      clearTimeout(timer);
      worker.terminate();
      resolve(out);
    });
    worker.once('error', () => {
      clearTimeout(timer);
      resolve('Error');
    });
  });
}

/** Spacing and quote style differ between languages and answer writers. */
function same(a, b) {
  const clean = (s) => String(s).replace(/['"\s]/g, '');
  return clean(a) === clean(b);
}

/** Shape rules every item must meet. Returns a reason, or null if fine. */
function shapeProblem(item, subject, difficulty) {
  if (item.subject !== subject) return 'wrong subject';
  if (item.difficulty !== difficulty) return 'wrong difficulty';
  if (typeof item.prompt !== 'string' || !item.prompt.trim()) return 'no prompt';
  if (typeof item.kind !== 'string' || !item.kind.trim()) return 'no kind';
  const code = item.code ?? item.lines?.join('\n');
  if (code) {
    const lines = code.split('\n');
    if (lines.length > MAX_LINES) return 'too many lines';
    if (lines.some((l) => l.length > MAX_LINE_WIDTH)) return 'line too wide';
  }
  if (item.lines?.length) return item.lines.length >= 3 ? null : 'too few lines';
  const options = item.options;
  if (!Array.isArray(options) || options.length !== 4) return 'needs 4 options';
  if (new Set(options).size !== 4) return 'repeated option';
  if (options.some((o) => typeof o !== 'string' || !o.trim())) return 'empty option';
  if (!Number.isInteger(item.answer) || item.answer < 0 || item.answer > 3) {
    return 'bad answer index';
  }
  if (!item.explanation?.trim()) return 'no explanation';
  return null;
}

/** Proves a coding item's answer by running it. Returns a reason, or null. */
async function codeProblem(item) {
  const { subject } = item;
  if (item.lines?.length) {
    const out = await runCode(subject, item.lines.join('\n'));
    if (out === 'Error') return 'lines do not run';
    return same(out, item.expected) ? null : `lines print ${out}`;
  }
  const right = item.options[item.answer];
  if (item.check === 'output') {
    const out = await runCode(subject, item.code);
    return same(out, right) ? null : `prints ${out}, answer says ${right}`;
  }
  if (item.check === 'blank') {
    if (!item.code.includes('___')) return 'no blank';
    const out = await runCode(subject, item.code.replaceAll('___', right));
    return same(out, item.expected) ? null : `filled code prints ${out}`;
  }
  if (item.check === 'bug') {
    const broken = await runCode(subject, item.code);
    const fixed = await runCode(subject, item.fixed);
    if (!same(fixed, item.expected)) return `fixed code prints ${fixed}`;
    return same(broken, item.expected) ? 'the "bug" gives the right output' : null;
  }
  return 'unknown check';
}

/** The item as phones receive it, without the checking fields. */
function publishable(item) {
  const out = { ...item };
  delete out.check;
  delete out.expected;
  delete out.fixed;
  return out;
}

/** Splits items into those that passed and those that failed, with reasons. */
async function verifyItems(items, subject, difficulty) {
  const good = [];
  const rejected = [];
  const coding = subject === 'python' || subject === 'javascript';
  const seen = new Set();
  for (const item of items) {
    let problem = shapeProblem(item, subject, difficulty);
    const key = item.code ?? item.lines?.join('\n') ?? item.prompt;
    if (!problem && seen.has(key)) problem = 'duplicate';
    if (!problem && coding) problem = await codeProblem(item);
    seen.add(key);
    if (problem) {
      rejected.push({ item, problem });
    } else {
      good.push(publishable(item));
    }
  }
  return { good, rejected };
}

module.exports = { runCode, same, shapeProblem, codeProblem, verifyItems, publishable };
