"""Builds assets/code_bank.json, the coding questions bundled with the app.

Every answer comes from actually running the code with Python or Node, never
from what someone typed, so the bank cannot teach a wrong output.

    python tool/build_code_bank.py
"""

import json
import os
import random
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'code_bank.json')
RUNNERS = {'python': (['python'], '.py'), 'javascript': (['node'], '.js')}
ERROR = 'Error'


def run(lang, code):
    """What the code prints, on one line, or 'Error' if it fails."""
    cmd, ext = RUNNERS[lang]
    with tempfile.NamedTemporaryFile('w', suffix=ext, delete=False, encoding='utf-8') as f:
        f.write(code)
    try:
        r = subprocess.run(cmd + [f.name], capture_output=True, text=True, timeout=20)
    finally:
        os.unlink(f.name)
    if r.returncode != 0:
        return ERROR
    # Node pads arrays as "[ 4, 6 ]"; show them as written in the question.
    return ' '.join(r.stdout.split()).replace('[ ', '[').replace(' ]', ']')


# (difficulty, code, params, wrong answers, explanation). @name fills in a
# param. Wrong answers are templates too; {out} is the real output.
PY_OUTPUT = [
    (1, 'x = @a\nx = x + @b\nprint(x)', [dict(a=a, b=b) for a, b in [(5, 2), (3, 4), (10, 5), (7, 8), (6, 3), (9, 1)]],
     ['@a', '@b', ERROR], 'x starts at @a, then @b is added.'),
    (1, 'print(@a * @b)', [dict(a=a, b=b) for a, b in [(3, 4), (6, 2), (5, 5), (7, 3), (8, 2), (9, 4)]],
     ['@a@b', '@a', ERROR], '* multiplies the two numbers.'),
    (1, 'print("@a" + "@b")', [dict(a=a, b=b) for a, b in [('sun', 'set'), ('rain', 'bow'), ('foot', 'ball'), ('tea', 'pot'), ('moon', 'light')]],
     ['@a @b', '@a', ERROR], '+ joins two strings with no space.'),
    (1, 'a = @a\nif a > @b:\n    print("big")\nelse:\n    print("small")', [dict(a=a, b=b) for a, b in [(5, 3), (2, 8), (9, 4), (1, 7), (6, 6)]],
     ['big small', 'a', ERROR, 'big', 'small'], 'The condition is checked, and only one branch runs.'),
    (1, 'for i in range(@n):\n    print(i)', [dict(n=n) for n in [2, 3, 4, 5]],
     ['@n', '1 2', ERROR], 'range(@n) counts from 0 up to, not including, @n.'),
    (1, 'word = "@w"\nprint(len(word))', [dict(w=w) for w in ['hello', 'python', 'code', 'phone', 'ghost', 'loop']],
     ['0', '1', ERROR, '10'], 'len() counts the characters in a string.'),
    (1, 'print(@a % @b)', [dict(a=a, b=b) for a, b in [(7, 3), (10, 4), (9, 2), (17, 5), (8, 3)]],
     ['0', '@b', '5', ERROR], '% gives the remainder after dividing.'),
    (1, 'word = "@w"\nprint(word[0])', [dict(w=w) for w in ['apple', 'tiger', 'mango', 'river', 'cloud']],
     ['@w', '0', ERROR], 'Positions start at 0, so [0] is the first letter.'),
    (2, 'nums = [@a, @b, @c]\nprint([n * 2 for n in nums if n > @a])', [dict(a=a, b=b, c=c) for a, b, c in [(1, 2, 3), (2, 4, 6), (3, 5, 7), (1, 5, 9)]],
     ['[@a, @b, @c]', '[]', ERROR], 'Keeps numbers above @a, then doubles each.'),
    (2, 'ages = {"ann": @a, "bob": @b}\nprint(ages.get("cat", @c))', [dict(a=a, b=b, c=c) for a, b, c in [(20, 30, 0), (11, 12, -1), (40, 50, 9), (5, 6, 7)]],
     ['None', '@a', ERROR], '.get() returns the default when the key is missing.'),
    (2, 'nums = [10, 20, 30, 40, 50]\nprint(nums[@a:@b])', [dict(a=a, b=b) for a, b in [(1, 3), (0, 2), (2, 4), (3, 5), (1, 4)]],
     ['[10, 20]', '[50]', ERROR], 'A slice stops before the end position.'),
    (2, 'def f(a, b=@b):\n    return a * b\nprint(f(@a))', [dict(a=a, b=b) for a, b in [(3, 2), (4, 5), (6, 3), (2, 7)]],
     ['@a', '@b', ERROR], 'b uses its default value of @b.'),
    (2, 'print(sorted([@a, @b, @c], reverse=True))', [dict(a=a, b=b, c=c) for a, b, c in [(3, 1, 2), (5, 9, 7), (8, 2, 4), (1, 6, 3)]],
     ['[@a, @b, @c]', 'None', ERROR], 'reverse=True sorts from largest to smallest.'),
    (2, 'print("-".join(["@a", "@b", "@c"]))', [dict(a=a, b=b, c=c) for a, b, c in [('a', 'b', 'c'), ('x', 'y', 'z'), ('1', '2', '3'), ('red', 'tan', 'sky')]],
     ['@a@b@c', '@a @b @c', ERROR], 'join puts the string between the items.'),
    (2, 'n = @n\ntotal = 0\nwhile n > 0:\n    total += n\n    n -= 1\nprint(total)', [dict(n=n) for n in [3, 4, 5, 6]],
     ['@n', '0', ERROR], 'The loop adds @n, then each smaller number down to 1.'),
    (2, 'a = [1, 2]\nb = a\nb.append(@n)\nprint(len(a))', [dict(n=n) for n in [3, 7, 9]],
     ['2', '@n', ERROR], 'b is the same list as a, so a grows too.'),
    (3, 'def add(item, box=[]):\n    box.append(item)\n    return box\n\nadd(@a)\nprint(add(@b))', [dict(a=a, b=b) for a, b in [(1, 2), (3, 4), (5, 6), (7, 8)]],
     ['[@b]', '[@a]', ERROR], 'The default list is made once and shared between calls.'),
    (3, 'def make():\n    n = @a\n    def step():\n        nonlocal n\n        n += @b\n        return n\n    return step\n\ns = make()\ns()\nprint(s())', [dict(a=a, b=b) for a, b in [(0, 1), (1, 2), (5, 5), (2, 3)]],
     ['@a', '@b', ERROR], 'The inner function keeps n between calls: a closure.'),
    (3, 'print(sum(x * x for x in range(@n)))', [dict(n=n) for n in [3, 4, 5, 6]],
     ['@n', '0', ERROR], 'Adds the squares of 0 up to @n minus 1.'),
    (3, 'print(len({@a, @b, @a, @c, @b}))', [dict(a=a, b=b, c=c) for a, b, c in [(1, 2, 3), (4, 5, 6), (7, 8, 9)]],
     ['5', '2', ERROR], 'A set keeps each value only once.'),
    (3, 'def f(*args, **kw):\n    return len(args) + len(kw)\nprint(f(@a, @b, x=@c))', [dict(a=a, b=b, c=c) for a, b, c in [(1, 2, 3), (4, 5, 6), (7, 8, 9)]],
     ['2', '1', ERROR], 'Two positional arguments plus one keyword argument.'),
    (3, 'try:\n    print(@a / 0)\nexcept ZeroDivisionError:\n    print("oops")\nfinally:\n    print("done")', [dict(a=a) for a in [1, 5]],
     ['oops', 'done', ERROR], 'except handles the error, and finally always runs.'),
    (3, 'class A:\n    n = @a\n\nx = A()\ny = A()\nx.n = @b\nprint(y.n)', [dict(a=a, b=b) for a, b in [(1, 2), (3, 9), (5, 7)]],
     ['@b', 'None', ERROR], 'x.n creates x\'s own value; y still reads the class value.'),
    (3, 'print(list(map(lambda x: x + @a, [1, 2, 3])))', [dict(a=a) for a in [1, 2, 5, 10]],
     ['[1, 2, 3]', '@a', ERROR], 'map applies the function to each item.'),
]

