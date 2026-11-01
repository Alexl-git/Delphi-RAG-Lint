// Test-only stand-in for the `lint <file> --json` child of `lsp --full-rules`
// (env DRAGLINT_FULLRULES_CHILD_EXE). Compiled by run_lsp_full_rules_guard.ps1 with csc.
// STUB_MARKER = file to create (proves the child was this stub);
// STUB_MODE = sleep | badjson | emit (emit prints the file named by STUB_JSON_FILE, exit 1
// like a `lint` that reports findings; slowemit sleeps STUB_SLEEP_MS first -- LSP C12).
using System;
using System.IO;
using System.Threading;
static class FullRulesChildStub {
  static int Main() {
    string marker = Environment.GetEnvironmentVariable("STUB_MARKER");
    if (!String.IsNullOrEmpty(marker)) File.WriteAllText(marker, "ran");
    string argvFile = Environment.GetEnvironmentVariable("STUB_ARGV_FILE");
    if (!String.IsNullOrEmpty(argvFile)) File.WriteAllLines(argvFile, Environment.GetCommandLineArgs());  // LSP C15: one argument per line
    string mode = Environment.GetEnvironmentVariable("STUB_MODE");
    if (mode == "sleep") { Thread.Sleep(60000); return 0; }
    if (mode == "badjson") { Console.Out.Write("this is not json"); return 0; }
    if (mode == "slowemit") { Thread.Sleep(Int32.Parse(Environment.GetEnvironmentVariable("STUB_SLEEP_MS"))); mode = "emit"; }
    // 1.40 lsp lane: burnemit = a SLOW but WORKING child (burns CPU STUB_SLEEP_MS, then emits); a stall budget must not kill it.
    if (mode == "burnemit") {
      var sw = System.Diagnostics.Stopwatch.StartNew(); long x = 0;
      while (sw.ElapsedMilliseconds < Int32.Parse(Environment.GetEnvironmentVariable("STUB_SLEEP_MS"))) x++;
      mode = "emit";
    }
    if (mode == "emit") {
      string json = File.ReadAllText(Environment.GetEnvironmentVariable("STUB_JSON_FILE"));
      // @@E@@ = a non-ASCII char (e-acute): written as UTF-8 only when the caller asked --output-encoding utf8, else '?' like the real engine's ascii default
      bool utf8 = String.Join(" ", Environment.GetCommandLineArgs()).Contains("--output-encoding utf8");
      byte[] bytes = new System.Text.UTF8Encoding(false).GetBytes(json.Replace("@@E@@", utf8 ? "\u00e9" : "?"));
      using (var so = Console.OpenStandardOutput()) so.Write(bytes, 0, bytes.Length);
      return 1;
    }
    return 3;
  }
}
