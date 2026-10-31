import AVFoundation
import MediaPlayer
import Observation
import ServiceManagement
import SwiftUI

/// The player: which station and track, play and pause, volume, the sleep timer, start at login, and the system's media
/// keys and Now Playing. `LofiTrack` writes the tracks and `LofiSynth` plays them.
@MainActor
@Observable
final class Radio {
    private(set) var station: Station
    /// What's playing, or about to after Next.
    private(set) var track: LofiTrack
    private(set) var isPlaying = false
    /// Seconds into the track.
    private(set) var elapsed: Double = 0
    /// When the sleep timer stops the music.
    private(set) var sleepEnd: Date?
    private(set) var startsAtLogin: Bool
    /// The focus timer: when it ends (while it's running), how long it has left (while the music's paused), and how
    /// long it was set for.
    private(set) var focusEnd: Date?
    private(set) var focusLeft: TimeInterval?
    private(set) var focusLength: TimeInterval = 0
    /// Focus sessions finished since the app opened.
    private(set) var focusDone = 0
    /// 0…1.
    var volume: Double {
        didSet {
            defaults.set(volume, forKey: Keys.volume)
            applyVolume()
        }
    }

    @ObservationIgnored let synth = LofiSynth()
    let updates = UpdateChecker()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var chimePlayer: AVAudioPlayerNode?
    /// The track handed to the synth most recently: what it plays next.
    @ObservationIgnored private var queued: LofiTrack
    @ObservationIgnored private var seenSwitches = 0
    /// Next was pressed and the synth hasn't switched yet, so its position is still the old track's.
    @ObservationIgnored private var skipPending = true
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var stopEngine: DispatchWorkItem?
    @ObservationIgnored private var artwork: [Station: MPMediaItemArtwork] = [:]

    private enum Keys {
        static let station = "MenuBarLofi.station", volume = "MenuBarLofi.volume"
        static func track(_ station: Station) -> String { "MenuBarLofi.track.\(station.rawValue)" }
    }

    /// `live`: plays out loud, checks for updates and answers the media keys. Tests pass false and run the synth themselves.
    init(defaults: UserDefaults = .standard, live: Bool = true) {
        self.defaults = defaults
        self.live = live
        let station = Station(rawValue: defaults.string(forKey: Keys.station) ?? "") ?? .chill
        let track = LofiTrack(station: station, number: Self.savedNumber(station, defaults))
        self.station = station
        self.track = track
        queued = track
        volume = defaults.object(forKey: Keys.volume) as? Double ?? 0.7
        startsAtLogin = live && SMAppService.mainApp.status == .enabled
        synth.queue(track, now: true)
        if live { connectMediaKeys(); updates.start() }
    }

    /// Each station carries on where you left it.
    private static func savedNumber(_ station: Station, _ defaults: UserDefaults) -> Int {
        min(max(defaults.integer(forKey: Keys.track(station)), 0), Station.trackCount - 1)
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        stopEngine?.cancel()
        if let left = focusLeft { // the focus clock carries on
            focusEnd = .now + left
            focusLeft = nil
        }
        applyVolume()
        startEngine()
        let ticker = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        ticker.tolerance = 0.1
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        updateNowPlaying()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        sleepEnd = nil
        if let end = focusEnd { // the focus clock waits for the music
            focusLeft = max(end.timeIntervalSinceNow, 0)
            focusEnd = nil
        }
        synth.target = 0
        ticker?.invalidate()
        ticker = nil
        if !skipPending { elapsed = Double(synth.position) / LofiTrack.sampleRate }
        stopEngine(after: Double(LofiSynth.fadeOut) + 0.5)
        updateNowPlaying()
    }

