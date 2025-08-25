# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FotoFlow is an iOS/macOS application built with SwiftUI and SwiftData. The project uses the Shuffle library for card-based UI interactions.

## Development Commands

### Building the Project
- **Build**: In Xcode, use `Cmd+B` or via command line: `xcodebuild -project FotoFlow.xcodeproj -scheme FotoFlow -configuration Debug`
- **Clean Build**: In Xcode, use `Cmd+Shift+K` or via command line: `xcodebuild clean -project FotoFlow.xcodeproj`

### Running Tests
- **Unit Tests**: `xcodebuild test -project FotoFlow.xcodeproj -scheme FotoFlow -destination 'platform=iOS Simulator,name=iPhone 15'`
- **UI Tests**: Tests use XCTest framework for UI testing and Swift Testing framework for unit tests
- **Single Test**: In Xcode, click the diamond next to a test method or use `Cmd+U` to run all tests

### Running the App
- **iOS Simulator**: Open in Xcode and press `Cmd+R` or use `xcodebuild -project FotoFlow.xcodeproj -scheme FotoFlow -destination 'platform=iOS Simulator,name=iPhone 15'`
- **Device**: Select device in Xcode toolbar and press `Cmd+R`

## Architecture

### Core Technologies
- **SwiftUI**: Primary UI framework
- **SwiftData**: Persistence layer using `@Model` macro for data models
- **Swift Package Manager**: Dependency management (Shuffle library via SPM)

### Project Structure
- `FotoFlow/`: Main application code
  - `FotoFlowApp.swift`: App entry point with SwiftData ModelContainer setup
  - `ContentView.swift`: Primary navigation view with list/detail layout
  - `Item.swift`: SwiftData model class
- `FotoFlowTests/`: Unit tests using Swift Testing framework
- `FotoFlowUITests/`: UI tests using XCTest framework

### Key Patterns
- **SwiftData Integration**: ModelContainer initialized in app entry point, passed via environment
- **Navigation**: Uses NavigationSplitView for list/detail navigation pattern
- **Data Flow**: @Query property wrapper for reactive data fetching, @Environment for ModelContext access

### Dependencies
- **Shuffle** (https://github.com/mac-gallagher/Shuffle.git): Card swipe UI library