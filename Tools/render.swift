// Renders the app's lo-fi offline, for checking levels and making preview clips. Built with the app's own sources:
//   swiftc -O -parse-as-library Tools/render.swift MenuBarLofi/Core/{Station,LofiTrack,LofiSynth}.swift -o render
//   ./render stats                       loudness and speed per station
//   ./render kinds                       loudness of each instrument on its own
//   ./render preview <out.wav>           a ~2 minute tour of all six stations
//   ./render track <out.wav> <station> <number> [from seconds] [for seconds]
import Foundation

let rate = Int(LofiTrack.sampleRate)

/// Plays `track` from `from` seconds in for `seconds`, at full volume. Later starts skip the fade-in; zero keeps the exact opening.
func render(_ track: LofiTrack, from: Double, seconds: Double) -> (left: [Float], right: [Float]) {
    let synth = LofiSynth()
    synth.queue(track, now: true)
    synth.target = 1
    var left = [Float](repeating: 0, count: 512), right = left
    let skip = Int((from > 0 ? max(from, 2) : 0) * Double(rate)) / 512
    for _ in 0..<skip { synth.render(left: &left, right: &right, count: 512) }
    var outL: [Float] = [], outR: [Float] = []
    let total = Int(seconds * Double(rate))
    while outL.count < total {
        synth.render(left: &left, right: &right, count: 512)
        outL += left
        outR += right
    }
    return (Array(outL.prefix(total)), Array(outR.prefix(total)))
}

func levels(_ samples: [Float]) -> (rms: Float, peak: Float) {
    var sum: Float = 0, peak: Float = 0
    for s in samples { sum += s * s; peak = max(peak, abs(s)) }
    return ((sum / Float(max(samples.count, 1))).squareRoot(), peak)
}

func decibels(_ x: Float) -> String { String(format: "%6.1f dB", 20 * log10(max(x, 1e-9))) }

func writeWAV(_ left: [Float], _ right: [Float], to path: String) {
    var data = Data()
    func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
    let frames = left.count
    data.append("RIFF".data(using: .ascii)!)
    append(UInt32(36 + frames * 4).littleEndian)
    data.append("WAVEfmt ".data(using: .ascii)!)
    append(UInt32(16).littleEndian)
    append(UInt16(1).littleEndian) // PCM
    append(UInt16(2).littleEndian)
    append(UInt32(rate).littleEndian)
    append(UInt32(rate * 4).littleEndian)
    append(UInt16(4).littleEndian)
    append(UInt16(16).littleEndian)
    data.append("data".data(using: .ascii)!)
    append(UInt32(frames * 4).littleEndian)
    for i in 0..<frames {
        append(Int16(max(-1, min(1, left[i])) * 32767).littleEndian)
        append(Int16(max(-1, min(1, right[i])) * 32767).littleEndian)
    }
    try! data.write(to: URL(fileURLWithPath: path))
}

@main
struct Render {
    static func main() {
        let args = CommandLine.arguments
        switch args.count > 1 ? args[1] : "" {
        case "stats":
            for station in Station.allCases {
                var rms: [Float] = [], peak: Float = 0, busy = 0.0, made = 0.0
                for number in stride(from: 0, to: Station.trackCount, by: 20) {
                    let track = LofiTrack(station: station, number: number)
                    let start = CFAbsoluteTimeGetCurrent()
                    let (l, r) = render(track, from: 30, seconds: 30)
                    busy += CFAbsoluteTimeGetCurrent() - start
                    made += 32
                    let level = levels(l + r)
                    rms.append(level.rms)
                    peak = max(peak, level.peak)
                }
                let mean = rms.reduce(0, +) / Float(rms.count)
                print("\(station.name.padding(toLength: 9, withPad: " ", startingAt: 0)) rms \(decibels(mean)) (\(decibels(rms.min()!))…\(decibels(rms.max()!))) peak \(decibels(peak))  \(Int(made / busy))× real time")
            }
        case "kinds":
            // Each instrument alone, from tracks that use it, against the electric piano.
            let kinds: [LofiTrack.Kind] = [.keys, .piano, .guitar, .pad, .bass, .lead, .square, .ocarina, .bell, .sax, .arp, .kick, .snare, .hat]
            for kind in kinds {
                var rms: [Float] = []
                for station in Station.allCases {
                    for number in 0..<12 {
                        let track = LofiTrack(station: station, number: number)
                        let only = track.events.filter { $0.kind == kind }
                        guard only.count > 40 else { continue }
                        let solo = LofiTrack(station: station, number: number, key: track.key, minor: track.minor, tempo: track.tempo,
                                             events: only, length: track.length,
                                             sound: LofiTrack.Sound(kit: track.sound.kit, vinyl: 0, tone: track.sound.tone, echo: track.sound.echo))
                        // Only the stretch where it actually plays.
                        let first = Double(only[0].time) / Double(rate)
                        let (l, r) = render(solo, from: first + 2, seconds: 20)
                        rms.append(levels(l + r).rms)
                        if rms.count >= 4 { break }
                    }
                    if rms.count >= 4 { break }
                }
                guard !rms.isEmpty else { print("\(kind): not found"); continue }
                print("\(String(describing: kind).padding(toLength: 8, withPad: " ", startingAt: 0)) \(decibels(rms.reduce(0, +) / Float(rms.count)))")
            }
            for (name, sound) in [("rain", LofiTrack.Sound(rain: 1, vinyl: 0)), ("cafe", LofiTrack.Sound(cafe: 1, vinyl: 0)), ("vinyl", LofiTrack.Sound())] {
                let quiet = LofiTrack(station: .chill, number: 0, key: 0, minor: false, tempo: 80, events: [], length: rate * 40, sound: sound)
                let (l, r) = render(quiet, from: 8, seconds: 20)
                print("\(name.padding(toLength: 8, withPad: " ", startingAt: 0)) \(decibels(levels(l + r).rms))")
            }
        case "track":
            let station = Station(rawValue: args[3])!
            let track = LofiTrack(station: station, number: Int(args[4])!)
            let (l, r) = render(track, from: args.count > 5 ? Double(args[5])! : 0, seconds: args.count > 6 ? Double(args[6])! : track.duration)
            print("\(track.title) — \(track.detail), \(Int(track.duration))s, \(track.events.count) notes")
            writeWAV(l, r, to: args[2])
        case "preview":
            // The first 20 seconds of every station's deliberately different opening, crossfaded.
            let picks = Station.allCases.map { ($0, 0, 0.0) }
            let fade = 2 * rate
            var outL: [Float] = [], outR: [Float] = []
            for (index, pick) in picks.enumerated() {
                let track = LofiTrack(station: pick.0, number: pick.1)
                print("\(pick.0.name): \(track.title) — \(track.detail)")
                var (l, r) = render(track, from: pick.2, seconds: 21)
                for i in 0..<fade { // fade each clip in and out, then overlap the fades
                    let gain = Float(i) / Float(fade)
                    l[i] *= gain; r[i] *= gain
                    l[l.count - 1 - i] *= gain; r[r.count - 1 - i] *= gain
                }
                if index == 0 {
                    outL = l; outR = r
                } else {
                    let start = outL.count - fade
                    for i in 0..<fade { outL[start + i] += l[i]; outR[start + i] += r[i] }
                    outL += l[fade...]; outR += r[fade...]
                }
            }
            writeWAV(outL, outR, to: args[2])
            print(String(format: "%.0f seconds", Double(outL.count) / Double(rate)))
        default:
            print("usage: render stats | kinds | preview <out.wav> | track <out.wav> <station> <number> [from] [seconds]")
        }
    }
}
