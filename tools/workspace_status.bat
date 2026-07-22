ECHO OFF

echo STABLE_STAMP_VALUE stable
echo VOLATILE_STAMP_VALUE volatile
REM Fixed stand-in for a commit-derived source-date epoch (real builds:
REM `git log -1 --format=%%ct`). STABLE_ puts it in the stable status file,
REM part of the action cache key, so a given commit stays reproducible.
echo STABLE_SOURCE_DATE_EPOCH 1234567890
