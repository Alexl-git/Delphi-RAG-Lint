@echo off
REM Build the ConvRulesEditor console test runner (Win64) from THIS checkout.
REM
REM This name is kept because older docs and plans reference it. It used to hard-code
REM C:\Projects\Delphi-RAG-lint\src\tools\convrules-editor\tests, so running it from a
REM worktree compiled the MAIN checkout's tests and reported BUILD_EXITCODE=0 for source
REM that was never touched. It now forwards to the checkout-relative twin, which is the
REM single source of truth.
call "%~dp0_build_convrules_tests_local.bat" %*
exit /b %errorlevel%
