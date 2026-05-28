@echo off
setlocal
set HERE=%~dp0
set FAILED=0

REM Pin cwd to repo root for the entire suite so relative paths inside
REM fixtures (e.g. T3 reads tests\fixtures\Docs.pas; T7 writes tests\t7.sqlite)
REM resolve consistently regardless of where the stitcher is invoked.
pushd "%HERE%.."

echo === T1: schema v4 ===
call "%HERE%fixtures\T1_schema.bat" || set FAILED=1

echo === T2: typecheck ===
"%HERE%fixtures\T2_typecheck.exe" || set FAILED=1

echo === T3: region scanner ===
"%HERE%fixtures\T3_regions.exe" || set FAILED=1

echo === T4: XMLDoc parser ===
"%HERE%fixtures\T4_xmldoc.exe" || set FAILED=1

echo === T5: PasDoc parser ===
"%HERE%fixtures\T5_pasdoc.exe" || set FAILED=1

echo === T6: dispatch ===
"%HERE%fixtures\T6_dispatch.exe" || set FAILED=1

echo === T7: storage roundtrip ===
"%HERE%fixtures\T7_storage.exe" || set FAILED=1

echo === T8: end-to-end indexing ===
call "%HERE%fixtures\T8_e2e.bat" || set FAILED=1

echo === T9: CLI hover ===
call "%HERE%fixtures\T9_hover.bat" || set FAILED=1

echo === T10: CLI find ===
call "%HERE%fixtures\T10_find.bat" || set FAILED=1

echo === T11: MCP tools ===
call "%HERE%fixtures\T11_mcp.bat" || set FAILED=1

echo === T12: LSP hover ===
call "%HERE%fixtures\T12_lsp.bat" || set FAILED=1

echo === T13: docs config ===
call "%HERE%fixtures\T13_config.bat" || set FAILED=1

echo.
echo === Stop criteria: self-corpus doc coverage ===
del /q "%HERE%draglint_self.sqlite" 2>NUL
"%HERE%..\third_party\dll\drag-lint.exe" index "%HERE%..\src" --db "%HERE%draglint_self.sqlite" >NUL
python -c "import sqlite3,sys; print('symbol_docs with summary:', sqlite3.connect(sys.argv[1]).execute('SELECT COUNT(*) FROM symbol_docs WHERE summary IS NOT NULL').fetchone()[0])" "%HERE%draglint_self.sqlite"

popd

if %FAILED%==1 (
  echo.
  echo *** TESTS FAILED ***
  exit /b 1
)
echo.
echo *** ALL v0.16 TESTS PASS ***
