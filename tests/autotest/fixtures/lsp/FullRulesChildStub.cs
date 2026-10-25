// Test-only stand-in for the `lint <file> --json` child of `lsp --full-rules`
// (env DRAGLINT_FULLRULES_CHILD_EXE). Compiled by run_lsp_full_rules_guard.ps1 with csc.
// STUB_MARKER = file to create (proves the child was this stub);
// STUB_MODE = sleep | badjson | emit (emit prints the file named by STUB_JSON_FILE, exit 1
// like a `lint` that reports findings).
using System;
using System.IO;
using System.Threading;
static class FullRulesChildStub {
  static int Main() {
    string marker = Environment.GetEnvironmentVariable("STUB_MARKER");
    if (!String.IsNullOrEmpty(marker)) File.WriteAllText(marker, "ran");
    string mode = Environment.GetEnvironmentVariable("STUB_MODE");
    if (mode == "sleep") { Thread.Sleep(60000); return 0; }
    if (mode == "badjson") { Console.Out.Write("this is not json"); return 0; }
    if (mode == "emit") { Console.Out.Write(File.ReadAllText(Environment.GetEnvironmentVariable("STUB_JSON_FILE"))); return 1; }
    return 3;
  }
}