    /// Once it's quiet, stop the engine so it costs nothing.
    private func stopEngine(after seconds: Double) {
        stopEngine?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.engine?.pause() } }
        stopEngine = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Plays music for `minutes`, then stops it and rings a chime.
    func startFocus(minutes: Double) {
        focusLength = minutes * 60
        focusEnd = .now + focusLength
        focusLeft = nil
        play()
    }

    func stopFocus() {
        focusEnd = nil
        focusLeft = nil
    }

    private func finishFocus() {
        stopFocus()
        focusDone += 1
        pause()
        guard let engine, let chimePlayer else { return }
        if !engine.isRunning { try? engine.start() }
        chimePlayer.stop()
        chimePlayer.volume = Float(volume * volume)
        if let buffer = Chime.buffer(format: chimePlayer.outputFormat(forBus: 0)) { chimePlayer.scheduleBuffer(buffer) }
        chimePlayer.play()
        stopEngine(after: Chime.length + 0.5)
    }

    func next() { go(to: (track.number + 1) % Station.trackCount) }

    /// Back to the start of this track, or to the one before if it's only just begun.
    func previous() { go(to: elapsed > 3 ? track.number : (track.number + Station.trackCount - 1) % Station.trackCount) }

    func select(_ station: Station) {
        guard station != self.station else { return }
        self.station = station
        defaults.set(station.rawValue, forKey: Keys.station)
        go(to: Self.savedNumber(station, defaults))
    }

    /// nil turns it off.
    func sleep(minutes: Double?) {
        sleepEnd = minutes.map { .now + $0 * 60 }
        applyVolume()
    }

    func setStartsAtLogin(_ on: Bool) {
        guard live else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Start at login: \(error)")
        }
        let status = SMAppService.mainApp.status
        // macOS can ask for an OK in System Settings first.
        if status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        startsAtLogin = status == .enabled || status == .requiresApproval
    }

    /// Twice a second while playing: follows the synth onto the next track and queues the one after, moves the clock,
    /// and runs the sleep timer.
    func tick() {
        let switches = synth.switches
        if switches != seenSwitches {
            seenSwitches = switches
            skipPending = false
            if queued.station != track.station || queued.number != track.number {
                track = queued
                defaults.set(track.number, forKey: Keys.track(track.station))
            }
            queued = LofiTrack(station: track.station, number: (track.number + 1) % Station.trackCount)
            synth.queue(queued, now: false)
            updateNowPlaying()
        }
        if !skipPending { elapsed = Double(synth.position) / LofiTrack.sampleRate }
        if let focusEnd, focusEnd.timeIntervalSinceNow <= 0 { finishFocus() }
        if let sleepEnd {
            if sleepEnd.timeIntervalSinceNow <= 0 { pause() } else { applyVolume() }
        }
    }

    private func go(to number: Int) {
        track = LofiTrack(station: station, number: number)
        queued = track
        skipPending = true
        elapsed = 0
        defaults.set(number, forKey: Keys.track(station))
        synth.queue(track, now: true)
        updateNowPlaying()
    }

    /// The volume squared (so the slider feels even), easing to nothing over the sleep timer's last 30 seconds.
    private func applyVolume() {
        guard isPlaying else { return }
        var level = Float(volume * volume)
        if let sleepEnd { level *= Float(min(max(sleepEnd.timeIntervalSinceNow / 30, 0), 1)) }
        synth.target = level
    }

    private func startEngine() {
        guard live else { return }
        if engine == nil {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: LofiTrack.sampleRate, channels: 2) else { return }
            let engine = AVAudioEngine()
            let node = Self.sourceNode(synth, format: format)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            let chime = AVAudioPlayerNode()
            engine.attach(chime)
            engine.connect(chime, to: engine.mainMixerNode, format: format)
            chimePlayer = chime
            self.engine = engine
            // Headphones in or out stops the engine; pick up again if it should be playing.
            NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self, self.isPlaying { self.startEngine() }
                }
            }
        }
        if let engine, !engine.isRunning {
            do { try engine.start() } catch { NSLog("Lo-fi couldn't start: \(error)") }
        }
    }

    /// Made outside the main actor: the block runs on the audio thread.
    private nonisolated static func sourceNode(_ synth: LofiSynth, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count == 2, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(left: left, right: right, count: Int(frameCount))
            return noErr
        }
    }

    // MARK: - Media keys and Now Playing

    private func connectMediaKeys() {
        let commands = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (Radio) -> Void) {
            command.addTarget { [weak self] _ in
                DispatchQueue.main.async { if let self { action(self) } }
                return .success
            }
        }
        on(commands.playCommand) { $0.play() }
        on(commands.pauseCommand) { $0.pause() }
        on(commands.togglePlayPauseCommand) { $0.togglePlay() }
        on(commands.nextTrackCommand) { $0.next() }
        on(commands.previousTrackCommand) { $0.previous() }
    }

    private func updateNowPlaying() {
        guard live else { return }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: "Menu Bar Lofi",
            MPMediaItemPropertyAlbumTitle: track.station.name,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyArtwork: artwork(for: track.station),
        ]
        center.playbackState = isPlaying ? .playing : .paused
    }

    private func artwork(for station: Station) -> MPMediaItemArtwork {
        if let art = artwork[station] { return art }
        let image = ImageRenderer(content: Cover(station: station, size: 300)).nsImage ?? NSImage()
        let art = Self.artwork(image)
        artwork[station] = art
        return art
    }

    /// Made outside the main actor: the system asks for the picture from any thread.
    private nonisolated static func artwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
