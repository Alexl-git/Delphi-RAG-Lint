/* tsblank: same-length comment blanker + before/after parse measurement for tree-sitter-delphi13.
   The blanker replaces every byte of every comment (// to end of line, { ... }, (* ... *)) with a
   space, keeping CR and LF bytes, so the blanked text has the SAME length and every byte offset,
   row and column of the remaining tokens is unchanged. Compiler directives ({$...} and (*$...*))
   are NEVER blanked. String literals are honoured ('...' with '' doubling; a string never spans a
   line). Comments do not nest; the kind that opened decides the terminator (Delphi semantics).

   usage:
     tsblank blank <in.pas> <out.pas>             write the blanked copy (byte length identical)
     tsblank comments <in.pas>                    side table: startByte endByte row col kind text
     tsblank run <dll> <symbol> <list.txt> <out.tsv>
         per file: path  oErr  bErr  oMiss  bMiss  oBytes  bBytes  oHas  bHas  treeSame  class  firstErr
         oHas/bHas = ts_node_has_error(root) (ERROR or MISSING anywhere; the gate's "fails")
         oX = original text, bX = blanked text; Err = ERROR node count, Miss = MISSING node
         count, Bytes = bytes under the outermost ERROR nodes; treeSame = 1 when both trees are
         node-for-node identical once comment nodes are dropped (type + start + end byte);
         class = clean | comment | ifdef | gap | mixed | worse (see classify()); firstErr = the
         first 60 bytes of ORIGINAL text at the first outermost ERROR of the blanked tree,
         whitespace collapsed.
         stdout: files= oFail= bFail= newlyClean= improved= same= worse= treeDiffClean=
   Exit code 0; 2 on a usage or load error. 7-bit ASCII. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tree_sitter/api.h"

typedef const TSLanguage *(*LangFn)(void);
static const TSLanguage *load(const char *dll, const char *sym) {
  HMODULE h = LoadLibraryA(dll); if (!h) { fprintf(stderr, "cannot load %s\n", dll); exit(2); }
  LangFn f = (LangFn)GetProcAddress(h, sym); if (!f) { fprintf(stderr, "no %s\n", sym); exit(2); }
  return f();
}

static char *readfile(const char *path, uint32_t *len) {
  FILE *f = fopen(path, "rb"); if (!f) return 0;
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  char *s = malloc(n + 1); *len = (uint32_t)fread(s, 1, n, f); fclose(f); s[*len] = 0;
  return s;
}

/* ---- the blanker -------------------------------------------------------------------------- */
typedef struct { uint32_t start, end, row, col; char kind[4]; } Comment;

/* Blank the comment at s[i..end) in place (end exclusive), keeping CR/LF. */
static void blank_range(char *s, uint32_t i, uint32_t end) {
  for (; i < end; i++) if (s[i] != '\r' && s[i] != '\n') s[i] = ' ';
}

/* Scans src (len bytes). When out != NULL, writes the blanked copy into out (same length).
   When cb != NULL, calls cb(comment, ctx) for every comment found. Returns the comment count. */
static long scan(const char *src, uint32_t len, char *out, void (*cb)(const Comment *, void *), void *ctx) {
  long count = 0;
  uint32_t i = 0, row = 0, lineStart = 0;
  if (out) memcpy(out, src, len);
  while (i < len) {
    char c = src[i];
    if (c == '\n') { row++; lineStart = i + 1; i++; continue; }
    if (c == '\'') {                                  /* string literal: to the closing quote or EOL */
      i++;
      while (i < len && src[i] != '\'' && src[i] != '\n' && src[i] != '\r') i++;
      if (i < len && src[i] == '\'') i++;
      continue;
    }
    uint32_t start = i; const char *kind = 0; uint32_t end = 0;
    if (c == '/' && i + 1 < len && src[i + 1] == '/') {
      kind = (i + 2 < len && src[i + 2] == '/') ? "///" : "//";
      end = i + 2;
      while (end < len && src[end] != '\n' && src[end] != '\r') end++;
    } else if (c == '{') {
      if (i + 1 < len && src[i + 1] == '$') { i++; continue; }   /* directive: kept */
      kind = "{}";
      end = i + 1;
      while (end < len && src[end] != '}') end++;
      if (end < len) end++;                           /* include the closing brace */
    } else if (c == '(' && i + 1 < len && src[i + 1] == '*') {
      if (i + 2 < len && src[i + 2] == '$') { i += 2; continue; }   /* (*$...*) directive: kept */
      kind = "(*";
      end = i + 2;
      while (end + 1 < len && !(src[end] == '*' && src[end + 1] == ')')) end++;
      end = (end + 1 < len) ? end + 2 : len;          /* include the closing *) or run to EOF */
    }
    if (!kind) { i++; continue; }
    count++;
    if (cb) { Comment cm; cm.start = start; cm.end = end; cm.row = row; cm.col = start - lineStart; strcpy(cm.kind, kind); cb(&cm, ctx); }
    if (out) blank_range(out, start, end);
    /* advance over the comment, counting the rows it spans */
    for (uint32_t k = start; k < end; k++) if (src[k] == '\n') { row++; lineStart = k + 1; }
    i = end;
  }
  return count;
}

