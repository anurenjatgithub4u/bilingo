// Weekly job: asks OpenAI for new BiLingo questions, checks every one, and
// publishes those that pass to Firestore `contentPacks`, shared by all users.
// Phones only read packs. Nothing in the app can call OpenAI or start this.
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret, defineString, defineInt } = require('firebase-functions/params');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');
const { verifyItems } = require('./verify');

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const OPENAI_MODEL = defineString('OPENAI_MODEL', { default: 'gpt-4o-mini' });

/** Questions requested per subject and difficulty each run. Keeps cost bounded. */
const ITEMS_PER_BATCH = defineInt('ITEMS_PER_BATCH', { default: 25 });

const SUBJECTS = ['en', 'de', 'python', 'javascript'];
const NAMES = { en: 'English', de: 'German', python: 'Python', javascript: 'JavaScript' };
const LEVELS = { 1: 'Beginner', 2: 'Intermediate', 3: 'Advanced' };

/// The same topics the app offers as interests.
const TOPICS = [
  'travel', 'food', 'nature', 'sports', 'technology', 'business',
  'science', 'education', 'entertainment', 'daily life', 'feelings',
];

const LANGUAGE_RULES = {
  1: 'Everyday A1-A2 words: food, family, home. Short sentences of 5-8 words, present tense. Wrong answers are clearly different.',
  2: 'B1 topics: work, travel, opinions. Past and future tenses. Wrong answers are plausible and related in meaning.',
  3: 'B2-C1 abstract, formal and rare words, long sentences. Wrong answers look alike and are easy to confuse.',
};
const CODE_RULES = {
  1: 'Variables, arithmetic, strings, conditions, simple loops.',
  2: 'Functions, lists or arrays, dictionaries or objects, slices, map and filter.',
  3: 'Closures, classes, generators or async, scope traps, mutable defaults.',
};

function promptFor(subject, difficulty, count, avoid) {
  const coding = subject === 'python' || subject === 'javascript';
  const level = LEVELS[difficulty];
  const shared =
    `Write ${count} new ${NAMES[subject]} questions for ${level} learners in a phone app. ` +
    'Every field must be accurate; a wrong answer teaches something false. ' +
    `Set subject to "${subject}" and difficulty to ${difficulty}. ` +
    'answer is the 0-based index of the right option, and exactly one option is right. ' +
    'explanation is one short sentence in English. ';
  const noRepeat = avoid.length
    ? `Do not repeat these existing prompts: ${JSON.stringify(avoid.slice(-60))}. `
    : '';
  if (!coding) {
    return (
      shared + noRepeat +
      `Rules for this level: ${LANGUAGE_RULES[difficulty]} ` +
      'Mix these kinds: "Pick the meaning", "Fill the blank"' +
      (subject === 'de' ? ', "der, die or das?", "Grammar"' : ', "Closest meaning"') +
      '. Four options each. Leave code, check, expected, fixed and lines empty. ' +
      `Set topic to the one that fits best from ${JSON.stringify(TOPICS)}, ` +
      'and spread the questions across all of them.' +
      (subject === 'de' ? ' Prompts are in German with an English gloss in brackets.' : '')
    );
  }
  return (
    shared + noRepeat +
    'Leave topic empty. ' +
    `Rules for this level: ${CODE_RULES[difficulty]} ` +
    'Code is at most 8 lines, each at most 36 characters, with no imports, files, network or input. ' +
    `Output comes from ${subject === 'python' ? 'print' : 'console.log'}. Mix these forms:\n` +
    '1. kind "What does this print?", prompt "What is the output?", check "output": four options, the right one being the exact printed output.\n' +
    '2. kind "Fill the blank", prompt "Which word completes the code?", check "blank": code contains ___, expected is the output once filled.\n' +
    '3. kind "Find the bug", prompt "Which line has the bug?", check "bug": options are "Line 1" style, fixed is the corrected code, expected is its output.\n' +
    '4. kind "Order the lines", prompt "Put the lines in order.", check "lines": lines are the program in the right order, expected is its output, options empty, code empty.'
  );
}

