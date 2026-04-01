# CLAUDE.md

This repository contains the iOS app for EmberSensor.

Project purpose:
- Display live wildfire risk status from the EmberSensor backend
- Show nearby fires on a map
- Alert the user when risk becomes high
- Keep the app simple, readable, and reliable

Current structure:
- `ContentView.swift` = main dashboard / status tab
- `FireMapView.swift` = map tab and nearby fire interactions
- `FireDetailCard.swift` = selected fire details
- `APIService.swift` = backend calls
- `FireStatus.swift` = status response model
- `FireMapModels.swift` = map/fire response models
- `EmberSensorApp.swift` = app entry point
- `NotificationDelegate.swift` = foreground notification presentation

Primary goals:
- Preserve existing behavior unless a change is explicitly requested
- Keep the app lightweight and easy to debug
- Keep backend API integration stable
- Prefer small, low-risk edits over broad rewrites

Rules:
- Do not change backend endpoint paths unless explicitly asked
- Do not rename decoded JSON fields unless the backend contract has changed
- Do not remove polling, notification behavior, or map behavior unless explicitly asked
- Do not hardcode secrets or private credentials into the app
- Preserve the current user flow unless explicitly asked to redesign it
- Prefer improving structure and clarity over adding abstractions
- When making changes, inspect the affected files first and summarize current behavior before editing

Swift / SwiftUI rules:
- Prefer simple SwiftUI patterns already used in the repo
- Keep UI state changes predictable
- Be careful with MainActor / concurrency issues
- Avoid unnecessary architectural rewrites
- Keep networking logic in `APIService.swift` or a closely related networking layer
- Keep models small and aligned with backend JSON
- Minimize duplicate formatting or business logic across views

Networking rules:
- Preserve compatibility with the current backend
- If adding a new API call, define the request/response model clearly
- Keep request timeout and error-handling behavior explicit
- Do not silently swallow backend contract changes; call them out clearly

Map rules:
- Preserve the current visible-region fetch behavior unless explicitly asked to change it
- Keep map interactions responsive
- Be cautious when changing annotation identity, debounce logic, or refresh logic

Notification rules:
- Preserve current high-risk alert behavior unless explicitly asked to change it
- Explain any user-facing notification changes before implementing them

When making changes:
1. Inspect the relevant files
2. Summarize the current behavior
3. Propose the minimal change
4. Make the edit
5. Summarize exactly what changed and any user-visible impact

Preferred output style:
- Be concise
- Mention file-by-file impact
- Call out backend contract changes explicitly
- For non-trivial edits, note risks and validation steps
