# Vocabulary Builder — Learn English (iOS)

A SwiftUI client for the [Vocabulary Learner](../docs) API. Browse, study, and
quiz English ↔ Vietnamese vocabulary, plus an OCR flow that turns a photo of
a page into saved words.

This is the iOS port described in
[`../docs/IOS_PORTING_GUIDE.md`](../docs/IOS_PORTING_GUIDE.md). It is built
end-to-end on this Ubuntu box with [xtool](https://github.com/xtool-org/xtool)
and installed onto the device through SideStore's on-device signing.

## Features

- **Sign in / sign up** with the same backend the web app uses
  (`POST /api/auth/sign-up`, `POST /api/auth/sign-in`).
  `GET /api/auth/session` always returns 401, so the user object from
  sign-in is persisted to `UserDefaults` instead.
- **Home** — greeting, stat circles (WORDS / WEAK / KNOWN), upload-photo pill,
  recent words.
- **Library** — search, category filter, multi-select delete, swipe-delete,
  server-side sort order (`updatedAt ?? createdAt` desc, then alphabetical).
- **Word detail** — full record, IPA, definition, translation, example,
  progress, edit / delete.
- **Word editor** — create / edit, image attach (compressed to ≤ 1280 px /
  500 KB), per-field AI enrich via `POST /api/ai/enrich-word`.
- **Collections** — list + detail, create, delete, member word lists.
- **Study** — flashcard mode with four filters (all / weak / collection /
  category), tap-to-reveal, `AVSpeechSynthesizer` pronounces the headword,
  marks `studyCount` + `lastSeenAt` on the server.
- **Quiz** — three modes (`Word → Definition`, `Definition → Word`,
  `Fill in the gap`) backed by `POST /api/quiz/ensure` with
  `candidateWords` / `candidateDefinitions` so the offline fallback
  produces real distractors. Mastery logic is client-side: a wrong answer
  sets `isWeak = true`, a correct answer at `strongThreshold` clears it.
- **OCR** — five-step wizard (`upload` → `extracting` → `pick` → `edit` →
  `done`) that takes a photo, calls `POST /api/ai/extract-from-image`,
  lets the user pick which words to import, optionally enriches each one
  with `POST /api/ai/enrich-word`, then `POST /api/words` to save.
- **Generate** — `POST /api/ai/generate-collection` with subject + count,
  preview, multi-select import.
- **Settings** — study thresholds + CEFR level via
  `GET`/`PUT /api/users/{id}/settings`; storage usage via
  `GET /api/storage/usage`; export of words + collections + progress as
  JSON; **Erase all data** via `DELETE /api/account/data` with a
  confirmation dialog; configurable base URL.

## Project layout

```
VocabularyBuilder/
├── VocabularyBuilderApp.swift              @main, injects APIClient + stores
├── RootView.swift                   AuthView ↔ ContentView switch
├── ContentView.swift                5-tab TabView
├── Core/
│   ├── AppSettings.swift            base URL + onboarding (UserDefaults)
│   ├── APIError.swift               error type, 500 empty-body handling
│   ├── APIModels.swift              Codable DTOs mirroring openapi.yaml
│   ├── APIClient.swift              URLSession actor
│   ├── Speech.swift                 AVSpeechSynthesizer wrapper
│   ├── ImageCache.swift             NSCache-backed image cache
│   └── ImageProcessor.swift         1280 px / 500 KB JPEG compressor
├── DesignSystem/
│   ├── Theme.swift                  tokens (teal[700] = #00796B, etc.)
│   ├── Components.swift             Chip, StatCircle, Card, ErrorBanner, …
│   └── MultiLineTextField.swift     iOS 15 UITextView wrapper
├── Stores/
│   ├── SessionStore.swift           persisted user
│   └── LibraryStore.swift           shared words / collections / progress
└── Features/
    ├── Auth/        AuthView.swift
    ├── Home/        HomeView.swift
    ├── Library/     LibraryView.swift, WordDetailView.swift, WordEditorView.swift
    ├── Collections/ CollectionsView.swift, CollectionDetailView.swift
    ├── Study/       StudyView.swift
    ├── Quiz/        QuizView.swift
    ├── Settings/    SettingsView.swift
    └── OCR/         OcrFlowView.swift, ImagePicker.swift, GenerateView.swift
VocabularyBuilderTests/      XCTest target (model decoders + store smoke tests)
.build/linux-ios/     xtool workspace (Package.swift + xtool.yml + Info.plist)
```

The previous local-first architecture (bundled `words.json`,
`UserDefaults`-backed per-word status) has been removed entirely. The server
is the source of truth.

## Build

Prerequisites (already installed on this Ubuntu box): Swift 6.3.3, xtool, the
iOS SDK at `~/.swiftpm/swift-sdks/`, `actool`, `pymobiledevice3`.

```bash
./build.sh --release --ipa           # produces releases/VocabularyBuilder.ipa
./build.sh --release --ipa --serve   # also starts an HTTP server on :8080
```

## Install on the iPhone

Either:
- `./build.sh --release --ipa --serve` then open the printed URL in Safari
  on the iPhone and share → **Open in SideStore**, or
- push to `main` and let CI publish the IPA as a GitHub Release, then open
  the SideStore install URL on the iPhone.

## ATS

The API is served as plain HTTP over Tailscale. A scoped ATS exception
for the Tailscale MagicDNS hostname is configured in
[`.build/linux-ios/Info.plist`](.build/linux-ios/Info.plist):

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSExceptionDomains</key>
  <dict>
    <key>bao-thinkcentre-m93p.tail2c53fc.ts.net</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key>
      <true/>
      <key>NSIncludesSubdomains</key>
      <false/>
    </dict>
    <key>localhost</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key>
      <true/>
    </dict>
  </dict>
</dict>
```

The default base URL in `AppSettings` matches the hostname above. Override
it in **Settings → API** if the Tailscale address changes.

## Configuration

| Key | Default | Description |
| --- | --- | --- |
| `vocabulary.baseURL` | `http://bao-thinkcentre-m93p.tail2c53fc.ts.net:2001` | API base URL |
| `vocabulary.session.user` | unset | Encoded `AuthUser` blob |
| `vocabulary.hasCompletedOnboarding` | `false` | Onboarding flag |

## Bundle ID / app name

- Bundle ID: `dev.baodoan.vocabulary_builder`
- App display name: `vocabulary_builder` (lowercase, with underscore)
- Min iOS: 15.0 (works on iPhone 11 / iOS 15.7)
- Targets: iPhone + iPad