JS_OUTPUT = [
    (1, 'let x = @a;\nx = x + @b;\nconsole.log(x);', [dict(a=a, b=b) for a, b in [(5, 2), (3, 4), (10, 5), (7, 8), (6, 3)]],
     ['@a', '@b', ERROR], 'x starts at @a, then @b is added.'),
    (1, 'let a = "@a";\nconsole.log(a + @b);', [dict(a=a, b=b) for a, b in [(5, 2), (1, 9), (3, 3), (7, 1), (2, 8)]],
     ['@a', '@b', ERROR, '0'], 'A string + a number joins them as text.'),
    (1, 'console.log(@a * @b);', [dict(a=a, b=b) for a, b in [(3, 4), (6, 2), (5, 5), (7, 3), (8, 2)]],
     ['@a@b', '@a', ERROR], '* multiplies the two numbers.'),
    (1, 'const a = @a;\nif (a > @b) {\n  console.log("big");\n} else {\n  console.log("small");\n}', [dict(a=a, b=b) for a, b in [(5, 3), (2, 8), (9, 4), (1, 7)]],
     ['big small', 'a', ERROR, 'big', 'small'], 'Only one branch of the if runs.'),
    (1, 'for (let i = 0; i < @n; i++) {\n  console.log(i);\n}', [dict(n=n) for n in [2, 3, 4, 5]],
     ['@n', '1 2', ERROR], 'The loop runs while i is below @n, starting at 0.'),
    (1, 'const word = "@w";\nconsole.log(word.length);', [dict(w=w) for w in ['hello', 'script', 'code', 'phone', 'ghost']],
     ['0', '1', ERROR, '10'], '.length counts the characters.'),
    (1, 'console.log(@a % @b);', [dict(a=a, b=b) for a, b in [(7, 3), (10, 4), (9, 2), (17, 5)]],
     ['0', '@b', '5', ERROR], '% gives the remainder after dividing.'),
    (1, 'console.log(5 === "5");\nconsole.log(5 == "5");', [dict()],
     ['true true', 'false false', 'true false', ERROR], '=== checks the type too; == converts first.'),
    (2, 'const r = [@a, @b, @c]\n  .map(n => n * 2)\n  .filter(n => n > @b);\nconsole.log(r);', [dict(a=a, b=b, c=c) for a, b, c in [(1, 2, 3), (2, 3, 5), (1, 4, 6), (3, 4, 8)]],
     ['[@a, @b, @c]', '[]', ERROR], 'Doubles every number, then keeps those above @b.'),
    (2, 'const nums = [@a, @b, @c];\nconsole.log(nums.reduce((s, n) => s + n, 0));', [dict(a=a, b=b, c=c) for a, b, c in [(1, 2, 3), (4, 5, 6), (2, 4, 8), (3, 3, 9)]],
     ['@a', '0', ERROR], 'reduce adds each number to the running total.'),
    (2, 'const u = { name: "ann", age: @a };\nconst { age } = u;\nconsole.log(age + @b);', [dict(a=a, b=b) for a, b in [(20, 1), (30, 5), (11, 2)]],
     ['@a', 'undefined', ERROR], 'Destructuring pulls age out of the object.'),
    (2, 'const a = [1, 2];\nconst b = [...a, @n];\nconsole.log(a.length, b.length);', [dict(n=n) for n in [3, 7, 9]],
     ['3 3', '2 2', ERROR], 'Spread copies into a new array, so a keeps its length.'),
    (2, 'function f(a, b = @b) {\n  return a * b;\n}\nconsole.log(f(@a));', [dict(a=a, b=b) for a, b in [(3, 2), (4, 5), (6, 3)]],
     ['@a', 'NaN', ERROR], 'b falls back to its default of @b.'),
    (2, 'const s = "@w";\nconsole.log(s.split("").reverse().join(""));', [dict(w=w) for w in ['abc', 'code', 'moon', 'star']],
     ['@w', 'undefined', ERROR], 'Splits into letters, reverses them, joins them again.'),
    (2, 'const a = [1, 2];\nconst b = a;\nb.push(@n);\nconsole.log(a.length);', [dict(n=n) for n in [3, 7, 9]],
     ['2', '@n', ERROR], 'b points to the same array, so a grows too.'),
    (3, 'for (var i = 0; i < @n; i++) {\n  setTimeout(() => console.log(i), 0);\n}', [dict(n=n) for n in [2, 3, 4]],
     ['0 1', '0 0', ERROR, '1 2'], 'var is shared, and the timers run after the loop ends.'),
    (3, 'for (let i = 0; i < @n; i++) {\n  setTimeout(() => console.log(i), 0);\n}', [dict(n=n) for n in [2, 3, 4]],
     ['@n @n', '0 0', ERROR, '1 2'], 'let makes a new i for each loop.'),
    (3, 'function make() {\n  let n = @a;\n  return () => (n += @b);\n}\nconst s = make();\ns();\nconsole.log(s());', [dict(a=a, b=b) for a, b in [(0, 1), (1, 2), (5, 5), (2, 3)]],
     ['@a', '@b', ERROR], 'The inner function keeps n between calls: a closure.'),
    (3, 'console.log("a");\nsetTimeout(() => console.log("b"), 0);\nPromise.resolve().then(() => console.log("c"));\nconsole.log("d");', [dict()],
     ['a b c d', 'a d b c', 'a c d b', ERROR], 'Sync code first, then promises, then timers.'),
    (3, 'console.log(typeof null, typeof @a);', [dict(a=a) for a in [1, 5]],
     ['null number', 'object object', ERROR], 'typeof null is "object", a famous JavaScript quirk.'),
    (3, 'class A {\n  n = @a;\n  get() {\n    return this.n;\n  }\n}\nconst f = new A().get;\ntry {\n  console.log(f());\n} catch {\n  console.log("lost");\n}', [dict(a=a) for a in [1, 7]],
     ['@a', 'undefined', ERROR], 'Detached from its object, the method loses this.'),
    (3, 'const m = new Map([["a", @a]]);\nm.set("a", @b);\nconsole.log(m.size, m.get("a"));', [dict(a=a, b=b) for a, b in [(1, 2), (5, 9), (3, 4)]],
     ['2 @b', '1 @a', ERROR], 'Setting the same key replaces its value.'),
    (3, 'console.log([..."@w"].filter((c, i, a) => a.indexOf(c) === i).length);', [dict(w=w) for w in ['hello', 'banana', 'level']],
     ['0', '1', ERROR, '10'], 'Keeps only the first time each letter appears.'),
]

