# PureVoice Delivery Roadmap

## Purpose

The confirmed design contains three independently deployable systems. Each system gets its own implementation plan and release gate so the offline reader can ship without waiting for backend work.

## Delivery Sequence

1. **V1 Offline Core**
   - Native SwiftUI application based on the Stitch project.
   - TXT, EPUB, and approved non-DRM MOBI import.
   - Readium visual reader, Apple system TTS, local persistence, and core VoiceOver support.
   - Detailed plan: `docs/superpowers/plans/2026-07-14-v1-offline-reader.md`.

2. **V1.1 Cloud Refinement**
   - StoreKit consumable credits, explicit upload consent, LLM cleanup, result comparison, version restoration, and 24-hour deletion.
   - Write the detailed plan only after selecting the backend runtime, object storage, LLM provider, and receipt-validation service.

3. **V2 Web Transfer**
   - App-scoped transfer identity, temporary pairing codes, web upload, device inbox, and 72-hour expiry.
   - Write the detailed plan only after selecting hosting, storage, abuse controls, and operational ownership.

## Release Gates

- V1 ships only after the VoiceOver core-task audit passes on physical devices.
- MOBI enters V1 only after the license ADR is approved and representative MOBI/KF8 files pass the conversion suite. EPUB and TXT work remains releasable independently.
- V1.1 cannot delay offline reading or require an account.
- V2 transfer identity remains separate from purchases and Apple transaction data.
