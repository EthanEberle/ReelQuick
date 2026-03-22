# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReelQuick is an iOS/macOS application built with SwiftUI and SwiftData. The project uses the Shuffle library for card-based UI interactions.

## Development Commands

### Building the Project
- **Build**: In Xcode, use `Cmd+B` or via command line: `xcodebuild -project ReelQuick.xcodeproj -scheme ReelQuick -configuration Debug`
- **Clean Build**: In Xcode, use `Cmd+Shift+K` or via command line: `xcodebuild clean -project ReelQuick.xcodeproj`

### Running Tests
- **Unit Tests**: `xcodebuild test -project ReelQuick.xcodeproj -scheme ReelQuick -destination 'platform=iOS Simulator,name=iPhone 15'`
- **UI Tests**: Tests use XCTest framework for UI testing and Swift Testing framework for unit tests
- **Single Test**: In Xcode, click the diamond next to a test method or use `Cmd+U` to run all tests

### Running the App
- **iOS Simulator**: Open in Xcode and press `Cmd+R` or use `xcodebuild -project ReelQuick.xcodeproj -scheme ReelQuick -destination 'platform=iOS Simulator,name=iPhone 15'`
- **Device**: Select device in Xcode toolbar and press `Cmd+R`

## Architecture

### Core Technologies
- **SwiftUI**: Primary UI framework
- **SwiftData**: Persistence layer using `@Model` macro for data models
- **Swift Package Manager**: Dependency management (Shuffle library via SPM)

### Project Structure
- `ReelQuick/`: Main application code
  - `ReelQuickApp.swift`: App entry point with SwiftData ModelContainer setup
  - `ContentView.swift`: Primary navigation view with list/detail layout
  - `Item.swift`: SwiftData model class
- `ReelQuickTests/`: Unit tests using Swift Testing framework
- `ReelQuickUITests/`: UI tests using XCTest framework

### Key Patterns
- **SwiftData Integration**: ModelContainer initialized in app entry point, passed via environment
- **Navigation**: Uses NavigationSplitView for list/detail navigation pattern
- **Data Flow**: @Query property wrapper for reactive data fetching, @Environment for ModelContext access

### Dependencies
- **Shuffle** (https://github.com/mac-gallagher/Shuffle.git): Card swipe UI library

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:b9766037 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