# (difficulty, code with ___, right answer, wrong answers, expected output, explanation)
PY_BLANK = [
    (1, '___ x in range(3):\n    print(x)', 'for', ['if', 'while', 'def'], '0 1 2', 'for loops over each value.'),
    (1, 'name = "ann"\n___(name)', 'print', ['echo', 'write', 'log'], 'ann', 'print shows a value.'),
    (1, 'x = 5\n___ x > 3:\n    print("yes")', 'if', ['for', 'def', 'when'], 'yes', 'if runs code when a condition is true.'),
    (2, '___ double(n):\n    return n * 2\nprint(double(4))', 'def', ['function', 'fn', 'func'], '8', 'def creates a function.'),
    (2, 'nums = [1, 2]\nnums.___(3)\nprint(nums)', 'append', ['push', 'add', 'insert'], '[1, 2, 3]', 'append adds to the end of a list.'),
    (2, 'def f():\n    ___ 7\nprint(f())', 'return', ['yield', 'give', 'print'], '7', 'return sends a value back.'),
    (3, 'class Dog:\n    def ___(self, name):\n        self.name = name\nprint(Dog("rex").name)', '__init__', ['init', 'new', 'create'], 'rex', '__init__ sets up a new object.'),
    (3, 'def gen():\n    ___ 1\n    ___ 2\nprint(list(gen()))', 'yield', ['return', 'give', 'emit'], '[1, 2]', 'yield produces values one at a time.'),
    (3, '___ open is not None:\n    print("ok")', 'if', ['with', 'try', 'for'], 'ok', 'if checks the condition.'),
]
JS_BLANK = [
    (1, '___ x = 5;\nconsole.log(x);', 'let', ['int', 'var x:', 'def'], '5', 'let declares a variable.'),
    (1, 'console.___("hi");', 'log', ['print', 'echo', 'write'], 'hi', 'console.log prints a value.'),
    (1, 'const x = 5;\n___ (x > 3) {\n  console.log("yes");\n}', 'if', ['for', 'when', 'case'], 'yes', 'if runs code when a condition is true.'),
    (2, '___ double(n) {\n  return n * 2;\n}\nconsole.log(double(4));', 'function', ['def', 'fn', 'func'], '8', 'function creates a function.'),
    (2, 'const a = [1, 2];\na.___(3);\nconsole.log(a);', 'push', ['append', 'add', 'insert'], '[1, 2, 3]', 'push adds to the end of an array.'),
    (2, 'const f = (n) ___ n + 1;\nconsole.log(f(1));', '=>', ['->', '==', ':='], '2', '=> makes an arrow function.'),
    (3, 'async function f() {\n  const v = ___ Promise.resolve(3);\n  console.log(v);\n}\nf();', 'await', ['yield', 'async', 'then'], '3', 'await waits for a promise.'),
    (3, 'class A {\n  ___() {\n    this.n = 1;\n  }\n}\nconsole.log(new A().n);', 'constructor', ['init', '__init__', 'create'], '1', 'constructor sets up a new object.'),
    (3, 'const o = { a: 1 };\nconsole.log(Object.___(o));', 'keys', ['props', 'names', 'list'], '[\'a\']', 'Object.keys lists the property names.'),
]

