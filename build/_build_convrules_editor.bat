@echo off
REM Build ConvRulesEditor.exe (Win64) from THIS checkout, then stage to dll-win64.
REM
REM This name is kept because older docs and plans reference it. It used to hard-code
REM C:\Projects\Delphi-RAG-lint for both the cd and the staging copy, so running it from
REM a worktree built and staged the MAIN checkout while still printing BUILD_EXITCODE=0
REM -- green evidence for code that was never compiled. Rather than keep a second copy of
REM the recipe that can drift out of step again, it now forwards to the checkout-relative
REM twin, which is the single source of truth.
call "%~dp0_build_convrules_editor_local.bat" %*
exit /b %errorlevel%
