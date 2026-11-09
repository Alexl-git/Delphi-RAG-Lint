/* tsparse: parse one file with a parser DLL and print its tree as an S-expression.
   usage: tsparse <dll> <symbol> <file> [fromRow toRow]   (rows 1-based; only nodes overlapping the range are printed)
   The gate's own instrument (lanes 147 GP / 148 GX / 148 G7); committed 149 GR. */
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
static const char *src; static unsigned r0 = 0, r1 = 0xFFFFFFFFu; static long errs = 0;
static void pr(TSNode n, int depth) {
  unsigned sr = ts_node_start_point(n).row, er = ts_node_end_point(n).row;
  if (er < r0 || sr > r1) return;
  if (ts_node_is_error(n)) errs++;
  int named = ts_node_is_named(n);
  if (!named && !ts_node_is_missing(n) && ts_node_child_count(n) == 0 && depth > 0) {
    unsigned a = ts_node_start_byte(n), b = ts_node_end_byte(n);
    printf("%*s'%.*s'\n", depth * 2, "", (int)(b - a), src + a);
    return;
  }
  printf("%*s(%s%s %u:%u-%u:%u", depth * 2, "", ts_node_type(n), ts_node_is_missing(n) ? " MISSING" : "",
         sr + 1, ts_node_start_point(n).column, er + 1, ts_node_end_point(n).column);
  uint32_t k = ts_node_child_count(n);
  if (k == 0) {
    unsigned a = ts_node_start_byte(n), b = ts_node_end_byte(n);
    if (b - a <= 40) printf(" '%.*s'", (int)(b - a), src + a);
  } else {
    printf("\n");
    for (uint32_t i = 0; i < k; i++) pr(ts_node_child(n, i), depth + 1);
    printf("%*s", depth * 2, "");
  }
  printf(")\n");
}
int main(int argc, char **argv) {
  if (argc < 4) return 2;
  const TSLanguage *l = load(argv[1], argv[2]);
  TSParser *p = ts_parser_new(); ts_parser_set_language(p, l);
  FILE *f = fopen(argv[3], "rb"); if (!f) return 3;
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  char *buf = malloc(n + 1); uint32_t len = (uint32_t)fread(buf, 1, n, f); fclose(f); buf[len] = 0; src = buf;
  if (argc >= 6) { r0 = (unsigned)atoi(argv[4]) - 1; r1 = (unsigned)atoi(argv[5]) - 1; }
  TSTree *t = ts_parser_parse_string(p, NULL, buf, len);
  pr(ts_tree_root_node(t), 0);
  printf("ERRORS_IN_RANGE=%ld\n", errs);
  return 0;
}
