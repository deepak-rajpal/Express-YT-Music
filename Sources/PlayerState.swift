import Foundation

/// Snapshot of what the web player is doing. Produced by `Resources/inject.js`.
struct PlayerState: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var artworkURL = ""
    var isPlaying = false
    var elapsed: Double = 0
    var duration: Double = 0
    var volume: Double = 1
    var hasPlayer = false

    var hasTrack: Bool { !title.isEmpty }

    /// "Artist — Title", or just the title when the artist is unknown.
    var summary: String {
        guard hasTrack else { return "" }
        return artist.isEmpty ? title : "\(artist) — \(title)"
    }

    init() {}

    init?(message: [String: Any]) {
        guard message["type"] as? String == "state" else { return nil }
        title      = message["title"]     as? String ?? ""
        artist     = message["artist"]    as? String ?? ""
        album      = message["album"]     as? String ?? ""
        artworkURL = message["artwork"]   as? String ?? ""
        isPlaying  = message["isPlaying"] as? Bool   ?? false
        elapsed    = message["elapsed"]   as? Double ?? 0
        duration   = message["duration"]  as? Double ?? 0
        volume     = message["volume"]    as? Double ?? 1
        hasPlayer  = message["hasPlayer"] as? Bool   ?? false
    }
}

extension Notification.Name {
    /// Posted by `PlayerStore` whenever the state changes. `object` is the `PlayerStore`.
    static let playerStateChanged = Notification.Name("eym.playerStateChanged")
}

/// Single source of truth for player state, so the status bar, mini player and
/// Now Playing centre all read the same thing.
final class PlayerStore {
    static let shared = PlayerStore()

    private(set) var state = PlayerState()

    private init() {}

    func update(_ new: PlayerState) {
        guard new != state else { return }
        let trackChanged = new.title != state.title || new.artist != state.artist
        state = new
        NotificationCenter.default.post(
            name: .playerStateChanged,
            object: self,
            userInfo: ["trackChanged": trackChanged]
        )
    }

    func clear() {
        update(PlayerState())
    }
}