/* ---- tree metrics ------------------------------------------------------------------------- */
typedef struct { long err, miss, bytes; uint32_t firstStart, firstEnd; int haveFirst; int has; } Metrics;

/* has = ts_node_has_error(root): ERROR or MISSING anywhere -- the same "fails" tsdiff/the gate use. */
static void walk(TSNode n, int inErr, Metrics *m) {
  int e = ts_node_is_error(n);
  if (e) {
    m->err++;
    if (!inErr) {
      m->bytes += ts_node_end_byte(n) - ts_node_start_byte(n);
      if (!m->haveFirst) { m->haveFirst = 1; m->firstStart = ts_node_start_byte(n); m->firstEnd = ts_node_end_byte(n); }
    }
  }
  if (ts_node_is_missing(n)) m->miss++;
  uint32_t k = ts_node_child_count(n);
  for (uint32_t i = 0; i < k; i++) walk(ts_node_child(n, i), inErr || e, m);
}

/* Does any outermost ERROR node of the blanked tree span a conditional directive in the ORIGINAL text? */
static int span_has_cond_directive(const char *src, uint32_t a, uint32_t b) {
  for (uint32_t i = a; i + 3 < b; i++) {
    if (src[i] == '{' && src[i + 1] == '$') {
      char w[8]; unsigned n = 0; uint32_t k = i + 2;
      while (k < b && n < 7 && ((src[k] >= 'a' && src[k] <= 'z') || (src[k] >= 'A' && src[k] <= 'Z'))) { w[n++] = (char)(src[k] | 0x20); k++; }
      w[n] = 0;
      if (strncmp(w, "if", 2) == 0 || strcmp(w, "else") == 0 || strcmp(w, "elseif") == 0 || strcmp(w, "endif") == 0 || strcmp(w, "ifend") == 0) return 1;
    }
  }
  return 0;
}

/* The ERROR node of an ifdef-split construct is often 1 byte (`;`) with the {$ENDIF}/{$IFDEF} right
   beside it, so the directive test looks IFDEF_WINDOW bytes to each side of the ERROR span. */
#define IFDEF_WINDOW 160
typedef struct { const char *src; uint32_t len; int touch, total; } CondCtx;
static void classify_walk(TSNode n, int inErr, CondCtx *c) {
  int e = ts_node_is_error(n);
  if (e && !inErr) {
    uint32_t a = ts_node_start_byte(n), b = ts_node_end_byte(n);
    a = a > IFDEF_WINDOW ? a - IFDEF_WINDOW : 0; b = b + IFDEF_WINDOW < c->len ? b + IFDEF_WINDOW : c->len;
    c->total++; if (span_has_cond_directive(c->src, a, b)) c->touch++;
  }
  uint32_t k = ts_node_child_count(n);
  for (uint32_t i = 0; i < k; i++) classify_walk(ts_node_child(n, i), inErr || e, c);
}

static const char *classify(const Metrics *o, const Metrics *b, TSNode broot, const char *src, uint32_t len) {
  if (b->err > o->err) return "worse";
  if (o->err == 0 && b->err == 0) return "clean";
  if (b->err == 0) return "comment";
  CondCtx c = { src, len, 0, 0 };
  classify_walk(broot, 0, &c);
  if (c.touch == 0) return "gap";
  if (c.touch == c.total) return "ifdef";
  return "mixed";
}

/* Node-for-node comparison ignoring comment nodes (type name + start + end byte). */
static int is_comment(TSNode n) { return strcmp(ts_node_type(n), "comment") == 0; }
static int same_tree_at(TSNode a, TSNode b, int depth);
static int same_tree(TSNode a, TSNode b) { return same_tree_at(a, b, 0); }
/* depth 0 = the root: its start byte moves with a leading comment block (tree-sitter starts the root
   at the first token, extras included), so only its children are compared there. */
static int same_tree_at(TSNode a, TSNode b, int depth) {
  if (strcmp(ts_node_type(a), ts_node_type(b)) != 0) return 0;
  if (depth > 0 && (ts_node_start_byte(a) != ts_node_start_byte(b) || ts_node_end_byte(a) != ts_node_end_byte(b))) return 0;
  uint32_t ka = ts_node_child_count(a), kb = ts_node_child_count(b), ia = 0, ib = 0;
  for (;;) {
    while (ia < ka && is_comment(ts_node_child(a, ia))) ia++;
    while (ib < kb && is_comment(ts_node_child(b, ib))) ib++;
    if (ia >= ka || ib >= kb) return ia >= ka && ib >= kb;
    if (!same_tree_at(ts_node_child(a, ia), ts_node_child(b, ib), depth + 1)) return 0;
    ia++; ib++;
  }
}

