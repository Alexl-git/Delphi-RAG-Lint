/* tserr: per file, ERROR node count, MISSING count and bytes under outermost ERROR nodes, old vs new DLL.
   usage: tserr oldDll newDll symbol list out [dump] ; out: path \t oErr \t nErr \t oMiss \t nMiss \t oBytes \t nBytes
   any 6th argument = dump mode: every outermost ERROR node (rows, bytes) of both trees goes to stdout, prefixed 1 (old) / 2 (new). */
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
static int dump = 0;
static void walk(TSNode n, int inErr, long *err, long *miss, long *bytes) {
  int e = ts_node_is_error(n);
  if (e) { (*err)++; if (!inErr) { *bytes += ts_node_end_byte(n) - ts_node_start_byte(n); if (dump) printf("%d ERR rows %u-%u bytes %u\n", dump, ts_node_start_point(n).row + 1, ts_node_end_point(n).row + 1, ts_node_end_byte(n) - ts_node_start_byte(n)); } }
  if (ts_node_is_missing(n)) (*miss)++;
  uint32_t k = ts_node_child_count(n);
  for (uint32_t i = 0; i < k; i++) walk(ts_node_child(n, i), inErr || e, err, miss, bytes);
}
int main(int argc, char **argv) {
  if (argc < 6) return 2;
  const TSLanguage *lo = load(argv[1], argv[3]), *ln = load(argv[2], argv[3]);
  TSParser *po = ts_parser_new(), *pn = ts_parser_new();
  ts_parser_set_language(po, lo); ts_parser_set_language(pn, ln);
  FILE *lst = fopen(argv[4], "r"), *out = fopen(argv[5], "w");
  char line[4096];
  while (fgets(line, sizeof line, lst)) {
    size_t L = strlen(line);
    while (L && (line[L-1] == '\n' || line[L-1] == '\r' || line[L-1] == ' ')) line[--L] = 0;
    if (!L) continue;
    FILE *f = fopen(line, "rb"); if (!f) continue;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *src = malloc(n + 1); uint32_t len = (uint32_t)fread(src, 1, n, f); fclose(f);
    TSTree *to = ts_parser_parse_string(po, NULL, src, len), *tn = ts_parser_parse_string(pn, NULL, src, len);
    long oe = 0, om = 0, ob = 0, ne = 0, nm = 0, nb = 0;
    dump = argc > 6 ? 1 : 0; walk(ts_tree_root_node(to), 0, &oe, &om, &ob); dump = argc > 6 ? 2 : 0; walk(ts_tree_root_node(tn), 0, &ne, &nm, &nb);
    fprintf(out, "%s\t%ld\t%ld\t%ld\t%ld\t%ld\t%ld\n", line, oe, ne, om, nm, ob, nb);
    ts_tree_delete(to); ts_tree_delete(tn); free(src);
  }
  fclose(out); return 0;
}