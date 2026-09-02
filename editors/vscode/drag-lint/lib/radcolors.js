/*
  radcolors.js -- read RAD Studio's editor colour scheme out of the registry and
  turn it into VS Code colours.

  WHY THIS EXISTS
    "Colour VS Code exactly like the IDE" is only literally true if the colours
    come FROM the IDE. RAD Studio stores its editor scheme at
    HKCU\Software\Embarcadero\BDS\<ver>\Editor\Highlight -- 42 elements, one
    subkey each -- so the theme is GENERATED from the user's own settings and
    tracks them when they change it.

  THE FOUR TRAPS, ALL SILENT (2026-09-01)

    1. The value name is `Foreground Color New`, NOT `Foreground Color`.
       The old-style names still exist on the keys and read back EMPTY. A
       converter reading them produces a theme with no colours at all, which
       presents as "the theme did not load" rather than as a bug here.

    2. `$00BBGGRR` is a Delphi TColor, so the bytes are BGR, NOT RGB.
       $00FFAA7F is #7FAAFF (light blue), not #FFAA7F (salmon). This was
       VERIFIED three ways plus against the live IDE before a line was written,
       because BOTH orderings produce a plausible dark palette and the WRONG one
       looks MORE conventional (blue keywords, salmon strings -- near-identical
       to Dark+), so a mistake here would never look like a mistake:
         - mechanism: the same field also stores `clWhite`/`clRed`/`clLime`, so
           it is ColorToString output of a TColor, and ColorToString's numeric
           branch is $00BBGGRR by definition;
         - vendor source on the build box, System.UITypes.pas: Red = $0000FF,
           Blue = $FF0000, Lime = $00FF00 -- red is the LOW byte;
         - convention: `Error line`, `Illegal Char` and `Diff deletion` all hold
           $005870E3, which is #E37058 red-orange under BGR and indigo under
           RGB. Red is obviously right for all three.
       run_pascal_grammar_and_theme.ps1 pins this with a literal expectation so
       an "obvious tidy-up" of the swap cannot pass.

    3. `Default Foreground` / `Default Background` are booleans that OVERRIDE the
       stored colour. When True the element inherits the editor default and the
       stored value is meaningless -- honour the flag FIRST.

    4. (Found while reading the live key, not in the original brief.) A value is
       not always `$`-hex: `clWhite`, `clRed`, `clLime`, `clYellow`, `clSilver`,
       `clBlack` all appear in the real scheme on this machine. A hex-only parser
       drops those elements silently.

  No dependencies and no build step, on purpose -- the extension ships as plain
  CommonJS (see extension.js's header). The registry is read through reg.exe so
  there is no native module either.
*/

'use strict';

const { execFileSync } = require('child_process');

const HIVE = 'HKCU\\Software\\Embarcadero\\BDS';

/*
  Trap 4. Vcl.Graphics' named TColor constants, as they come back from
  ColorToString. Values are the RTL's own (System.UITypes TColors), i.e. still
  $00BBGGRR -- they are run through the same swap as any other number, so this
  table cannot disagree with the hex path about byte order.
*/
const NAMED = {
  clblack: 0x000000, clmaroon: 0x000080, clgreen: 0x008000, clolive: 0x008080,
  clnavy: 0x800000, clpurple: 0x800080, clteal: 0x808000, clgray: 0x808080,
  clsilver: 0xc0c0c0, clred: 0x0000ff, cllime: 0x00ff00, clyellow: 0x00ffff,
  clblue: 0xff0000, clfuchsia: 0xff00ff, claqua: 0xffff00, clwhite: 0xffffff,
  clmoneygreen: 0xc0dcc0, clskyblue: 0xf0caa6, clcream: 0xf0fbff,
  clmedgray: 0xa4a0a0, cldkgray: 0x808080, clltgray: 0xc0c0c0,
};

