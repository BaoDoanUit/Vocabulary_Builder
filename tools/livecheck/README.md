# livecheck

Verifies the **import → library** flow against the live server, using the
app's real `APIClient` and real `LibraryStore` — the exact code path the
OCR import runs. It needs no device and no simulator, so it can be run
from a plain Linux box.

## Usage

```bash
tools/livecheck/run.sh                                  # default backend
tools/livecheck/run.sh http://my-host:2001               # another backend
```

## What it checks

1. **Sign-up** succeeds — the step that used to report
   `resource exceeds maximum size`.
2. **`GET /api/words`** succeeds — a bodyless GET must not carry a body
   (`NSURLErrorDomain Code=-1103`).
3. **`POST /api/words`** succeeds.
4. The imported word is **in the local store immediately** — the bug this
   whole flow was about: the OCR flow used to call `api.createWord`
   directly, so the word reached the server but never reached the
   LibraryStore, and the Library tab kept showing a stale list.
5. The word is **still there after a re-fetch** from the server.
6. The word is deleted again, so the server is left as it was.

## How it works

`Combine` does not exist on Linux, so this package provides a small
stand-in and copies the app's Foundation-only sources into a scratch
directory. The copies are patched in two places — the `Combine` import
and `URLSession`/`FoundationNetworking` — and nothing in the app itself
is modified.
