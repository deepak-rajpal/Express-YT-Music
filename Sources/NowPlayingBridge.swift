import AppKit
import MediaPlayer

/// Publishes the current track to macOS Now Playing (Control Centre, lock screen,
/// AirPods, media keys) and forwards the system's remote commands back to the page.
final class NowPlayingBridge {

    static let shared = NowPlayingBridge()

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    private var artworkCache: (url: String, artwork: MPMediaItemArtwork)?
    private var artworkTask: URLSessionDataTask?

    private init() {}

    func start() {
        registerCommands()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateChanged(_:)),
            name: .playerStateChanged,
            object: nil
        )
        publish()
    }

    // MARK: - Remote commands

    private func registerCommands() {
        let player = WebPlayerController.shared

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            player.play()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            player.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            player.togglePlayPause()
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            player.nextTrack()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            player.previousTrack()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            player.seek(to: event.positionTime)
            return .success
        }

        // Not supported by the web player - leave them off so the OS hides the affordance.
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
    }

    // MARK: - Publishing

    @objc private func stateChanged(_ note: Notification) {
        publish()
    }

    private func publish() {
        let state = PlayerStore.shared.state

        guard state.hasTrack else {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.title,
            MPMediaItemPropertyArtist: state.artist,
            MPMediaItemPropertyAlbumTitle: state.album,
            MPMediaItemPropertyPlaybackDuration: state.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]

        if let cached = artworkCache, cached.url == state.artworkURL {
            info[MPMediaItemPropertyArtwork] = cached.artwork
        }

        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = state.isPlaying ? .playing : .paused

        fetchArtworkIfNeeded(state.artworkURL)
    }

    private func fetchArtworkIfNeeded(_ urlString: String) {
        guard !urlString.isEmpty,
              artworkCache?.url != urlString,
              let url = URL(string: urlString) else { return }

        artworkTask?.cancel()
        artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let image = NSImage(data: data) else { return }

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                self.artworkCache = (urlString, artwork)
                // Re-publish so the artwork lands in Control Centre.
                if PlayerStore.shared.state.artworkURL == urlString {
                    self.publish()
                }
                ArtworkStore.shared.set(image: image, for: urlString)
            }
        }
        artworkTask?.resume()
    }
}

/// Shared decoded artwork so the mini player does not re-download the same image.
final class ArtworkStore {
    static let shared = ArtworkStore()

    private(set) var url: String = ""
    private(set) var image: NSImage?

    private init() {}

    func set(image: NSImage, for url: String) {
        self.image = image
        self.url = url
        NotificationCenter.default.post(name: .artworkChanged, object: self)
    }
}

extension Notification.Name {
    static let artworkChanged = Notification.Name("eym.artworkChanged")
}