# (difficulty, buggy code, bad line number, fixed code, expected output, explanation)
PY_BUG = [
    (1, 'x = 5\nif x > 3\n    print("big")', 2, 'x = 5\nif x > 3:\n    print("big")', 'big', 'An if line needs a colon at the end.'),
    (1, 'name = "ann\nprint(name)', 1, 'name = "ann"\nprint(name)', 'ann', 'The string is missing its closing quote.'),
    (2, 'def add(a, b):\n    a + b\nprint(add(1, 2))', 2, 'def add(a, b):\n    return a + b\nprint(add(1, 2))', '3', 'Without return the function gives back None.'),
    (2, 'nums = [1, 2, 3]\nprint(nums[3])', 2, 'nums = [1, 2, 3]\nprint(nums[2])', '3', 'Positions start at 0, so the last is 2.'),
    (3, 'class A:\n    def hi():\n        return 1\nprint(A().hi())', 2, 'class A:\n    def hi(self):\n        return 1\nprint(A().hi())', '1', 'Methods need self as the first parameter.'),
    (3, 'total = 0\ndef add():\n    total += 1\nadd()\nprint(total)', 3, 'total = 0\ndef add():\n    global total\n    total += 1\nadd()\nprint(total)', '1', 'Changing an outer variable needs global.'),
]
JS_BUG = [
    (1, 'const x = 5;\nx = 6;\nconsole.log(x);', 1, 'let x = 5;\nx = 6;\nconsole.log(x);', '6', 'A const cannot be reassigned; use let.'),
    (1, 'let name = "ann;\nconsole.log(name);', 1, 'let name = "ann";\nconsole.log(name);', 'ann', 'The string is missing its closing quote.'),
    (2, 'function add(a, b) {\n  a + b;\n}\nconsole.log(add(1, 2));', 2, 'function add(a, b) {\n  return a + b;\n}\nconsole.log(add(1, 2));', '3', 'Without return the function gives undefined.'),
    (2, 'const a = [1, 2, 3];\nconsole.log(a.size);', 2, 'const a = [1, 2, 3];\nconsole.log(a.length);', '3', 'Arrays use .length, not .size.'),
    (3, 'async function f() {\n  return 1;\n}\nconsole.log(f() + 1);', 4, 'async function f() {\n  return 1;\n}\nf().then(v => console.log(v + 1));', '2', 'An async function gives a promise, so wait for it.'),
    (3, 'const o = {\n  n: 1,\n  get: () => this.n,\n};\nconsole.log(o.get());', 3, 'const o = {\n  n: 1,\n  get() { return this.n; },\n};\nconsole.log(o.get());', '1', 'Arrow functions have no this of their own.'),
]

