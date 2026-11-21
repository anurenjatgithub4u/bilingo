// Runs one snippet of generated code and posts back what it printed.
const { parentPort, workerData } = require('node:worker_threads');
const util = require('node:util');
const vm = require('node:vm');

function oneLine(text) {
  return text.trim().split(/\s+/).join(' ').replaceAll('[ ', '[').replaceAll(' ]', ']');
}

async function runPython(code) {
  const { loadPyodide } = require('pyodide');
  const out = [];
  const pyodide = await loadPyodide({ stdout: (l) => out.push(l), stderr: () => {} });
  await pyodide.runPythonAsync(code);
  return out.join(' ');
}

async function runJavaScript(code) {
  const out = [];
  const timers = [];
  // Only what the questions need: no require, process or network.
  const sandbox = {
    console: { log: (...a) => out.push(a.map((v) => (typeof v === 'string' ? v : util.inspect(v))).join(' ')) },
    setTimeout: (f) => timers.push(f),
  };
  vm.runInNewContext(code, sandbox, { timeout: 5000 });
  // Promises first, as in a real event loop, then timers in order.
  await new Promise((r) => setImmediate(r));
  for (const t of timers) {
    t();
    await new Promise((r) => setImmediate(r));
  }
  return out.join(' ');
}

(async () => {
  try {
    const { subject, code } = workerData;
    const out = subject === 'python' ? await runPython(code) : await runJavaScript(code);
    parentPort.postMessage(oneLine(out));
  } catch {
    parentPort.postMessage('Error');
  }
})();
