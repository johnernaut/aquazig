# AquaZig macOS App

SwiftUI-based macOS application for controlling Pentair ScreenLogic pool systems.

## Quick Start

### 1. Build the XCFramework

First, build the AquaZig library:

```bash
cd /path/to/aquazig
./scripts/build-xcframework.sh
```

### 2. Open in Xcode

Simply open the project:

```bash
open AquaZigApp/AquaZigApp.xcodeproj
```

The project is pre-configured with:
- Local package dependency to `AquaZigSwift`
- Network client entitlement for ScreenLogic communication
- Local network usage description

### 3. Run

Build and run the app (Cmd+R). It will:
1. Automatically discover your ScreenLogic device on the local network
2. Connect and authenticate
3. Display pool/spa status, temperatures, and pump information

## Features

- Auto-discovery of ScreenLogic devices
- Real-time pool and spa status
- Temperature display and heat mode control
- Pump status monitoring
- Chemistry data display (pH, ORP, salt)

## Architecture

```
AquaZigApp
├── AquaZigApp.swift       # @main entry point
├── ContentView.swift      # Main UI with dashboard
└── ViewModels/
    └── PoolViewModel.swift  # State management
```

The app uses the AquaZigSwift package which wraps the Zig-based AquaZig library.

## Requirements

- macOS 13.0+
- Xcode 15.0+
- ScreenLogic pool controller on the local network
