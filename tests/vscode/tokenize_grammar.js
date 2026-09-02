/*
  tokenize_grammar.js -- MANUAL verification of syntaxes/pascal.tmLanguage.json
  against the real TextMate engine (vscode-textmate + vscode-oniguruma), i.e.
  exactly what VS Code runs.

    cd <scratch dir>
    npm install vscode-textmate vscode-oniguruma
    node <repo>\tests\vscode\tokenize_grammar.js

  WHY IT IS NOT NAMED run_*.ps1
    The battery discovers run_*.ps1 recursively, so anything named that way is
    claimed to have run. This needs two npm modules that the extension does not
    depend on and a fresh clone does not have, so as a battery runner it would
    either fail on a clean machine or -- far worse -- skip and report green.
    A test that can silently skip is the failure mode this repo keeps getting
    bitten by, so it stays a hand-run tool and the BATTERY guard
    (run_pascal_grammar_and_theme.ps1) checks the structural properties instead:
    rule order, the negative lookahead, scope suffixes, theme/grammar agreement.

  WHAT IT PROVED when the grammar was written (2026-09-01), 24/24:
    {$IFDEF} and {$R *.dfm} scope as DIRECTIVES while { } and (* *) scope as
    comments; 'It''s here' survives the doubled-quote escape; 1..5 is a subrange
    and not the float "1."; %1010 and &777 are binary and octal; an asm body is
    meta.assembly. It also caught a real inconsistency -- the declarations rule
    scoped `procedure` as keyword.control while the keyword list scoped it
    storage.type, so the same word got two scopes depending on whether a name
    followed it.
*/

const fs = require('fs');
const path = require('path');

// Node resolves a require() from the SCRIPT's directory, but the two engine
// modules are installed in whatever scratch directory this is run from -- this
// file lives in the repo, which deliberately has no node_modules. Resolve from
// the CWD instead, and say plainly what to do when they are absent rather than
// dying with a bare "Cannot find module".
const { createRequire } = require('module');
const cwdRequire = createRequire(path.join(process.cwd(), 'noop.js'));
let oniguruma, vsctm;
try {
  oniguruma = cwdRequire('vscode-oniguruma');
  vsctm = cwdRequire('vscode-textmate');
} catch (e) {
  console.error('tokenize_grammar.js needs the TextMate engine, which is not a repo dependency.');
  console.error('  cd <a scratch dir> && npm install vscode-textmate vscode-oniguruma');
  console.error('  node ' + __filename);
  process.exit(2);
}

// Repo-relative: this file is tests\vscode\, the extension is editors\vscode\drag-lint\.
const EXT = path.resolve(__dirname, '..', '..', 'editors', 'vscode', 'drag-lint');
const GRAMMAR = path.join(EXT, 'syntaxes', 'pascal.tmLanguage.json');

const LINES = [
  'unit Sample;',
  '{$IFDEF DEBUG}',
  '{$R *.dfm}',
  '{ a plain brace comment }',
  '(* a paren comment *)',
  '// a line comment',
  '/// <summary>doc</summary>',
  'const',
  "  S = 'It''s here';",
  '  C = #13#10;',
  '  H = $FF;',
  '  N = 42;',
  '  F = 1.5;',
  '  B = %1010;',
  '  O = &777;',
  '  R = 1..5;',
  'procedure Foo(const A: string);',
  'begin',
  '  if A <> nil then Exit;',
  'end;',
  'asm',
  '  MOV EAX, 1',
  'end;',
];