# (difficulty, lines in the right order, expected output)
PY_ORDER = [
    (1, ['x = 2', 'y = 3', 'print(x + y)'], '5'),
    (1, ['name = "ann"', 'greeting = "hi " + name', 'print(greeting)'], 'hi ann'),
    (2, ['def double(n):', '    return n * 2', 'print(double(4))'], '8'),
    (2, ['total = 0', 'for n in [1, 2, 3]:', '    total += n', 'print(total)'], '6'),
    (3, ['class Dog:', '    def __init__(self, name):', '        self.name = name', 'print(Dog("rex").name)'], 'rex'),
    (3, ['def gen():', '    yield 1', '    yield 2', 'print(list(gen()))'], '[1, 2]'),
]
JS_ORDER = [
    (1, ['let x = 2;', 'let y = 3;', 'console.log(x + y);'], '5'),
    (1, ['const name = "ann";', 'const hi = "hi " + name;', 'console.log(hi);'], 'hi ann'),
    (2, ['function double(n) {', '  return n * 2;', '}', 'console.log(double(4));'], '8'),
    (2, ['let total = 0;', 'for (const n of [1, 2, 3]) {', '  total += n;', '}', 'console.log(total);'], '6'),
    (3, ['class Dog {', '  name = "rex";', '}', 'console.log(new Dog().name);'], 'rex'),
    (3, ['async function f() {', '  const v = await Promise.resolve(3);', '  console.log(v);', '}', 'f();'], '3'),
]