/*
  A Delphi TColor value -> "#RRGGBB".

  Returns null for anything that has no fixed RGB: an empty value, an
  unrecognised name, or a SYSTEM colour. System colours are $FFxxxxxx (the high
  byte is not zero) and mean "ask the OS" -- clWindow is $FF000005, which read as
  a plain number would be a near-black blue and would poison the background of a
  generated theme. Callers treat null as "inherit".
*/
function delphiColorToHex(raw) {
  if (raw === undefined || raw === null) return null;
  const s = String(raw).trim();
  if (!s) return null;

  let v;
  if (s[0] === '$') {
    if (!/^\$[0-9a-fA-F]{1,8}$/.test(s)) return null;
    v = parseInt(s.slice(1), 16);
  } else if (/^-?\d+$/.test(s)) {
    v = Number(s) >>> 0;
  } else {
    const named = NAMED[s.toLowerCase()];
    if (named === undefined) return null;
    v = named;
  }

  if (v > 0x00ffffff) return null; // system colour ($FFxxxxxx) -- no fixed RGB

  // Trap 2: $00BBGGRR. Red is the LOW byte.
  const r = v & 0xff;
  const g = (v >> 8) & 0xff;
  const b = (v >> 16) & 0xff;
  const hh = (n) => n.toString(16).padStart(2, '0').toUpperCase();
  return `#${hh(r)}${hh(g)}${hh(b)}`;
}

/*
  One Highlight element as VS Code understands it.
  `fg`/`bg` are "#RRGGBB" or null (inherit), `fontStyle` is a TextMate style
  string ('bold italic', '' for none).
*/
function elementFromValues(values) {
  const truthy = (x) => String(x || '').trim().toLowerCase() === 'true';

  // Trap 3: the Default flags win over whatever colour is stored.
  const fg = truthy(values['Default Foreground'])
    ? null
    : delphiColorToHex(values['Foreground Color New']); // Trap 1: ...New
  const bg = truthy(values['Default Background'])
    ? null
    : delphiColorToHex(values['Background Color New']);

  const styles = [];
  if (truthy(values.Bold)) styles.push('bold');
  if (truthy(values.Italic)) styles.push('italic');
  if (truthy(values.Underline)) styles.push('underline');

  return { fg, bg, fontStyle: styles.join(' ') };
}

/*
  reg.exe ACCEPTS the short hive names but ECHOES the long ones: query
  `HKCU\...` and every key line comes back `HKEY_CURRENT_USER\...`. Matching the
  query string against the output therefore finds nothing, and the parse yields
  zero elements from a command that succeeded -- which is why readScheme refuses
  to return a colourless scheme rather than trusting the parse.
*/
const HIVE_LONG = {
  HKCU: 'HKEY_CURRENT_USER', HKLM: 'HKEY_LOCAL_MACHINE', HKCR: 'HKEY_CLASSES_ROOT',
  HKU: 'HKEY_USERS', HKCC: 'HKEY_CURRENT_CONFIG',
};

function expandHive(key) {
  const m = /^([A-Z]+)(\\|$)/i.exec(String(key));
  const long = m && HIVE_LONG[m[1].toUpperCase()];
  return long ? long + String(key).slice(m[1].length) : String(key);
}

/*
  Parse `reg.exe query <key> /s` output into { <element>: {values...} }.

  reg.exe prints a key line, then indented "    Name    REG_SZ    Value" rows.
  A value may legitimately contain spaces (and every element name here does --
  "Reserved word", "Additional search match highlight"), so split on the TYPE
  token rather than on whitespace.
*/
function parseRegQuery(text, hiveKey) {
  const want = expandHive(hiveKey).toUpperCase();
  const out = {};
  let current = null;
  for (const line of String(text).split(/\r?\n/)) {
    if (!line.trim()) continue;
    if (/^HKEY_/i.test(line.trim())) {
      const full = line.trim();
      const idx = full.toUpperCase().indexOf(want);
      current = idx >= 0 ? full.slice(idx + want.length).replace(/^\\/, '') : null;
      if (current) out[current] = {};
      continue;
    }
    if (!current) continue;
    const m = line.match(/^\s{2,}(.+?)\s{2,}REG_[A-Z_]+\s{2,}(.*)$/);
    if (m) out[current][m[1].trim()] = m[2];
  }
  return out;
}