static void snippet(const char *src, uint32_t len, uint32_t at, char *out, size_t cap) {
  size_t n = 0; int sp = 0;
  for (uint32_t i = at; i < len && n + 1 < cap; i++) {
    unsigned char c = (unsigned char)src[i];
    if (c == '\t' || c == '\r' || c == '\n' || c == ' ') { if (!sp && n) out[n++] = ' '; sp = 1; continue; }
    sp = 0; out[n++] = (c < 0x20 || c > 0x7e) ? '?' : (char)c;
  }
  out[n] = 0;
}

/* ---- commands ----------------------------------------------------------------------------- */
static void print_comment(const Comment *c, void *ctx) {
  const char *src = (const char *)ctx;
  char text[41]; size_t n = 0;
  for (uint32_t i = c->start; i < c->end && n < 40; i++) { unsigned char ch = (unsigned char)src[i]; text[n++] = (ch < 0x20 || ch > 0x7e) ? '?' : (char)ch; }
  text[n] = 0;
  printf("%u\t%u\t%u\t%u\t%s\t%s\n", c->start, c->end, c->row + 1, c->col + 1, c->kind, text);
}

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: tsblank blank in out | comments in | run dll symbol list out\n"); return 2; }
  if (strcmp(argv[1], "blank") == 0 && argc >= 4) {
    uint32_t len; char *src = readfile(argv[2], &len); if (!src) { fprintf(stderr, "cannot read %s\n", argv[2]); return 2; }
    char *out = malloc(len + 1); long n = scan(src, len, out, 0, 0);
    FILE *f = fopen(argv[3], "wb"); if (!f) return 2; fwrite(out, 1, len, f); fclose(f);
    printf("comments=%ld bytes=%u\n", n, len); return 0;
  }
  if (strcmp(argv[1], "comments") == 0) {
    uint32_t len; char *src = readfile(argv[2], &len); if (!src) { fprintf(stderr, "cannot read %s\n", argv[2]); return 2; }
    printf("start\tend\trow\tcol\tkind\ttext\n");
    long n = scan(src, len, 0, print_comment, src);
    fprintf(stderr, "comments=%ld\n", n); return 0;
  }
  if (strcmp(argv[1], "run") == 0 && argc >= 6) {
    const TSLanguage *lang = load(argv[2], argv[3]);
    TSParser *p = ts_parser_new(); ts_parser_set_language(p, lang);
    FILE *lst = fopen(argv[4], "r"), *out = fopen(argv[5], "w");
    if (!lst || !out) { fprintf(stderr, "cannot open list or out\n"); return 2; }
    long files = 0, oFail = 0, bFail = 0, newlyClean = 0, improved = 0, same = 0, worse = 0, treeDiffClean = 0;
    char line[4096];
    while (fgets(line, sizeof line, lst)) {
      size_t L = strlen(line);
      while (L && (line[L-1] == '\n' || line[L-1] == '\r' || line[L-1] == ' ')) line[--L] = 0;
      if (!L) continue;
      uint32_t len; char *src = readfile(line, &len); if (!src) continue;
      char *bl = malloc(len + 1); scan(src, len, bl, 0, 0);
      TSTree *to = ts_parser_parse_string(p, NULL, src, len);
      TSTree *tb = ts_parser_parse_string(p, NULL, bl, len);
      Metrics mo = {0}, mb = {0};
      walk(ts_tree_root_node(to), 0, &mo); walk(ts_tree_root_node(tb), 0, &mb);
      mo.has = ts_node_has_error(ts_tree_root_node(to)); mb.has = ts_node_has_error(ts_tree_root_node(tb));
      int ts = same_tree(ts_tree_root_node(to), ts_tree_root_node(tb));
      const char *cls = classify(&mo, &mb, ts_tree_root_node(tb), src, len);
      char snip[64] = ""; if (mb.haveFirst) snippet(src, len, mb.firstStart, snip, sizeof snip);
      /* fail = has_error (ERROR or MISSING), as the gate counts it; verdicts by ERROR node count,
         with has_error as the tie-breaker (a MISSING-only tree is not clean) */
      files++;
      if (mo.has) oFail++;
      if (mb.has) bFail++;
      if (mo.has && !mb.has) newlyClean++;
      else if (mb.err > mo.err || (!mo.has && mb.has)) { worse++; cls = "worse"; }
      else if (mb.err < mo.err || (mb.miss < mo.miss && mb.err == mo.err)) improved++;
      else if (mo.has) same++;
      if (!mo.has && !mb.has && !ts) treeDiffClean++;
      fprintf(out, "%s\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld\t%d\t%d\t%d\t%s\t%s\n", line, mo.err, mb.err, mo.miss, mb.miss, mo.bytes, mb.bytes, mo.has, mb.has, ts, cls, snip);
      ts_tree_delete(to); ts_tree_delete(tb); free(src); free(bl);
    }
    fclose(out); fclose(lst);
    printf("files=%ld oFail=%ld bFail=%ld newlyClean=%ld improved=%ld same=%ld worse=%ld treeDiffClean=%ld\n",
           files, oFail, bFail, newlyClean, improved, same, worse, treeDiffClean);
    return 0;
  }
  fprintf(stderr, "usage: tsblank blank in out | comments in | run dll symbol list out\n"); return 2;
}
