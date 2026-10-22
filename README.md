# Vocabulary — Learn English (iOS)

A minimal iOS app for studying English vocabulary with Vietnamese translations. Built with SwiftUI, packaged as an unsigned `.ipa` on Ubuntu via [xtool](https://github.com/xtool-org/xtool), and installed onto the device through SideStore's on-device signing.

## Features
- 70 curated English ↔ Vietnamese words across 9 categories (Greetings, Family, Food, Home, Time, Work, Travel, Animals, Colors, Numbers)
- **Words** tab — browse, search, filter by status (New / Learning / Known), reset progress
- **Study** tab — flashcard mode with tap-to-reveal, pronunciation, example sentences, and study deck that prioritizes unknown words
- **Quiz** tab — 10-question multiple-choice quiz that automatically updates word status based on your answers
- Progress persisted across launches via `UserDefaults`

## Project layout
```
Vocabulary/
├── VocabularyApp.swift      App entry, owns the WordStore
├── ContentView.swift        TabView (Words / Study / Quiz)
├── Word.swift               Data model
├── WordStore.swift          @MainActor ObservableObject; loads words.json, persists status
├── WordListView.swift       Browse, search, filter
├── FlashcardView.swift      Study mode
├── QuizView.swift           Quiz mode
├── words.json               Curated word list (the actual data)
└── Assets.xcassets/         AppIcon (open-book) + AccentColor
VocabularyTests/             XCTest target
.build/linux-ios/            xtool workspace (Package.swift + xtool.yml)
```

## Build

Prerequisites (already installed on this Ubuntu box): Swift 6.3.3, xtool, the iOS SDK at `~/.swiftpm/swift-sdks/`, `actool`, `pymobiledevice3`.

```bash
./build.sh --release --ipa           # produces releases/Vocabulary.ipa
./build.sh --release --ipa --serve   # also starts an HTTP server on :8080
```

## Install on the iPhone

Either:
- `./build.sh --release --ipa --serve` then open the printed URL in Safari on the iPhone and share → **Open in SideStore**, or
- push to `main` and let CI publish the IPA as a GitHub Release, then open the SideStore install URL on the iPhone

## Bundle ID / app name

- Bundle ID: `dev.baodoan.vocabulary`
- App display name: `vocabulary` (lowercase)
- Min iOS: 15.0 (works on iPhone 11 / iOS 15.7)
