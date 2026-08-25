# Privacy

## Summary

Your documents never leave your device. There is no account, no cloud, no
telemetry, and no AI.

## What is stored, and where

| Data | Location | Notes |
|---|---|---|
| Imported PDF copies | app Application Support directory | content-addressed |
| Library index (names, sizes, favourites, recents) | local SQLite | never transmitted |
| Settings | local | never transmitted |

The database lives in **Application Support**, not Documents. On iOS the app
enables Files-app visibility for its Documents folder, and placing the database
there would let a user delete their entire library by accident.

## What is logged

Logs are local-only and never transmitted. Each record carries operation, start
and end time, file size, result, and error code.

## What is never logged

- PDF content or extracted text
- Passwords
- Filenames or file paths
- Document titles

File identity appears in logs only as a truncated SHA-256 hash. The logging API
accepts `fileHash`, not `fileName`, so leaking identity requires deliberate
effort rather than a moment's inattention.

## Network access

None. The application functions with networking fully disabled.

## Third-party services

None. No analytics SDK, no crash reporter, no advertising identifier.