const ITEM_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['subject', 'difficulty', 'kind', 'prompt', 'code', 'options', 'answer', 'explanation', 'check', 'expected', 'fixed', 'lines', 'topic'],
  properties: {
    subject: { type: 'string' },
    difficulty: { type: 'integer' },
    kind: { type: 'string' },
    prompt: { type: 'string' },
    code: { type: 'string' },
    options: { type: 'array', items: { type: 'string' } },
    answer: { type: 'integer' },
    explanation: { type: 'string' },
    check: { type: 'string' },
    expected: { type: 'string' },
    fixed: { type: 'string' },
    lines: { type: 'array', items: { type: 'string' } },
    topic: { type: 'string' },
  },
};

async function askOpenAI(prompt) {
  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${OPENAI_API_KEY.value()}`,
    },
    body: JSON.stringify({
      model: OPENAI_MODEL.value(),
      messages: [
        { role: 'system', content: 'You write accurate, level-appropriate learning questions.' },
        { role: 'user', content: prompt },
      ],
      response_format: {
        type: 'json_schema',
        json_schema: {
          name: 'questions',
          strict: true,
          schema: {
            type: 'object',
            additionalProperties: false,
            required: ['items'],
            properties: { items: { type: 'array', items: ITEM_SCHEMA } },
          },
        },
      },
    }),
    signal: AbortSignal.timeout(180000),
  });
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const data = await res.json();
  return JSON.parse(data.choices[0].message.content).items;
}

/** Empty fields from the strict schema become absent, as the app expects. */
function tidy(item) {
  const out = { ...item };
  // An unknown topic is dropped, and the app treats it as daily life.
  if (!TOPICS.includes(out.topic)) delete out.topic;
  for (const k of ['code', 'check', 'expected', 'fixed']) {
    if (!out[k]) delete out[k];
  }
  if (!out.lines?.length) delete out.lines;
  if (out.lines) {
    out.options = [];
    out.answer = 0;
    out.explanation = out.explanation || `It prints ${out.expected}.`;
  }
  return out;
}

async function recentPrompts(db, subject, difficulty) {
  const snap = await db
    .collection('contentPacks')
    .where('subject', '==', subject)
    .where('difficulty', '==', difficulty)
    .limit(10)
    .get();
  return snap.docs.flatMap((d) => (d.data().items ?? []).map((i) => i.code ?? i.prompt));
}

async function generateAll() {
  if (!admin.apps.length) admin.initializeApp();
  const db = admin.firestore();
  const summary = [];
  for (const subject of SUBJECTS) {
    for (const difficulty of [1, 2, 3]) {
      try {
        const avoid = await recentPrompts(db, subject, difficulty);
        const raw = await askOpenAI(promptFor(subject, difficulty, ITEMS_PER_BATCH.value(), avoid));
        const { good, rejected } = await verifyItems(raw.map(tidy), subject, difficulty);
        for (const r of rejected) {
          logger.info('Rejected', { subject, difficulty, problem: r.problem });
        }
        if (good.length) {
          const createdAt = Date.now();
          await db.collection('contentPacks').doc(`${subject}_${difficulty}_${createdAt}`).set({
            subject,
            difficulty,
            createdAt,
            items: good,
          });
        }
        summary.push(`${subject}/${difficulty}: ${good.length} published, ${rejected.length} rejected`);
      } catch (e) {
        // One failed batch shouldn't lose the rest of the run.
        logger.error('Batch failed', { subject, difficulty, message: e.message });
        summary.push(`${subject}/${difficulty}: failed`);
      }
    }
  }
  logger.info('Content run finished', { summary });
}

exports.generateContentPacks = onSchedule(
  {
    schedule: 'every monday 03:00',
    timeZone: 'Asia/Kolkata',
    secrets: [OPENAI_API_KEY],
    timeoutSeconds: 1800,
    memory: '1GiB',
    // Never two runs at once, and no automatic retries that would cost twice.
    maxInstances: 1,
    retryCount: 0,
  },
  generateAll,
);
