import AVFoundation
import XCTest
@testable import MenuBarLofi

// Everything here is generated or made up in the test itself: no files, nothing read from ~/Documents (macOS's
// Documents privacy prompt and iCloud stalls hung Menu Bar Emulator's tests).

private let second = Int(LofiTrack.sampleRate)

/// Runs the synth like the audio thread does (512-sample chunks) and reports the levels.
@discardableResult
private func play(_ synth: LofiSynth, seconds: Double) -> (peak: Float, rms: Float, finite: Bool) {
    var left = [Float](repeating: 0, count: 512), right = left
    var peak: Float = 0, sum: Float = 0, finite = true
    let chunks = Int(seconds * Double(second)) / 512
    for _ in 0..<chunks {
        synth.render(left: &left, right: &right, count: 512)
        for i in 0..<512 {
            finite = finite && left[i].isFinite && right[i].isFinite
            peak = max(peak, abs(left[i]), abs(right[i]))
            sum += left[i] * left[i] + right[i] * right[i]
        }
    }
    return (peak, (sum / Float(max(chunks * 1024, 1))).squareRoot(), finite)
}

/// A short made-up track: one chord a second.
private func blip(seconds: Double, note: Int = 60) -> LofiTrack {
    let events = (0..<Int(seconds)).map { LofiTrack.Event(time: $0 * second, kind: .keys, note: note, velocity: 0.6, length: second / 2) }
    return LofiTrack(station: .chill, number: 0, key: 0, minor: false, tempo: 80, events: events, length: Int(seconds * Double(second)), sound: .init())
}

final class GeneratorTests: XCTestCase {
    func testSameTrackEveryTime() {
        for station in Station.allCases {
            for number in [0, 17, 119] {
                let a = LofiTrack(station: station, number: number)
                _ = LofiTrack(station: station, number: number + 1) // no hidden state between tracks
                let b = LofiTrack(station: station, number: number)
                XCTAssertEqual(a.events, b.events, "\(station) \(number)")
                XCTAssertEqual(a.length, b.length)
                XCTAssertEqual(a.sound.kit, b.sound.kit)
                XCTAssertEqual(a.title, b.title)
            }
        }
    }

    func testThirtyHoursOfDifferentMusic() {
        var hours = 0.0
        var fingerprints = Set<String>()
        for station in Station.allCases {
            let tracks = (0..<Station.trackCount).map { LofiTrack(station: station, number: $0) }
            hours += tracks.reduce(0) { $0 + $1.duration } / 3600
            for track in tracks {
                XCTAssertEqual(track.events.map(\.time), track.events.map(\.time).sorted(), "in time order")
                XCTAssertLessThanOrEqual(track.events.count, LofiSynth.maxEvents, "fits the synth")
                XCTAssertLessThan(track.events.last!.time, track.length)
                let notes = track.events.filter { ![.kick, .snare, .hat, .openHat].contains($0.kind) }
                XCTAssertTrue(notes.allSatisfy { (28...100).contains($0.note) && $0.length > 0 && $0.velocity > 0 && $0.velocity <= 1 })
                XCTAssertGreaterThan(track.duration, 100, "a couple of minutes each")
                XCTAssertLessThan(track.duration, 240)
                // The tune itself: the first 40 notes above the chords.
                let tune = track.events.filter { $0.note >= 60 && [.lead, .square, .ocarina, .bell, .sax, .guitar, .piano].contains($0.kind) }
                fingerprints.insert("\(track.key) \(track.minor) \(track.tempo) " + tune.prefix(40).map { "\($0.kind)\($0.note)" }.joined(separator: ","))
            }

            // Every station gets around: keys, tempos, instruments and kits change from track to track.
            XCTAssertEqual(Set(tracks.map(\.title)).count, Station.trackCount, "\(station): every title different")
            XCTAssertGreaterThanOrEqual(Set(tracks.map(\.key)).count, 12, "\(station): every key")
            XCTAssertGreaterThanOrEqual(Set(tracks.map(\.tempo)).count, 10, "\(station): tempos")
            let bands = Set(tracks.map { Set($0.events.map(\.kind)) })
            XCTAssertGreaterThanOrEqual(bands.count, 3, "\(station): different line-ups")
            let samey = zip(tracks, tracks.dropFirst()).filter {
                $0.key == $1.key && $0.minor == $1.minor && $0.tempo == $1.tempo && Set($0.events.map(\.kind)) == Set($1.events.map(\.kind))
            }
            XCTAssertEqual(samey.count, 0, "\(station): no track sounds just like the one before")
        }
        XCTAssertEqual(fingerprints.count, Station.allCases.count * Station.trackCount, "720 different tunes")
        XCTAssertGreaterThanOrEqual(hours, 30, "about 30 hours")
        XCTAssertLessThan(hours, 36)
        print("Lo-fi: \(String(format: "%.1f", hours)) hours in \(fingerprints.count) tracks")
    }

