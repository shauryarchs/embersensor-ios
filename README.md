# EmberSensor iOS

An iOS app for real-time wildfire risk monitoring. EmberSensor connects to a backend that aggregates local sensor data, weather conditions, and satellite fire detection to give homeowners a live picture of fire risk near their home.

## What it does

- **Risk dashboard** — displays a live risk index (0–10) with LOW / MEDIUM / HIGH classification, updated every 15 seconds. Shows sensor temperature, smoke levels, flame detection, humidity, wind speed and direction, and rainfall.
- **Fire map** — an interactive map showing nearby fires sourced from satellite data. Tap any fire pin to see details including confidence, brightness, satellite source, and acquisition time.
- **High risk alerts** — triggers a local push notification and a full-screen emergency alert when risk transitions into HIGH (index ≥ 8), even when the app is in the foreground.

## Tech stack

- Swift / SwiftUI
- MapKit
- URLSession (no third-party networking libraries)
- UserNotifications

## Project structure

| File | Purpose |
|------|---------|
| `EmberSensorApp.swift` | App entry point, notification delegate setup |
| `ContentView.swift` | Status dashboard, polling timer, alert logic |
| `FireMapView.swift` | Interactive fire map, region-based data fetching |
| `FireDetailCard.swift` | Detail card for a selected fire pin |
| `APIService.swift` | All backend API calls |
| `FireStatus.swift` | Model for status endpoint response |
| `FireMapModels.swift` | Models for fires endpoint response |
| `NotificationDelegate.swift` | Foreground notification presentation |
