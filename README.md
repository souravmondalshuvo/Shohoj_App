# Shohoj

University life, made simple. Shohoj is a Flutter app for BRAC University students with academic tools for CGPA tracking, course reviews, planning, and difficulty insights.

## Features

- Google/Firebase sign-in restricted to `user.name@g.bracu.ac.bd` accounts
- CGPA calculator with semester and course tracking
- Degree progress tracker by department
- Course and faculty reviews backed by Firestore
- Grade playground and reverse CGPA solver
- Semester planner with course search
- Course difficulty map from student reviews
- Adaptive UI: iOS liquid-glass styling and Android Material navigation

## Tech Stack

- Flutter / Dart
- Firebase Core
- Firebase Auth
- Cloud Firestore
- Google Sign-In
- Provider

## Setup

Install dependencies:

```bash
flutter pub get
```

Run the app:

```bash
flutter run
```

Run checks:

```bash
flutter analyze
flutter test
flutter build ios --simulator --debug
```

## Firebase

Firebase is configured through:

- `firebase.json`
- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

The platform Firebase config files contain API keys and are intentionally ignored by git. Regenerate them with FlutterFire when needed:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

### Firestore rules and indexes

This app shares the `shohoj` Firebase project with the Shohoj web app. Firestore
rules and indexes are owned by the **web repo** and must only ever be deployed
from there.

A rules deploy replaces the entire ruleset rather than merging, so deploying
from this repo would silently wipe the web app's security model. `firebase.json`
here deliberately declares no `firestore` block, and `firestore.rules` /
`firestore.indexes.json` are gitignored so a stray local copy cannot be picked
up.

When the app needs access to a new collection, change the rules in the web repo
and deploy from there.

## Auth Rules

Shohoj only allows Google accounts ending with:

```text
@g.bracu.ac.bd
```

The app checks this after Google account selection and again after Firebase sign-in. Rejected users are signed out immediately.

## Per-machine Xcode settings

`ios/Flutter/Debug.xcconfig` and `Release.xcconfig` end with an optional
`#include? "Local.xcconfig"`. That file is gitignored, so anything in it applies
only to your machine. Copy `ios/Flutter/Local.xcconfig.example` to get started.

The case this exists for: if the repo lives in an iCloud-synced folder
(`~/Documents`, `~/Desktop`), Xcode code signing fails on extended attributes
the sync daemon attaches to files under the build directory. Redirecting
`FLUTTER_BUILD_DIR` outside the synced tree avoids it.

Keep machine-specific paths out of the committed xcconfigs — they are relative
to the repo, so they resolve somewhere arbitrary on any other checkout and make
an iOS CI job impossible.

## iOS Notes

The iOS app uses a platform-adaptive liquid-glass style for cards and tab navigation. Simulator builds disable simulator-only code signing to avoid macOS extended-attribute signing failures while keeping real-device signing available.

## Project Structure

```text
lib/
  data/        Course catalog and department metadata
  models/      Course and semester models
  screens/     App feature screens
  services/    Auth and Firestore services
  theme/       App theme
  widgets/     Shared UI widgets
```