    func testStationsHaveTheirOwnSound() {
        func tracks(_ station: Station) -> [LofiTrack] { (0..<40).map { LofiTrack(station: station, number: $0) } }
        XCTAssertTrue(tracks(.rainy).allSatisfy { $0.sound.rain > 0 }, "it always rains on Rainy")
        XCTAssertTrue(tracks(.cafe).allSatisfy { $0.sound.cafe > 0 && $0.sound.kit == .brushes }, "a café, with brushes")
        XCTAssertTrue(tracks(.gameBoy).allSatisfy { $0.sound.rain == 0 && $0.events.contains { $0.kind == .arp } }, "arpeggios, no weather")
        XCTAssertGreaterThan(tracks(.night).filter(\.minor).count, 24, "Night is mostly minor")
        XCTAssertLessThan(tracks(.gameBoy).filter(\.minor).count, 14, "Game Boy is mostly major")
        XCTAssertTrue(tracks(.cafe).contains { $0.events.contains { $0.kind == .guitar } })
        XCTAssertTrue(tracks(.night).contains { $0.events.contains { $0.kind == .sax } })
        XCTAssertTrue(tracks(.study).contains { $0.events.contains { $0.kind == .piano } })
        XCTAssertTrue(tracks(.rainy).contains { $0.events.contains { $0.kind == .pad } })
        XCTAssertTrue(tracks(.gameBoy).contains { $0.sound.kit == .chip })
        let tempo = { (station: Station) in Double(tracks(station).map(\.tempo).reduce(0, +)) / 40 }
        XCTAssertLessThan(tempo(.night), tempo(.cafe), "Night is slower than the café")
    }

    func testPlaylistOpeningsHaveDistinctArrangements() {
        let voices: [Station: LofiTrack.Kind] = [.chill: .guitar, .study: .piano, .rainy: .guitar, .night: .bell, .gameBoy: .square]
        for (station, voice) in voices {
            let track = LofiTrack(station: station, number: 0)
            XCTAssertTrue(track.events.contains { $0.kind == voice && $0.time < second }, "\(station): its signature voice opens the track")
            if station == .gameBoy {
                XCTAssertEqual(track.sound.kit, .chip)
                XCTAssertEqual(track.tempo, 100)
                XCTAssertTrue(track.events.contains { $0.kind == .kick && $0.time == 0 }, "the chip fanfare starts immediately")
                XCTAssertTrue(track.events.contains { $0.kind == .arp && $0.time == 0 })
            } else if station != .chill {
                let firstKick = track.events.first { $0.kind == .kick }
                XCTAssertNotNil(firstKick)
                XCTAssertGreaterThan(firstKick?.time ?? 0, 8 * second, "\(station): a beatless, spacious opening")
            }
        }
        let study = LofiTrack(station: .study, number: 0)
        XCTAssertFalse(study.events.contains { $0.kind == .pad }, "the first Study track leaves room for solo piano")
        let firstSnare = study.events.first { $0.kind == .snare }!
        let step = Double(firstSnare.time) / LofiTrack.sampleRate / (60 / Double(study.tempo) / 4)
        XCTAssertEqual(Int(step.rounded()) % 16, 8, "half-time snare instead of the usual two and four")
    }
}

