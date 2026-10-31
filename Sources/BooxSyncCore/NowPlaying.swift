import Foundation
import AppKit

public struct NowPlaying: Equatable, Sendable {
    public var source: String
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    public var position: Double   // seconds
    public var duration: Double   // seconds
    public var artworkURL: URL?

    public init(source: String, title: String, artist: String, album: String, isPlaying: Bool,
                position: Double, duration: Double, artworkURL: URL?) {
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.position = position
        self.duration = duration
        self.artworkURL = artworkURL
    }
}

public enum NowPlayingStatus: Equatable, Sendable {
    case playing(NowPlaying)
    case noPlayer          // nothing running
    case idle              // a player is running but has no track
    case automationDenied  // macOS blocked controlling the player
}

/// Reads the current track from Spotify or Music through AppleScript. Only asks apps that are already running,
/// so it never launches a player. macOS asks for Automation permission the first time.
public final class NowPlayingProvider {
    private struct Player {
        let name: String
        let bundleID: String
        let script: String
    }

    // Everything comes back as tab-separated text so locale decimal separators cannot get in the way.
    private let players: [Player] = [
        Player(name: "Spotify", bundleID: "com.spotify.client", script: """
        with timeout of 2 seconds
          tell application id "com.spotify.client"
            if player state is stopped then return "stopped"
            set t to current track
            return (name of t) & tab & (artist of t) & tab & (album of t) & tab & (player state as text) & tab & (artwork url of t) & tab & ((duration of t) as integer as text) & tab & ((player position) as integer as text)
          end tell
        end timeout
        """),
        Player(name: "Music", bundleID: "com.apple.Music", script: """
        with timeout of 2 seconds
          tell application id "com.apple.Music"
            if player state is stopped then return "stopped"
            set t to current track
            return (name of t) & tab & (artist of t) & tab & (album of t) & tab & (player state as text) & tab & "" & tab & ((duration of t) as integer as text) & tab & ((player position) as integer as text)
          end tell
        end timeout
        """),
    ]

    public init() {}

    /// Call on the main thread (NSAppleScript is not thread safe).
    @MainActor
    public func current() -> NowPlayingStatus {
        var best: NowPlaying?
        var anyRunning = false
        for player in players {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty else { continue }
            anyRunning = true
            var errorInfo: NSDictionary?
            guard let output = NSAppleScript(source: player.script)?.executeAndReturnError(&errorInfo) else {
                if (errorInfo?[NSAppleScript.errorNumber] as? Int) == -1743 { return .automationDenied }
                continue
            }
            guard let text = output.stringValue, let parsed = Self.parse(text, source: player.name) else { continue }
            if best == nil || (parsed.isPlaying && !(best?.isPlaying ?? false)) { best = parsed }
        }
        if let best { return .playing(best) }
        return anyRunning ? .idle : .noPlayer
    }

    public static func parse(_ text: String, source: String) -> NowPlaying? {
        let fields = text.components(separatedBy: "\t")
        guard fields.count >= 7 else { return nil }
        let rawDuration = Double(fields[5]) ?? 0
        // Spotify reports milliseconds, Music reports seconds.
        let duration = source == "Spotify" ? rawDuration / 1000 : rawDuration
        let artwork = fields[4].isEmpty ? nil : URL(string: fields[4])
        return NowPlaying(
            source: source, title: fields[0], artist: fields[1], album: fields[2],
            isPlaying: fields[3] == "playing", position: Double(fields[6]) ?? 0, duration: duration, artworkURL: artwork)
    }
}
