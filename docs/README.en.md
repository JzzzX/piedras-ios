# Piedras

`Piedras / 椰子面试` is an iOS-first AI notes project for conversations, meetings, podcasts, interviews, and other long-form audio workflows.

The goal is not just speech-to-text. The project is built around the full loop after capture:

- turning audio into readable transcripts
- writing notes while listening
- shaping raw content into structured summaries
- asking follow-up questions against a single note
- gradually building searchable personal context from past records

This repository is both an open-source portfolio project and a buildable product system.

## Product Direction

The product is based on a few simple beliefs:

- transcription is the starting point, not the outcome
- notes are part of the thinking process, not an attachment
- AI should amplify organization and retrieval, not merely replace note-taking
- the iOS experience should stay lightweight enough to feel immediate

That is why the repository is structured as a combined system:

- an `iOS app` for capture, browsing, editing, playback, and note-level Q&A
- a `cloud API` for AI workflows, sync, export, and orchestration
- an `ASR proxy` for real-time transcription connectivity

## Highlights

- Native iOS recording and transcription flow
- Detail view built around title, transcript, structured notes, and attachments
- Dedicated transcript panel for focused review
- AI-enhanced notes and note-scoped Q&A
- Historical record list with organizational structure
- Full-stack repository including client, API, and transcription proxy

## Screenshots

| Home | Transcript |
| --- | --- |
| ![Piedras home list](../.github/assets/screenshots/01-home-list.png) | ![Piedras note detail transcript](../.github/assets/screenshots/02-note-detail-transcript.png) |

| Recording | Chat with note |
| --- | --- |
| ![Piedras recording live](../.github/assets/screenshots/03-recording-live.png) | ![Piedras chat with note](../.github/assets/screenshots/04-chat-with-note.png) |

## Repository Layout

- `CocoInterview/`: SwiftUI iOS client
- `CocoInterviewRecordingWidget/`: widget / Live Activity target
- `CocoInterviewTests/`: unit tests
- `CocoInterviewUITests/`: UI flow tests
- `cloud/api/`: Next.js + Prisma backend
- `cloud/asr-proxy/`: standalone ASR WebSocket proxy
- `docs/`: supporting documentation
- `scripts/`: build and validation helpers

## Engineering Notes

### iOS

- SwiftUI-based product surface
- local-first interaction model
- state and screen design centered on real user flows
- widget and Live Activity support

### Cloud API

- Next.js
- Prisma
- PostgreSQL
- server-side capabilities for AI summarization, Q&A, sync, and export

### Speech / AI

- real-time ASR proxy pipeline
- structured AI note generation
- note-scoped question answering
- room for future cross-note retrieval and knowledge workflows

## Local Development

Build the iOS app:

```sh
xcodebuild -project CocoInterview.xcodeproj -scheme CocoInterview -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Run iOS tests:

```sh
xcodebuild test -project CocoInterview.xcodeproj -scheme CocoInterview -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Start the cloud API:

```sh
cd cloud/api
npm install
npx prisma generate
npm run dev
```

Build the cloud API:

```sh
cd cloud/api
npm run build
```

Smoke-test the ASR chain:

```sh
say -o tmp-asr-sample.aiff "Hello, this is a Piedras transcription smoke test."
afconvert -f WAVE -d LEI16 tmp-asr-sample.aiff tmp-asr-sample.wav
node scripts/asr_smoke_test.mjs tmp-asr-sample.wav http://127.0.0.1:3000
```

## Configuration

- The iOS app reads the backend URL from `COCO_INTERVIEW_BACKEND_BASE_URL`
- The ASR smoke test reads the backend URL from `COCO_INTERVIEW_BACKEND_URL`
- No production backend URL is baked into this public repository

## Roadmap

- improve real-time transcription resilience
- refine the unified record / edit / playback detail flow
- strengthen Q&A quality across current and historical notes
- expand attachment, sharing, export, and archive capabilities
- continue unifying project branding around `Piedras`
- move the project from a strong prototype toward a more complete product

## Known Limitations

- the product and repository are still evolving quickly
- the full experience depends on external backend and ASR services
- AI and speech features are sensitive to third-party availability, cost, and network quality
- today the repository is best understood as a portfolio-grade product system rather than a turnkey public SaaS