final class SynthTests: XCTestCase {
    func testCleanLevelsOnEveryStation() {
        var rendered = 0.0, busy = 0.0
        for station in Station.allCases {
            for number in [5, 66] {
                let synth = LofiSynth()
                synth.queue(LofiTrack(station: station, number: number), now: true)
                synth.target = 1 // full volume: the loudest it gets
                let start = CFAbsoluteTimeGetCurrent()
                let warmup = play(synth, seconds: 2)
                let level = play(synth, seconds: 6)
                busy += CFAbsoluteTimeGetCurrent() - start
                rendered += 8
                XCTAssertTrue(warmup.finite && level.finite, "\(station) \(number): no NaNs")
                XCTAssertLessThan(level.peak, 0.95, "\(station) \(number): never clips")
                XCTAssertGreaterThan(level.rms, 0.03, "\(station) \(number): actually plays")
                XCTAssertLessThan(level.rms, 0.3, "\(station) \(number): not blasting")
            }
        }
        print("Lo-fi renders \(Int(rendered / busy))× faster than real time in this build")
        XCTAssertGreaterThan(rendered / busy, 3, "fast enough never to stutter, even in a debug build")
    }

    func testFadesInSlowlyOutQuicklyAndKeepsItsPlace() {
        let synth = LofiSynth()
        synth.queue(LofiTrack(station: .chill, number: 3), now: true)
        XCTAssertEqual(play(synth, seconds: 1).peak, 0, "silent until asked")
        XCTAssertEqual(synth.position, 0, "and the track doesn't move")
        synth.target = 0.8
        let first = play(synth, seconds: 0.5)
        play(synth, seconds: 1.5)
        let later = play(synth, seconds: 3)
        XCTAssertLessThan(first.rms, later.rms * 0.3, "fades in")
        synth.target = 0
        play(synth, seconds: 1)
        XCTAssertEqual(synth.fade, 0, "faded out within a second")
        let parked = synth.position
        XCTAssertEqual(play(synth, seconds: 1).peak, 0)
        XCTAssertEqual(synth.position, parked, "keeps its place for next time")
    }

    func testNextSwitchesQuicklyAndTracksFollowOn() {
        let synth = LofiSynth()
        synth.queue(blip(seconds: 2), now: true)
        synth.target = 1
        play(synth, seconds: 0.5)
        XCTAssertEqual(synth.switches, 1)
        // The next one, queued for when this ends: it starts right after.
        synth.queue(blip(seconds: 30, note: 67), now: false)
        play(synth, seconds: 1)
        XCTAssertEqual(synth.switches, 1, "still on the first")
        play(synth, seconds: 1)
        XCTAssertEqual(synth.switches, 2, "on to the next as the first ends")
        XCTAssertLessThan(synth.position, second)
        // Next: a quick fade and the new track starts from the top.
        play(synth, seconds: 2)
        synth.queue(blip(seconds: 30, note: 72), now: true)
        play(synth, seconds: 0.4)
        XCTAssertEqual(synth.switches, 3)
        XCTAssertLessThan(synth.position, second / 4, "from the top")
        // Nothing queued at the end: it waits quietly instead of running off.
        let short = LofiSynth()
        short.queue(blip(seconds: 1), now: true)
        short.target = 1
        let after = play(short, seconds: 4)
        XCTAssertTrue(after.finite)
        XCTAssertEqual(short.position, second, "parked at the end")
    }

    func testNextWhilePausedSwitchesSilently() {
        let synth = LofiSynth()
        synth.queue(blip(seconds: 30), now: true)
        play(synth, seconds: 0.1)
        XCTAssertEqual(synth.switches, 1, "picked up while silent")
        synth.queue(blip(seconds: 30, note: 67), now: true)
        play(synth, seconds: 0.1)
        XCTAssertEqual(synth.switches, 2)
        XCTAssertEqual(synth.position, 0)
    }
}