/*
  Which BDS versions are installed, newest first. Returns e.g. ['37.0','36.0'].
*/
function installedVersions() {
  let text;
  try {
    text = execFileSync('reg.exe', ['query', HIVE], { encoding: 'utf8' });
  } catch {
    return [];
  }
  const vers = [];
  for (const line of text.split(/\r?\n/)) {
    const m = line.trim().match(/\\([0-9]+\.[0-9]+)$/);
    if (m) vers.push(m[1]);
  }
  return vers.sort((a, b) => parseFloat(b) - parseFloat(a));
}

/*
  Read one IDE's Highlight scheme.
  `version` may be 'auto' (newest installed) or e.g. '37.0'.
  Throws with an actionable message rather than returning an empty scheme --
  Trap 1's failure mode is a theme with no colours, and a silent empty result is
  exactly how that reaches the user.
*/
function readScheme(version) {
  let ver = version && version !== 'auto' ? version : installedVersions()[0];
  if (!ver) throw new Error(`No RAD Studio installation found under ${HIVE}.`);

  const key = `${HIVE}\\${ver}\\Editor\\Highlight`;
  let text;
  try {
    text = execFileSync('reg.exe', ['query', key, '/s'], { encoding: 'utf8' });
  } catch {
    throw new Error(`Cannot read the editor scheme at ${key}. Open RAD Studio ${ver} once so it writes its editor settings.`);
  }

  const raw = parseRegQuery(text, key);
  const elements = {};
  let coloured = 0;
  for (const [name, values] of Object.entries(raw)) {
    const el = elementFromValues(values);
    elements[name] = el;
    if (el.fg || el.bg) coloured++;
  }
  if (coloured === 0) {
    throw new Error(`Read ${Object.keys(raw).length} element(s) from ${key} but none carried a colour -- expected "Foreground Color New" values.`);
  }
  return { version: ver, key, elements };
}

/*
  IDE Highlight element -> the TextMate scopes our grammar emits for it.

  Every scope ends in `.pascal`. That is load-bearing, not cosmetic: it is what
  makes the settings.json path (editor.tokenColorCustomizations) recolour Pascal
  files ONLY and leave every other language on the user's own theme. A scope
  added here without that suffix silently bleeds into other languages.

  The IDE has no separate colour for functions vs types vs variables -- they are
  all `Identifier` -- so this map deliberately collapses them rather than
  inventing distinctions the IDE does not make.
*/
const SCOPE_MAP = [
  ['Reserved word', ['keyword.control.pascal', 'keyword.other.pascal', 'storage.type.pascal', 'storage.modifier.pascal']],
  ['Comment', ['comment.line.double-slash.pascal', 'comment.block.pascal', 'comment.block.parens.pascal']],
  ['String', ['string.quoted.single.pascal', 'constant.character.escape.pascal']],
  ['Character', ['constant.character.pascal']],
  ['Number', ['constant.numeric.decimal.pascal']],
  ['Float', ['constant.numeric.float.pascal']],
  ['Hex', ['constant.numeric.hex.pascal']],
  ['Binary', ['constant.numeric.binary.pascal']],
  ['Octal', ['constant.numeric.octal.pascal']],
  ['Preprocessor', ['keyword.control.directive.pascal']],
  ['Symbol', ['keyword.operator.pascal', 'punctuation.pascal']],
  ['Identifier', ['entity.name.function.pascal', 'entity.name.type.pascal']],
  ['Assembler', ['meta.assembly.pascal']],
];