// [needle, scope that must be on the token covering the needle's first char, why]
const EXPECT = [
  ['{$IFDEF', 'keyword.control.directive.pascal', 'a compiler directive is NOT a comment'],
  ['DEBUG', 'keyword.control.directive.pascal', 'directive body stays in the directive'],
  ['{$R', 'keyword.control.directive.pascal', '{$R *.dfm} is a directive'],
  ['a plain brace comment', 'comment.block.pascal', 'a brace comment IS a comment'],
  ['a paren comment', 'comment.block.parens.pascal', 'paren comment'],
  ['// a line comment', 'comment.line.double-slash.pascal', 'line comment'],
  ['/// <summary>', 'comment.line.double-slash.pascal', 'DocInsight comment'],
  ["'It''s here'", 'string.quoted.single.pascal', 'string literal'],
  ["''s", 'constant.character.escape.pascal', 'doubled quote is an escape, not a string end'],
  ['here', 'string.quoted.single.pascal', 'string continues past the doubled quote'],
  ['#13', 'constant.character.pascal', 'character constant'],
  ['$FF', 'constant.numeric.hex.pascal', 'hex literal'],
  ['42', 'constant.numeric.decimal.pascal', 'decimal literal'],
  ['1.5', 'constant.numeric.float.pascal', 'float literal'],
  ['%1010', 'constant.numeric.binary.pascal', 'binary literal'],
  ['&777', 'constant.numeric.octal.pascal', 'octal literal'],
  ['1..5', 'constant.numeric.decimal.pascal', 'subrange 1..5 is NOT a float'],
  ['procedure', 'storage.type.pascal', 'reserved word'],
  ['Foo', 'entity.name.function.pascal', 'routine name'],
  ['const A', 'storage.type.pascal', 'const: one scope in every context'],
  ['begin', 'keyword.control.pascal', 'begin'],
  ['nil', 'keyword.control.pascal', 'nil'],
  ['<>', 'keyword.operator.pascal', 'operator'],
  ['MOV EAX', 'meta.assembly.pascal', 'asm body'],
];

(async () => {
  // Resolved through the module rather than __dirname: this file lives in the
  // repo but the two npm modules are installed wherever it is run FROM, so a
  // __dirname-relative path only works in the directory it was written in.
  const wasm = fs.readFileSync(
    path.join(path.dirname(cwdRequire.resolve('vscode-oniguruma')), '..', 'release', 'onig.wasm')
  );
  await oniguruma.loadWASM(wasm.buffer);

  const registry = new vsctm.Registry({
    onigLib: Promise.resolve({
      createOnigScanner: (s) => new oniguruma.OnigScanner(s),
      createOnigString: (s) => new oniguruma.OnigString(s),
    }),
    loadGrammar: async (scope) =>
      scope === 'source.pascal'
        ? vsctm.parseRawGrammar(fs.readFileSync(GRAMMAR, 'utf8'), GRAMMAR)
        : null,
  });

  const grammar = await registry.loadGrammar('source.pascal');
  if (!grammar) throw new Error('grammar failed to load');

  // Carry rule state across lines the way an editor does -- a multi-line
  // construct only misbehaves when state is preserved.
  const perLine = [];
  let state = vsctm.INITIAL;
  for (const line of LINES) {
    const r = grammar.tokenizeLine(line, state);
    perLine.push(r.tokens);
    state = r.ruleStack;
  }

  function scopesAt(needle) {
    for (let i = 0; i < LINES.length; i++) {
      const col = LINES[i].indexOf(needle);
      if (col < 0) continue;
      const tok = perLine[i].find((t) => col >= t.startIndex && col < t.endIndex);
      if (tok) return { scopes: tok.scopes, line: i + 1 };
    }
    return null;
  }

  let failed = 0;
  for (const [needle, scope, why] of EXPECT) {
    const at = scopesAt(needle);
    const ok = at && at.scopes.includes(scope);
    if (!ok) failed++;
    const got = at ? at.scopes[at.scopes.length - 1] : '(needle not in sample)';
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${why.padEnd(48)} ${JSON.stringify(needle).padEnd(16)} -> ${got}`);
  }

  console.log('');
  console.log(failed === 0 ? 'TOKENIZATION: all expectations met' : `TOKENIZATION: ${failed} FAILED`);
  process.exitCode = failed === 0 ? 0 : 1;
})().catch((e) => { console.error(e); process.exitCode = 2; });
