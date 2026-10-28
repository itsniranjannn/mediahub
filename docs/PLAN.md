# MediaHub Product Plan

## Overview
MediaHub is a modern, cross-platform media player and manager for Android and iOS built with Flutter and Riverpod.

## Architecture
- Clean Architecture (app, core, domain, data, features, platform, shared).
- Reactive state management using `flutter_riverpod`.
- Navigation routing using `go_router`.
- Local persistence using Drift (SQLite).
- Local media indexing via native MediaStore / permissions.

## Core Feature Roadmap
1. Task 1: Project Setup & Design System (Completed)
2. Task 2: Local Library Foundation (MediaStore Indexing, Drift Storage, Search/Sort, Permissions)
3. Task 3: Music Player & Audio Engine
4. Task 4: Video Player & Playback Controls
5. Task 5: Direct URL Downloads & Management
6. Task 6: Playlists & Audio/Video Trim & Export