/*
  The scheme as `editor.tokenColorCustomizations.textMateRules`.
  Elements that inherit (null fg, no style) are omitted -- an empty rule is
  indistinguishable from a missing one to VS Code but not to a reader.
*/
function buildTokenRules(scheme) {
  const rules = [];
  for (const [element, scopes] of SCOPE_MAP) {
    const el = scheme.elements[element];
    if (!el) continue;
    const settings = {};
    if (el.fg) settings.foreground = el.fg;
    // fontStyle must be emitted even when empty, or the base theme's bold/italic
    // leaks through on scopes the IDE draws plain (comments are the visible one).
    settings.fontStyle = el.fontStyle;
    if (!settings.foreground && !settings.fontStyle) continue;
    rules.push({ scope: scopes, settings });
  }
  return rules;
}

/*
  A complete VS Code colour theme. Unlike the settings path this DOES carry the
  editor background, which is the point of it -- it is the "full IDE look"
  option, and it recolours every language, not just Pascal.
*/
function buildTheme(scheme) {
  const plain = scheme.elements['Plain text'] || {};
  const bg = plain.bg || '#1E1E1E';
  const fg = plain.fg || '#D4D4D4';
  const lineNo = scheme.elements['Line Number'] || {};
  const marked = scheme.elements['Marked block'] || {};
  const search = scheme.elements['Search match'] || {};
  const lineHi = scheme.elements['Line Highlight'] || {};
  const rightMargin = scheme.elements['Right margin'] || {};

  /*
    Selection and find-match are DELIBERATELY not literal.

    The IDE's `Marked block` sets a foreground AND a background (black on light
    blue here), so its selection stays readable. VS Code has no per-selection
    foreground -- tokens keep their own colour and the selection colour is
    painted behind them -- so copying the IDE's opaque background verbatim puts
    peach keywords on light blue and makes selected code the least readable text
    on screen. Alpha keeps the IDE's HUE, which is the recognisable part, while
    letting the token colours through.

    Same reasoning for whitespace: the IDE stores it as ordinary plain-text
    white, which at full strength turns every space into a bright dot.
  */
  const alpha = (hex, aa) => (hex ? hex + aa : null);

  const colors = {
    'editor.background': bg,
    'editor.foreground': fg,
    'editorLineNumber.foreground': lineNo.fg || fg,
    'editorRuler.foreground': rightMargin.fg || rightMargin.bg || bg,
    'editor.lineHighlightBackground': lineHi.bg || bg,
    'editor.selectionBackground': alpha(marked.bg, '59') || '#264F78',
    'editor.findMatchHighlightBackground': alpha(search.bg, '4D') || '#515C6A',
    'editorCursor.foreground': fg,
    'editorWhitespace.foreground': alpha((scheme.elements.Whitespace || {}).fg, '40') || fg,
  };
  for (const k of Object.keys(colors)) if (!colors[k]) delete colors[k];

  return {
    // `name` is what the theme picker shows; the label in package.json is what
    // wins, but a theme file with no name reads as anonymous in error messages.
    name: `Delphi IDE (RAD Studio ${scheme.version})`,
    type: isDark(bg) ? 'dark' : 'light',
    semanticHighlighting: true,
    colors,
    tokenColors: buildTokenRules(scheme).map((r) => ({
      name: undefined,
      scope: r.scope,
      settings: r.settings,
    })).map(({ scope, settings }) => ({ scope, settings })),
  };
}

function isDark(hex) {
  const m = /^#([0-9a-fA-F]{6})$/.exec(hex || '');
  if (!m) return true;
  const n = parseInt(m[1], 16);
  const [r, g, b] = [(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];
  return (0.299 * r + 0.587 * g + 0.114 * b) < 128;
}

/*
  One serializer for both writers. The rest of this extension is CRLF, and a
  theme regenerated with LF would show up as a whole-file diff that looks like a
  colour change and is not one -- so the committed theme and a regenerated theme
  are byte-identical when the scheme has not moved.
*/
function serializeJson(value) {
  return (JSON.stringify(value, null, 2) + '\n').replace(/\r?\n/g, '\r\n');
}

module.exports = {
  HIVE,
  serializeJson,
  delphiColorToHex,
  elementFromValues,
  parseRegQuery,
  installedVersions,
  readScheme,
  buildTokenRules,
  buildTheme,
  SCOPE_MAP,
};