@MainActor
final class RadioTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "MenuBarLofiTests.\(UUID().uuidString)")
    }

    func testPlayPauseVolume() {
        let radio = Radio(defaults: defaults, live: false)
        XCTAssertFalse(radio.isPlaying, "quiet until you press play")
        XCTAssertEqual(radio.station, .chill)
        XCTAssertEqual(radio.track.number, 0)
        XCTAssertEqual(radio.volume, 0.7)
        XCTAssertEqual(radio.synth.target, 0)
        radio.togglePlay()
        XCTAssertTrue(radio.isPlaying)
        XCTAssertEqual(radio.synth.target, 0.49, accuracy: 0.001, "volume squared")
        radio.volume = 0.5
        XCTAssertEqual(radio.synth.target, 0.25, accuracy: 0.001)
        radio.togglePlay()
        XCTAssertFalse(radio.isPlaying)
        XCTAssertEqual(radio.synth.target, 0)
        radio.volume = 0.9
        XCTAssertEqual(radio.synth.target, 0, "the volume doesn't start it")
        XCTAssertEqual(Radio(defaults: defaults, live: false).volume, 0.9, "remembered")
    }

    func testNextPreviousAndStations() {
        let radio = Radio(defaults: defaults, live: false)
        radio.play()
        play(radio.synth, seconds: 0.5)
        radio.tick()
        XCTAssertGreaterThan(radio.elapsed, 0.3)
        radio.next()
        XCTAssertEqual(radio.track.number, 1)
        XCTAssertEqual(radio.elapsed, 0)
        play(radio.synth, seconds: 0.5)
        radio.tick()
        XCTAssertLessThan(radio.elapsed, 0.5, "the clock restarts with the new track")
        radio.previous()
        XCTAssertEqual(radio.track.number, 0, "just started: back a track")
        play(radio.synth, seconds: 4)
        radio.tick()
        radio.previous()
        XCTAssertEqual(radio.track.number, 0, "a few seconds in: back to its start")
        radio.previous()
        XCTAssertEqual(radio.track.number, Station.trackCount - 1, "wraps round")

        radio.select(.rainy)
        XCTAssertEqual(radio.station, .rainy)
        XCTAssertEqual(radio.track.station, .rainy)
        radio.next()
        radio.next()
        radio.select(.chill)
        XCTAssertEqual(radio.track.number, Station.trackCount - 1, "each station carries on where it was")
        radio.select(.rainy)
        XCTAssertEqual(radio.track.number, 2)
        XCTAssertTrue(radio.isPlaying, "switching stations keeps playing")

        let reopened = Radio(defaults: defaults, live: false)
        XCTAssertEqual(reopened.station, .rainy, "remembered after a restart")
        XCTAssertEqual(reopened.track.number, 2)
    }

    func testPlaysTheNextTrackWhenOneEnds() {
        // The shortest Game Boy track, so this doesn't take forever in a debug build.
        let lengths = (0..<Station.trackCount).map { LofiTrack(station: .gameBoy, number: $0).length }
        let number = lengths.indices.min { lengths[$0] < lengths[$1] }!
        defaults.set("gameBoy", forKey: "MenuBarLofi.station")
        defaults.set(number, forKey: "MenuBarLofi.track.gameBoy")
        let radio = Radio(defaults: defaults, live: false)
        XCTAssertEqual(radio.track.number, number)
        radio.play()
        play(radio.synth, seconds: 0.5)
        radio.tick() // follows the synth onto the track and queues the one after
        play(radio.synth, seconds: radio.track.duration)
        radio.tick()
        XCTAssertEqual(radio.track.number, (number + 1) % Station.trackCount, "on to the next by itself")
        XCTAssertLessThan(radio.elapsed, 1)
        XCTAssertEqual(defaults.integer(forKey: "MenuBarLofi.track.gameBoy"), radio.track.number)
    }

    func testSleepTimerFadesThenStops() throws {
        let radio = Radio(defaults: defaults, live: false)
        radio.play()
        radio.sleep(minutes: 10)
        XCTAssertNotNil(radio.sleepEnd)
        XCTAssertEqual(radio.synth.target, 0.49, accuracy: 0.001, "full volume till the last 30 seconds")
        radio.sleep(minutes: 0.25) // 15 seconds left
        XCTAssertEqual(radio.synth.target, 0.49 * 0.5, accuracy: 0.01, "halfway down")
        radio.sleep(minutes: nil)
        XCTAssertEqual(radio.synth.target, 0.49, accuracy: 0.001, "off again")
        radio.sleep(minutes: 0.0001)
        Thread.sleep(forTimeInterval: 0.02)
        radio.tick()
        XCTAssertFalse(radio.isPlaying, "stopped")
        XCTAssertNil(radio.sleepEnd)
        XCTAssertEqual(radio.synth.target, 0)
    }

    func testFocusTimerPlaysThenStopsWithAChime() {
        let radio = Radio(defaults: defaults, live: false)
        radio.startFocus(minutes: 25)
        XCTAssertTrue(radio.isPlaying, "starting focus starts the music")
        XCTAssertEqual(radio.focusEnd!.timeIntervalSinceNow, 25 * 60, accuracy: 1)
        radio.pause()
        XCTAssertNil(radio.focusEnd)
        XCTAssertEqual(radio.focusLeft!, 25 * 60, accuracy: 1, "pausing the music pauses the clock")
        radio.play()
        XCTAssertEqual(radio.focusEnd!.timeIntervalSinceNow, 25 * 60, accuracy: 1, "and it carries on")
        radio.stopFocus()
        radio.tick()
        XCTAssertTrue(radio.isPlaying, "stopping the timer leaves the music on")
        XCTAssertEqual(radio.focusDone, 0)

        radio.startFocus(minutes: 0.0001)
        Thread.sleep(forTimeInterval: 0.02)
        radio.tick()
        XCTAssertFalse(radio.isPlaying, "time's up: the music stops")
        XCTAssertNil(radio.focusEnd)
        XCTAssertNil(radio.focusLeft)
        XCTAssertEqual(radio.focusDone, 1)
        XCTAssertEqual(radio.synth.target, 0)
    }

    func testChimeIsSoftAndClean() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let buffer = try XCTUnwrap(Chime.buffer(format: format))
        let left = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        XCTAssertEqual(Double(buffer.frameLength) / 44100, Chime.length, accuracy: 0.01)
        XCTAssertTrue(left.allSatisfy(\.isFinite))
        let peak = left.map(abs).max()!
        XCTAssertGreaterThan(peak, 0.1, "you can hear it")
        XCTAssertLessThan(peak, 0.7, "but it's gentle")
        XCTAssertLessThan(abs(left.last!), 0.001, "and ends without a click")
    }
}

