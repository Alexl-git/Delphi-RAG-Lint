/* tsdiff: parse every file of a list with two parser DLLs and compare the trees.
   usage: tsdiff <oldDll> <newDll> <symbol> <list.txt> <out.tsv>
   out: path \t oldErr \t newErr \t same \t regions
   region = row:oldType>newType:dExprIf:dIfElse  (d = new count - old count inside the region) */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tree_sitter/api.h"

typedef const TSLanguage *(*LangFn)(void);

static const TSLanguage *load(const char *dll, const char *sym) {
  HMODULE h = LoadLibraryA(dll);
  if (!h) { fprintf(stderr, "cannot load %s\n", dll); exit(2); }
  LangFn f = (LangFn)GetProcAddress(h, sym);
  if (!f) { fprintf(stderr, "no %s in %s\n", sym, dll); exit(2); }
  return f();
}

static int count_type(TSNode n, const char *t) {
  int c = strcmp(ts_node_type(n), t) == 0;
  uint32_t k = ts_node_child_count(n);
  for (uint32_t i = 0; i < k; i++) c += count_type(ts_node_child(n, i), t);
  return c;
}

static FILE *out;
static int nregions;

static void region(TSNode a, TSNode b) {
  int dx = count_type(b, "exprIf") - count_type(a, "exprIf");
  int di = count_type(b, "ifElse") - count_type(a, "ifElse");
  fprintf(out, "%s%u:%s>%s:%d:%d", nregions ? ";" : "", ts_node_start_point(a).row + 1,
          ts_node_type(a), ts_node_type(b), dx, di);
  nregions++;
}

static int streq(const char *x, const char *y) {
  if (!x || !y) return x == y;
  return strcmp(x, y) == 0;
}

static void cmp(TSNode a, TSNode b) {
  uint32_t k = ts_node_child_count(a);
  if (strcmp(ts_node_type(a), ts_node_type(b)) || ts_node_start_byte(a) != ts_node_start_byte(b) ||
      ts_node_end_byte(a) != ts_node_end_byte(b) || k != ts_node_child_count(b) ||
      ts_node_is_missing(a) != ts_node_is_missing(b)) { region(a, b); return; }
  for (uint32_t i = 0; i < k; i++) {
    if (!streq(ts_node_field_name_for_child(a, i), ts_node_field_name_for_child(b, i))) { region(a, b); return; }
  }
  for (uint32_t i = 0; i < k; i++) cmp(ts_node_child(a, i), ts_node_child(b, i));
}

static char *slurp(const char *p, uint32_t *len) {
  FILE *f = fopen(p, "rb");
  if (!f) return NULL;
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  char *buf = malloc(n + 1);
  *len = (uint32_t)fread(buf, 1, n, f);
  fclose(f);
  return buf;
}

int main(int argc, char **argv) {
  if (argc < 6) { fprintf(stderr, "usage: tsdiff oldDll newDll symbol list out\n"); return 2; }
  const TSLanguage *lo = load(argv[1], argv[3]), *ln = load(argv[2], argv[3]);
  TSParser *po = ts_parser_new(), *pn = ts_parser_new();
  ts_parser_set_language(po, lo); ts_parser_set_language(pn, ln);
  FILE *lst = fopen(argv[4], "r");
  out = fopen(argv[5], "w");
  char line[4096];
  int files = 0, oldFail = 0, newFail = 0, diff = 0, missing = 0;
  while (fgets(line, sizeof line, lst)) {
    size_t L = strlen(line);
    while (L && (line[L - 1] == '\n' || line[L - 1] == '\r' || line[L - 1] == ' ')) line[--L] = 0;
    if (!L) continue;
    uint32_t len; char *src = slurp(line, &len);
    if (!src) { missing++; continue; }
    files++;
    TSTree *to = ts_parser_parse_string(po, NULL, src, len);
    TSTree *tn = ts_parser_parse_string(pn, NULL, src, len);
    TSNode ro = ts_tree_root_node(to), rn = ts_tree_root_node(tn);
    int eo = ts_node_has_error(ro), en = ts_node_has_error(rn);
    oldFail += eo; newFail += en;
    fprintf(out, "%s\t%d\t%d\t", line, eo, en);
    long pos = ftell(out);
    nregions = 0;
    fprintf(out, "?\t");
    cmp(ro, rn);
    fprintf(out, "\n");
    if (nregions) diff++;
    (void)pos;
    ts_tree_delete(to); ts_tree_delete(tn); free(src);
  }
  fclose(out);
  printf("files=%d missing=%d oldFail=%d newFail=%d treeDiff=%d\n", files, missing, oldFail, newFail, diff);
  return 0;
}
