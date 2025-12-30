// AquaZig Swift Package
//
// A Swift wrapper for the AquaZig ScreenLogic pool controller library.
//
// Usage:
//
//     import AquaZig
//
//     let client = AquaZigClient()
//     try await client.discoverAndConnect()
//     let status = try await client.getStatus()
//     print("Pool temp: \(status.pool.currentTemp)F")
//

// Re-export all public types
@_exported import CAquaZig

// Module version
public let aquaZigVersion = "0.1.0"