final class UpdateCheckerTests: XCTestCase {
    func testVersionsCompareLikeNumbers() {
        XCTAssertTrue(UpdateChecker.isNewer("1.1", than: "1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.10", than: "1.0"))
    }

    func testBannerShowsForNewerVersionsUntilDismissed() throws {
        let store = UserDefaults(suiteName: "MenuBarLofiTests.\(UUID().uuidString)")!
        let checker = UpdateChecker(store: store, current: "1.0")
        let feed = try JSONDecoder().decode(UpdateChecker.Update.self, from: Data(#"{"version":"1.1","message":"Fresh sounds","url":"https://ko-fi.com/kian"}"#.utf8))
        checker.consider(feed)
        XCTAssertEqual(checker.available?.message, "Fresh sounds")
        XCTAssertEqual(checker.link.absoluteString, "https://ko-fi.com/kian")
        checker.dismiss()
        XCTAssertNil(checker.available)
        checker.consider(feed)
        XCTAssertNil(checker.available, "stays hidden after dismissing")
        checker.consider(UpdateChecker.Update(version: "1.2"))
        XCTAssertNotNil(checker.available, "a newer one shows again")
        checker.consider(UpdateChecker.Update(version: "1.0"))
        XCTAssertNil(checker.available, "never for the version you already have")
    }
}