WORD = {'python': 'print', 'javascript': 'log'}


def fill(text, params):
    # Longest names first, so @ab never partly matches @a.
    for k in sorted(params, key=len, reverse=True):
        text = text.replace('@' + k, str(params[k]))
    return text


def build(lang, output, blank, bug, order, rng):
    items = []
    problems = []
    for diff, code, grid, wrongs, why in output:
        for params in grid:
            src = fill(code, params)
            out = run(lang, src)
            options = [out]
            for w in wrongs:
                w = fill(w, params)
                if w not in options:
                    options.append(w)
            if len(options) < 4:
                problems.append(f'too few options: {src!r} -> {out!r}')
                continue
            options = options[:4]
            items.append(dict(subject=lang, difficulty=diff, kind='What does this ' + WORD[lang] + '?',
                              prompt='What is the output?', code=src, options=options, answer=0,
                              explanation=fill(why, params)))
    for diff, code, right, wrongs, expect, why in blank:
        got = run(lang, code.replace('___', right))
        if got.replace("'", '') != expect.replace("'", ''):
            problems.append(f'blank: {code!r} gave {got!r}, wanted {expect!r}')
            continue
        items.append(dict(subject=lang, difficulty=diff, kind='Fill the blank',
                          prompt='Which word completes the code?', code=code,
                          options=[right] + wrongs, answer=0, explanation=why))
    for diff, code, line, fixed, expect, why in bug:
        got = run(lang, fixed)
        if got != expect or run(lang, code) == expect:
            problems.append(f'bug: {code!r} fixed gave {got!r}, wanted {expect!r}')
            continue
        count = code.count('\n') + 1
        others = [n for n in range(1, count + 1) if n != line]
        options = [f'Line {line}'] + [f'Line {n}' for n in others[:3]]
        items.append(dict(subject=lang, difficulty=diff, kind='Find the bug',
                          prompt='Which line has the bug?', code=code,
                          options=options, answer=0, explanation=why))
    for diff, lines, expect in order:
        got = run(lang, '\n'.join(lines))
        if got != expect:
            problems.append(f'order: {lines!r} gave {got!r}, wanted {expect!r}')
            continue
        items.append(dict(subject=lang, difficulty=diff, kind='Order the lines',
                          prompt=f'Put the lines in order so it prints {expect}.',
                          lines=lines, explanation=f'It prints {expect}.'))
    return items, problems


def main():
    rng = random.Random(1)
    py, p1 = build('python', PY_OUTPUT, PY_BLANK, PY_BUG, PY_ORDER, rng)
    js, p2 = build('javascript', JS_OUTPUT, JS_BLANK, JS_BUG, JS_ORDER, rng)
    for p in p1 + p2:
        print('PROBLEM', p)
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(py + js, f, ensure_ascii=False, indent=1)
    for name, items in (('python', py), ('javascript', js)):
        by = {d: sum(i['difficulty'] == d for i in items) for d in (1, 2, 3)}
        print(name, len(items), by)
    sys.exit(1 if p1 + p2 else 0)


if __name__ == '__main__':
    main()
