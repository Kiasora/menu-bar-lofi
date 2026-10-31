import Foundation

/// One lo-fi track, written out in code from its station and number: the same every time, and 720 of them cost nothing
/// to ship. The core is Menu Bar Emulator's tape (jazzy chords, a hummable tune, swung drums, vinyl); each station
/// picks its own keys, tempos, instruments, drum kit and weather, and every track rolls its own chords and tune.
struct LofiTrack {
    static let sampleRate = 44100.0

    enum Kind: UInt8 {
        case keys, piano, guitar, pad, bass, lead, square, ocarina, bell, sax, arp, kick, snare, hat, openHat
    }

    struct Event: Equatable {
        /// Samples from the start of the track.
        var time: Int
        var kind: Kind
        /// MIDI note.
        var note: Int
        var velocity: Float
        /// Samples until the note's let go.
        var length: Int
    }

    /// How the whole track sounds, beyond its notes.
    struct Sound {
        var kit = Kit.dusty
        /// 0…1 each.
        var rain: Float = 0, cafe: Float = 0, vinyl: Float = 1
        /// The lo-fi filter's cutoff, in hertz.
        var tone: Float = 5600
        /// The tape echo's time, in samples.
        var echo = 20_000
    }

    let station: Station
    let number: Int
    /// 0 = C.
    let key: Int
    let minor: Bool
    /// Beats per minute.
    let tempo: Int
    /// In time order.
    let events: [Event]
    /// In samples, the crackle after the music included.
    let length: Int
    let sound: Sound

    var title: String { station.title(number) }
    var duration: Double { Double(length) / Self.sampleRate }

    /// "A minor · 72 bpm"
    var detail: String {
        let names = minor ? ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "G♯", "A", "B♭", "B"]
            : ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
        return "\(names[key]) \(minor ? "minor" : "major") · \(tempo) bpm"
    }
}

/// A drum kit. Every kit plays the same patterns; these numbers change what they sound like.
struct Kit: Equatable {
    /// A thump that drops from `kickPitch + kickSweep` to `kickPitch` hertz, with a click on top.
    var kickPitch: Float = 54, kickSweep: Float = 90, kickDecay: Float = 0.19, kickClick: Float = 0.25, kickLevel: Float = 0.42
    /// A pitched body plus a burst of noise. `snareColor`: how bright the noise is (0…1). `snareAttack`: brushes swish in.
    var snarePitch: Float = 190, snareBody: Float = 0.5, snareBodyDecay: Float = 0.05, snareNoise: Float = 0.8
    var snareDecay: Float = 0.13, snareColor: Float = 0.35, snareAttack: Float = 0, snareLevel: Float = 0.16
    var hatDecay: Float = 0.038, openHatDecay: Float = 0.16, hatColor: Float = 0.4, hatLevel: Float = 0.2
    /// 0…1: how much the hats ring like a ride cymbal.
    var metal: Float = 0
    /// Game Boy noise channel: the noise holds each value for a few samples, gritty and digital.
    var chip = false

    /// Menu Bar Emulator's kit.
    static let dusty = Kit()
    /// A rim click instead of a snare, everything quieter.
    static let soft = Kit(kickPitch: 50, kickSweep: 70, kickDecay: 0.15, kickClick: 0.1, kickLevel: 0.36,
                          snarePitch: 1650, snareBody: 0.9, snareBodyDecay: 0.012, snareNoise: 0.35, snareDecay: 0.03,
                          snareColor: 0.6, snareLevel: 0.13, hatDecay: 0.03, hatColor: 0.35, hatLevel: 0.14)
    /// Deeper kick, crisper snare.
    static let boomBap = Kit(kickPitch: 48, kickSweep: 110, kickDecay: 0.26, kickClick: 0.35, kickLevel: 0.46,
                             snarePitch: 180, snareNoise: 0.95, snareDecay: 0.16, snareColor: 0.45, snareLevel: 0.17,
                             hatDecay: 0.03, hatLevel: 0.18)
    /// Brushes on the snare, a ride for hats.
    static let brushes = Kit(kickPitch: 52, kickSweep: 60, kickDecay: 0.16, kickClick: 0.05, kickLevel: 0.34,
                             snareBody: 0.15, snareNoise: 0.9, snareDecay: 0.2, snareColor: 0.2, snareAttack: 0.015,
                             snareLevel: 0.13, hatDecay: 0.09, openHatDecay: 0.3, hatColor: 0.5, hatLevel: 0.1, metal: 0.5)
    static let chip = Kit(kickPitch: 60, kickSweep: 140, kickDecay: 0.12, kickClick: 0, kickLevel: 0.36,
                          snareBody: 0.3, snareDecay: 0.1, snareLevel: 0.12, hatLevel: 0.12, chip: true)
}

// MARK: - Stations

/// What a station plays: picked from at random, per track.
private struct Recipe {
    var tempos: ClosedRange<Int>
    /// Chance of a minor key.
    var minor: Float
    /// Who plays the tune (repeats make one likelier).
    var leads: [LofiTrack.Kind]
    /// Who plays the chords.
    var comps: [LofiTrack.Kind]
    var basses: [Int]
    var kits: [Kit]
    /// Chances of a pad under the chords, of rain, of Game Boy arpeggios in the bridge, of a music box doubling the
    /// last tune.
    var pads: Float, rain: Float, arps: Float, doubling: Float
    /// How loud the café is (0: no café).
    var cafe: Float = 0
    var tone: ClosedRange<Float>
    /// Slower, roomier tunes.
    var sparse = false
    var swing: ClosedRange<Double>
}

private enum Intro { case standard, melody, piano, picked, bells, chip, pickup, breakdown }
private enum Groove { case standard, halfTime, syncopated, chip }

private struct Opening {
    var lead: LofiTrack.Kind, comp: LofiTrack.Kind, kit: Kit
    var minor: Bool, tempo: Int
}

private extension Station {
    /// A deliberate first track for each station; the rest rotate through related arrangements, not just new seeds.
    var opening: Opening? {
        switch self {
        case .chill: Opening(lead: .guitar, comp: .keys, kit: .dusty, minor: false, tempo: 82)
        case .study: Opening(lead: .piano, comp: .piano, kit: .soft, minor: false, tempo: 72)
        case .rainy: Opening(lead: .guitar, comp: .guitar, kit: .soft, minor: true, tempo: 68)
        case .cafe: nil // Its brushes, walking bass and café already have a clear identity.
        case .night: Opening(lead: .bell, comp: .keys, kit: .soft, minor: true, tempo: 64)
        case .gameBoy: Opening(lead: .square, comp: .keys, kit: .chip, minor: false, tempo: 100)
        }
    }

    var intros: [Intro] {
        switch self {
        case .chill: [.melody, .pickup, .breakdown, .standard]
        case .study: [.piano, .breakdown, .pickup, .standard]
        case .rainy: [.picked, .breakdown, .pickup, .standard]
        case .cafe: [.standard]
        case .night: [.bells, .breakdown, .pickup, .standard]
        case .gameBoy: [.chip, .pickup, .chip, .standard]
        }
    }

    var grooves: [Groove] {
        switch self {
        case .chill: [.syncopated, .standard, .halfTime]
        case .study, .rainy, .night: [.halfTime, .standard]
        case .cafe: [.standard]
        case .gameBoy: [.chip, .syncopated]
        }
    }

    var recipe: Recipe {
        switch self {
        case .chill:
            Recipe(tempos: 74...88, minor: 0.3, leads: [.lead, .sax, .guitar, .ocarina, .bell, .lead], comps: [.keys, .keys, .piano],
                   basses: [0, 1, 2, 5], kits: [.dusty, .boomBap], pads: 0.3, rain: 0.12, arps: 0.2, doubling: 0.5,
                   tone: 4800...5600, swing: 0.12...0.24)
        case .study:
            Recipe(tempos: 66...80, minor: 0.35, leads: [.bell, .guitar, .piano, .ocarina], comps: [.piano, .piano, .keys],
                   basses: [1, 4, 0], kits: [.soft], pads: 0.5, rain: 0.15, arps: 0.1, doubling: 0.3,
                   tone: 4200...5000, sparse: true, swing: 0.08...0.18)
        case .rainy:
            Recipe(tempos: 64...78, minor: 0.75, leads: [.guitar, .sax, .ocarina, .piano], comps: [.piano, .keys, .guitar],
                   basses: [1, 4, 0], kits: [.soft, .boomBap], pads: 0.7, rain: 1, arps: 0, doubling: 0.2,
                   tone: 3800...4600, sparse: true, swing: 0.1...0.2)
        case .cafe:
            Recipe(tempos: 76...92, minor: 0.4, leads: [.sax, .guitar, .sax, .piano], comps: [.guitar, .keys, .guitar],
                   basses: [3, 3, 2], kits: [.brushes], pads: 0.1, rain: 0.08, arps: 0, doubling: 0.2, cafe: 1,
                   tone: 5000...6000, swing: 0.18...0.3)
        case .night:
            Recipe(tempos: 62...76, minor: 0.8, leads: [.sax, .square, .bell, .lead], comps: [.keys, .keys, .piano],
                   basses: [4, 1], kits: [.boomBap, .soft], pads: 0.8, rain: 0.2, arps: 0.15, doubling: 0.3,
                   tone: 3400...4400, sparse: true, swing: 0.12...0.22)
        case .gameBoy:
            Recipe(tempos: 84...108, minor: 0.15, leads: [.lead, .square, .ocarina, .bell, .lead], comps: [.keys],
                   basses: [0, 1, 2], kits: [.dusty, .chip, .dusty], pads: 0, rain: 0, arps: 1, doubling: 1,
                   tone: 6000...7400, swing: 0...0.06)
        }
    }
}

// MARK: - Writing a track

extension LofiTrack {
    private struct Chord {
        /// Semitones above the key.
        var root: Int
        /// Semitones above the root.
        var tones: [Int]
    }

    /// A two-bar idea: its rhythm in 16ths, and how each note moves from the last (in steps through the chord's notes).
    private struct Motif {
        var rhythm: [(step: Int, length: Int)]
        var moves: [Int]
    }

    private enum Part { case intro, tune, bridge, solo, outro }

    private static let maj7 = [0, 4, 7, 11], maj9 = [0, 4, 7, 11, 14], m7 = [0, 3, 7, 10], m9 = [0, 3, 7, 10, 14]
    private static let dom7 = [0, 4, 7, 10], dom9 = [0, 4, 7, 10, 14], m6 = [0, 3, 7, 9], six9 = [0, 4, 7, 9, 14]
    private static let m7b5 = [0, 3, 6, 10], sus = [0, 5, 7, 10]

    private static func chord(_ root: Int, _ tones: [Int]) -> Chord { Chord(root: root, tones: tones) }

    /// Four bars each. A bar has one chord, or two for half a bar each.
    private static let majorProgressions: [[[Chord]]] = [
        [[chord(0, maj7)], [chord(9, m7)], [chord(2, m7)], [chord(7, dom7)]],                    // I vi ii V
        [[chord(5, maj7)], [chord(7, dom7)], [chord(4, m7)], [chord(9, m7)]],                    // IV V iii vi
        [[chord(0, maj9)], [chord(4, dom7)], [chord(9, m9)], [chord(5, maj7)]],                  // I III7 vi IV
        [[chord(2, m9)], [chord(7, dom9)], [chord(0, maj9)], [chord(9, m9)]],                    // ii V I vi
        [[chord(5, maj7)], [chord(4, m7)], [chord(2, m7)], [chord(0, maj7)]],                    // IV iii ii I
        [[chord(0, maj7)], [chord(5, maj7)], [chord(8, maj7), chord(10, dom7)], [chord(0, maj9)]], // I IV bVI bVII I
        [[chord(9, m7)], [chord(5, maj7)], [chord(0, maj7)], [chord(7, dom7)]],                  // vi IV I V
        [[chord(0, maj7)], [chord(4, m7)], [chord(5, maj7)], [chord(5, m6)]],                    // I iii IV iv
        [[chord(5, maj7)], [chord(4, dom7)], [chord(9, m7)], [chord(7, m7), chord(0, dom7)]],    // IV III7 vi v I7
        [[chord(0, maj7)], [chord(0, dom9)], [chord(5, maj7)], [chord(5, m6)]],                  // I I7 IV iv
        [[chord(2, m9)], [chord(7, dom9)], [chord(4, m7)], [chord(9, dom7)]],                    // ii V iii VI7
        [[chord(5, maj7)], [chord(0, maj9)], [chord(5, maj9)], [chord(7, sus)]],                 // IV I IV Vsus
        [[chord(0, six9)], [chord(2, m9)], [chord(4, m7)], [chord(5, maj7)]],                    // I ii iii IV
        [[chord(9, m9)], [chord(2, m9)], [chord(7, dom9)], [chord(0, maj9)]],                    // vi ii V I
        [[chord(0, maj7)], [chord(10, maj7)], [chord(5, maj7)], [chord(0, maj9)]],               // I bVII IV I
        [[chord(5, maj9)], [chord(5, m6)], [chord(0, maj7)], [chord(9, m7)]],                    // IV iv I vi
    ]

    /// Same, counted from the minor key's own root.
    private static let minorProgressions: [[[Chord]]] = [
        [[chord(0, m9)], [chord(5, m9)], [chord(10, dom9)], [chord(3, maj7)]],                   // i iv bVII bIII
        [[chord(0, m7)], [chord(8, maj7)], [chord(3, maj7)], [chord(10, dom7)]],                 // i bVI bIII bVII
        [[chord(0, m9)], [chord(7, m7)], [chord(8, maj7)], [chord(10, dom7)]],                   // i v bVI bVII
        [[chord(2, m7b5)], [chord(7, dom7)], [chord(0, m9)], [chord(0, m7)]],                    // iiø V i
        [[chord(0, m7)], [chord(5, m7)], [chord(7, m7)], [chord(0, m9)]],                        // i iv v i
        [[chord(0, m9)], [chord(5, dom9)], [chord(0, m9)], [chord(5, dom9)]],                    // i IV (dorian)
        [[chord(0, m7)], [chord(10, dom7)], [chord(8, maj7)], [chord(7, dom7)]],                 // i bVII bVI V
        [[chord(8, maj7)], [chord(10, dom9)], [chord(0, m9)], [chord(0, m7)]],                   // bVI bVII i
        [[chord(5, m9)], [chord(7, m7)], [chord(0, m9)], [chord(8, maj7)]],                      // iv v i bVI
        [[chord(0, m9)], [chord(3, maj7)], [chord(5, m9)], [chord(10, dom7), chord(7, dom7)]],   // i bIII iv bVII V
        [[chord(0, m9)], [chord(8, maj9)], [chord(5, m7)], [chord(7, m7)]],                      // i bVI iv v
        [[chord(3, maj7)], [chord(10, dom7)], [chord(5, m7)], [chord(0, m9)]],                   // bIII bVII iv i
    ]

    private static let rhythms: [[(step: Int, length: Int)]] = [
        [(0, 4), (4, 2), (6, 2), (8, 6), (14, 2), (16, 4), (20, 4), (24, 8)],
        [(0, 3), (3, 3), (6, 2), (8, 4), (12, 4), (16, 6), (22, 2), (24, 8)],
        [(2, 2), (4, 2), (6, 4), (10, 2), (12, 4), (18, 2), (20, 2), (22, 2), (24, 8)],
        [(0, 6), (6, 2), (8, 2), (10, 2), (12, 4), (16, 12)],
        [(0, 2), (2, 2), (4, 2), (6, 2), (8, 8), (16, 2), (18, 2), (20, 4), (24, 8)],
        [(0, 8), (8, 4), (12, 4), (16, 8), (24, 8)],
        [(0, 4), (6, 2), (8, 4), (12, 2), (14, 2), (16, 8), (26, 6)],
        [(0, 2), (2, 2), (4, 4), (8, 2), (10, 2), (12, 4), (16, 2), (18, 2), (20, 2), (22, 2), (24, 8)],
        [(0, 3), (3, 3), (6, 4), (10, 2), (12, 2), (14, 2), (16, 8), (24, 4), (28, 4)],
    ]

    private static let sparseRhythms: [[(step: Int, length: Int)]] = [
        [(0, 6), (6, 2), (8, 2), (10, 2), (12, 4), (16, 12)],
        [(0, 8), (8, 4), (12, 4), (16, 8), (24, 8)],
        [(0, 8), (12, 4), (16, 12)],
        [(0, 6), (8, 8), (20, 4), (24, 8)],
        [(4, 4), (8, 8), (16, 4), (22, 10)],
        [(0, 4), (6, 2), (8, 4), (12, 2), (14, 2), (16, 8), (26, 6)],
        [(2, 6), (8, 8), (18, 6), (24, 8)],
    ]

    private static let compings: [[(step: Int, length: Int)]] = [
        [(0, 16)], [(0, 7), (10, 6)], [(0, 3), (3, 7), (12, 4)], [(0, 6), (6, 2), (8, 8)],
        [(0, 4), (6, 4), (12, 4)], [(0, 10), (14, 2)], [(2, 6), (8, 8)],
    ]

    private static let strums: [[(step: Int, length: Int)]] = [
        [(0, 4), (4, 2), (6, 2), (8, 4), (12, 2), (14, 2)], [(0, 6), (6, 2), (10, 6)], [(0, 3), (3, 3), (6, 2), (8, 8)],
        [(0, 8), (8, 8)], [(0, 4), (6, 2), (8, 4), (14, 2)],
    ]

    /// (step, length, tone): tone 0…3 is the chord's root, third, fifth or seventh; 4 is the root an octave up.
    private static let basses: [[(step: Int, length: Int, tone: Int)]] = [
        [(0, 7, 0), (10, 4, 0), (14, 2, 2)],
        [(0, 12, 0), (12, 4, 2)],
        [(0, 6, 0), (6, 2, 4), (8, 6, 2), (14, 2, 0)],
        [(0, 4, 0), (4, 4, 1), (8, 4, 2), (12, 4, 3)], // walking up the chord
        [(0, 14, 0)],
        [(0, 3, 0), (3, 5, 0), (8, 4, 2), (12, 4, 4)],
    ]

    private static let kicks = [[0, 10], [0, 7, 10], [0, 9], [0, 6, 10], [0, 3, 10], [0, 8, 11]]

    private static let forms: [[(part: Part, bars: Int)]] = [
        [(.intro, 4), (.tune, 16), (.bridge, 8), (.tune, 16), (.outro, 4)],
        [(.intro, 4), (.tune, 16), (.bridge, 8), (.solo, 8), (.tune, 16), (.outro, 4)],
        [(.intro, 4), (.tune, 16), (.solo, 8), (.tune, 16), (.outro, 4)],
        [(.intro, 8), (.tune, 16), (.bridge, 8), (.tune, 16), (.outro, 4)],
    ]

    private static func motif(_ rng: inout LofiRandom, _ rhythms: [[(step: Int, length: Int)]]) -> Motif {
        let rhythm = rhythms[rng.int(rhythms.count)]
        var moves = [0], total = 0
        for _ in 1..<rhythm.count {
            // Mostly steps; after a leap, a step back the other way.
            let last = moves[moves.count - 1]
            var move = abs(last) >= 2 ? -last.signum() : [1, -1, 1, 2, -1, -2, 3, 1, -1][rng.int(9)]
            if abs(total + move) > 4 { move = -move }
            moves.append(move)
            total += move
        }
        return Motif(rhythm: rhythm, moves: moves)
    }

    /// The chord without its root (the bass has that) plus its 9th, kept around middle C.
    private static func voicing(_ chord: Chord, key: Int) -> [Int] {
        let root = 48 + (key + chord.root) % 12
        var notes = (Array(chord.tones.dropFirst().prefix(3)) + [14]).map { root + $0 }
        while notes[0] < 52 { notes = notes.map { $0 + 12 } }
        return notes
    }

    /// An open guitar shape: root and fifth down low, the seventh, then the third and fifth an octave up.
    private static func guitarVoicing(_ chord: Chord, key: Int) -> [Int] {
        let root = 40 + (key + chord.root + 8) % 12
        let tones = chord.tones
        return [root, root + tones[2], root + tones[3], root + 12 + tones[1], root + 12 + tones[2]]
    }

    private static func range(_ kind: Kind) -> ClosedRange<Int> {
        switch kind {
        case .bell: 74...93
        case .sax: 60...79
        case .guitar: 62...81
        default: 67...86
        }
    }

    init(station: Station, number: Int) {
        var rng = LofiRandom(state: station.seed &+ UInt64(truncatingIfNeeded: number) &* 0x2545_F491_4F6C_DD1D)
        let recipe = station.recipe
        func pick<T>(_ options: [T]) -> T { options[rng.int(options.count)] }
        func between(_ range: ClosedRange<Float>) -> Float { range.lowerBound + rng.float() * (range.upperBound - range.lowerBound) }

        let signature = number % Station.trackCount == 0 ? station.opening : nil
        let variation = (number % Station.trackCount + Station.trackCount) % Station.trackCount
        let intro = station.intros[variation % station.intros.count]
        let groove = station.grooves[(variation / 2) % station.grooves.count]
        let minor = signature?.minor ?? (rng.float() < recipe.minor)
        // Each track a fifth from the last, like a DJ mixing in key: never the same key twice in a row, every key in turn.
        let key = (number * 7 + Int(station.seed % 12)) % 12
        let tempo = signature?.tempo ?? (recipe.tempos.lowerBound + rng.int(recipe.tempos.count))
        let beat = 60 / Double(tempo) * Self.sampleRate
        let sixteenth = beat / 4
        let swing = Double(between(Float(recipe.swing.lowerBound)...Float(recipe.swing.upperBound)))
        let progressions = minor ? Self.minorProgressions : Self.majorProgressions
        let verseIndex = rng.int(progressions.count)
        let verse = progressions[verseIndex]
        let bridge = progressions[(verseIndex + 1 + rng.int(progressions.count - 1)) % progressions.count] // never the verse's
        let lead = signature?.lead ?? pick(recipe.leads)
        let others = recipe.leads.filter { $0 != lead }
        let counter = others.isEmpty ? Kind.bell : pick(others)
        let comp = signature?.comp ?? pick(recipe.comps)
        let pads = station == .study && signature != nil ? false : rng.float() < recipe.pads
        let arps = rng.float() < recipe.arps
        let doubled = lead != .bell && rng.float() < recipe.doubling
        let comping = pick(Self.compings), bridgeComping = pick(Self.compings)
        let strumming = pick(Self.strums), bridgeStrumming = pick(Self.strums)
        let bassStyle = Self.basses[pick(recipe.basses)]
        let kick = pick(Self.kicks)
        let rhythms = recipe.sparse ? Self.sparseRhythms : Self.rhythms
        let main = Self.motif(&rng, rhythms), answer = Self.motif(&rng, rhythms), third = Self.motif(&rng, rhythms)
        let solo = Self.motif(&rng, rhythms)
        let form = pick(Self.forms)
        let sound = Sound(kit: signature?.kit ?? pick(recipe.kits), rain: rng.float() < recipe.rain ? between(0.45...1) : 0,
                          cafe: recipe.cafe * between(0.7...1), vinyl: between(0.7...1.2), tone: between(recipe.tone),
                          echo: Int(beat * pick([0.75, 0.75, 0.5, 1])))

        var parts: [Part] = [], sectionStart: [Int] = []
        for section in form {
            sectionStart += Array(repeating: parts.count, count: section.bars)
            parts += Array(repeating: section.part, count: section.bars)
        }
        let barCount = parts.count
        var events: [Event] = []
        events.reserveCapacity(4000)

        func time(_ bar: Int, _ step: Int) -> Int {
            Int((Double(bar * 16 + step) + (step % 2 == 1 ? swing : 0)) * sixteenth)
        }
        func add(_ kind: Kind, _ note: Int, _ velocity: Float, _ bar: Int, _ step: Int, steps: Double, nudge: Int = 0) {
            events.append(Event(time: max(0, time(bar, step) + nudge), kind: kind, note: note, velocity: velocity, length: Int(steps * sixteenth)))
        }
        func bars(_ bar: Int) -> [Chord] { (parts[bar] == .bridge ? bridge : verse)[bar % 4] }
        func chord(_ bar: Int, _ step: Int) -> Chord {
            let chords = bars(bar)
            return chords[step < 8 ? 0 : chords.count - 1]
        }
        /// Just the chords, held: the first four bars and the outro.
        func plain(_ bar: Int) -> Bool { bar < 4 || parts[bar] == .outro }
        func loose(_ bar: Int) -> Bool { parts[bar] == .bridge || parts[bar] == .solo }

        // The chords, rolled like a lazy hand (keys, piano), or strummed (guitar).
        for bar in 0..<barCount {
            let split = bars(bar).count > 1
            if comp == .guitar {
                let pattern = split ? [(step: 0, length: 8), (step: 8, length: 8)] : plain(bar) ? [(step: 0, length: 16)]
                    : loose(bar) ? bridgeStrumming : strumming
                for (index, hit) in pattern.enumerated() {
                    let notes = Self.guitarVoicing(chord(bar, hit.step), key: key)
                    let down = index % 2 == 0 || hit.step % 4 == 0
                    let velocity = (down ? 0.6 : 0.45) + rng.float() * 0.08
                    for (i, note) in (down ? notes : Array(notes.reversed().prefix(4))).enumerated() {
                        add(.guitar, note, velocity * (1 - 0.05 * Float(i)), bar, hit.step, steps: Double(hit.length) - 0.2, nudge: i * 420)
                    }
                }
            } else {
                let pattern = split ? [(step: 0, length: 8), (step: 8, length: 8)] : plain(bar) ? [(step: 0, length: 16)]
                    : loose(bar) ? bridgeComping : comping
                for hit in pattern {
                    let velocity = (hit.step == 0 ? 0.62 : 0.5) + rng.float() * 0.08
                    for (i, note) in Self.voicing(chord(bar, hit.step), key: key).enumerated() {
                        add(comp, note, velocity, bar, hit.step, steps: Double(hit.length) - 0.3, nudge: i * 530)
                    }
                }
            }
            // A soft pad holding each chord, swelling in the bridge and solo.
            if pads, bar < barCount - 2 {
                let chords = bars(bar)
                for (half, c) in chords.enumerated() {
                    for note in Self.voicing(c, key: key) {
                        add(.pad, note, loose(bar) ? 0.75 : 0.55, bar, half * 8, steps: 16 / Double(chords.count) - 0.1)
                    }
                }
            }
        }

        // Different openings earn their space: fingerpicking and sparse motifs wait for the beat; chip tunes jump straight in.
        let beatless = intro == .breakdown || intro == .picked || intro == .piano || intro == .bells
        let rhythmStart = intro == .chip ? 0 : beatless ? 4 : 2

        // Bass.
        for bar in rhythmStart..<barCount {
            let pattern = bar == barCount - 1 ? [(step: 0, length: 16, tone: 0)]
                : bars(bar).count > 1 ? [(step: 0, length: 8, tone: 0), (step: 8, length: 8, tone: 0)]
                : bassStyle
            for hit in pattern {
                let c = chord(bar, hit.step)
                let root = 36 + (key + c.root) % 12
                add(.bass, root + (hit.tone == 4 ? 12 : c.tones[hit.tone]), 0.75 + rng.float() * 0.1, bar, hit.step, steps: Double(hit.length) - 0.4)
            }
        }

        // Backbeats, half-time space and chip pulses differ between tracks rather than only changing the drum samples.
        for bar in rhythmStart..<(barCount - 2) {
            let full = bar >= (intro == .chip ? 0 : 4) && parts[bar] != .outro
            for step in stride(from: 0, to: 16, by: groove == .chip ? 1 : 2) where full || step % 4 == 0 {
                let open = full && bar % 8 == 7 && step == 14
                let velocity = (step % 4 == 0 ? 0.5 : 0.32) * (full ? 1 : 0.7) + rng.float() * 0.08
                add(open ? .openHat : .hat, 0, velocity, bar, step, steps: 1, nudge: rng.int(160) - 80)
            }
            guard full else { continue }
            if bar % 2 == 1 { add(.hat, 0, 0.22, bar, 15, steps: 1) }
            let breather = parts[bar] == .bridge && bar < sectionStart[bar] + 2
            let kicks = groove == .chip ? [0, 8] : groove == .halfTime ? [0, 10] : kick
            for step in breather ? [0] : kicks { add(.kick, 0, step == 0 ? 0.9 : 0.7, bar, step, steps: 1) }
            guard !breather else { continue }
            if groove == .halfTime {
                add(.snare, 0, 0.78 + rng.float() * 0.08, bar, 8, steps: 1, nudge: rng.int(120))
            } else {
                add(.snare, 0, 0.75 + rng.float() * 0.08, bar, 4, steps: 1, nudge: rng.int(120))
                add(.snare, 0, 0.78 + rng.float() * 0.08, bar, 12, steps: 1, nudge: rng.int(120))
                if groove == .syncopated && bar % 2 == 1 { add(.snare, 0, 0.3, bar, 14, steps: 1) }
            }
            if groove != .halfTime && bar % 4 == 3 { add(.snare, 0, 0.22, bar, 15, steps: 1) }
        }

        // The tune. Each note comes from the chord under it (chord tones on the strong beats, color notes between), so
        // a motif repeated over new chords turns into a sequence. `ending`: true lands home on the key's root, false
        // anywhere else (a question the next phrase answers). Returns the last note so the next idea carries on.
        func melody(_ motif: Motif, _ kind: Kind, _ bar: Int, from pitch: Int, range: ClosedRange<Int>,
                    velocity: Float = 1, ending: Bool? = nil) -> Int {
            var pitch = pitch
            for (i, note) in motif.rhythm.enumerated() {
                let b = bar + note.step / 16, s = note.step % 16
                let c = chord(b, s)
                let strong = s % 8 == 0 || note.length >= 6
                var allowed = Set(c.tones.map { (key + c.root + $0) % 12 })
                if !strong { allowed.formUnion([2, c.tones.contains(4) ? 9 : 5].map { (key + c.root + $0) % 12 }) }
                var move = motif.moves[i]
                if i == motif.rhythm.count - 1, let home = ending {
                    let tonic = key % 12
                    if home { allowed = [allowed.contains(tonic) ? tonic : (key + c.root) % 12] } else if allowed.count > 1 { allowed.remove(tonic) }
                    move = 0
                }
                let notes = range.filter { allowed.contains($0 % 12) }
                guard let nearest = notes.indices.min(by: { abs(notes[$0] - pitch) < abs(notes[$1] - pitch) }) else { continue }
                pitch = notes[min(max(nearest + move, 0), notes.count - 1)]
                add(kind, pitch, velocity * ((strong ? 0.8 : 0.68) + rng.float() * 0.08), b, s, steps: Double(note.length) * 0.92)
            }
            return pitch
        }
        func phrase(_ kind: Kind, _ bar: Int, from pitch: Int, range: ClosedRange<Int>, velocity: Float = 1, home: Bool) -> Int {
            var p = melody(main, kind, bar, from: pitch, range: range, velocity: velocity)
            p = melody(main, kind, bar + 2, from: p, range: range, velocity: velocity)
            p = melody(answer, kind, bar + 4, from: p, range: range, velocity: velocity)
            return melody(main, kind, bar + 6, from: p, range: range, velocity: velocity, ending: home)
        }

        let leadRange = Self.range(lead)
        let anchor = lead == .bell ? 72 + key % 12 : leadRange.lowerBound + 5 + key % 12
        let counterRange = counter == .bell ? 79...98 : Self.range(counter)
        let counterAnchor = counter == .bell ? anchor + 12 : counterRange.lowerBound + 5 + key % 12
        /// Eight bars of Game Boy-style arpeggios up and down each chord.
        func arpeggios(_ bar: Int) {
            for b in bar..<(bar + 8) {
                for step in 0..<16 {
                    let c = chord(b, step)
                    let tones = c.tones.prefix(4).map { 72 + (key + c.root + $0) % 12 }.sorted()
                    let cycle = tones + Array(tones.reversed().dropFirst().dropLast())
                    add(.arp, cycle[step % cycle.count], step % 4 == 0 ? 0.42 : 0.3, b, step, steps: 0.7)
                }
            }
        }
        /// Rainy intros: a slow fingerpicked figure instead of the usual chord-and-hat opening.
        func picked(_ bar: Int) {
            let shape = [0, 2, 3, 4, 2, 3, 1, 4]
            for b in bar..<barCount where parts[b] == .intro {
                for (i, step) in stride(from: 0, to: 16, by: 2).enumerated() {
                    let notes = Self.guitarVoicing(chord(b, step), key: key)
                    add(.guitar, notes[shape[i]], i % 4 == 0 ? 0.5 : 0.4, b, step, steps: 1.6)
                }
            }
        }
        var tunes = 0
        for bar in 0..<barCount where sectionStart[bar] == bar {
            switch parts[bar] {
            case .tune:
                // The tune twice: asking, then answering. The last time round a music box may double it an octave up.
                let end = phrase(lead, bar, from: anchor, range: leadRange, home: false)
                _ = phrase(lead, bar + 8, from: end, range: leadRange, home: true)
                if doubled, tunes > 0 {
                    _ = phrase(.bell, bar + 8, from: end + 12, range: (leadRange.lowerBound + 12)...(leadRange.upperBound + 12), velocity: 0.45, home: true)
                }
                tunes += 1
            case .bridge:
                // The lead rests; another voice plays a new idea, maybe over Game Boy-style arpeggios.
                let end = melody(third, counter, bar, from: counterAnchor, range: counterRange, velocity: 0.8)
                _ = melody(third, counter, bar + 4, from: end, range: counterRange, velocity: 0.8, ending: false)
                if arps { arpeggios(bar) }
            case .solo:
                // The lead noodles on new ideas, a little softer.
                if arps { arpeggios(bar) }
                var p = melody(solo, lead, bar, from: anchor, range: leadRange, velocity: 0.85)
                p = melody(answer, lead, bar + 2, from: p, range: leadRange, velocity: 0.85)
                p = melody(solo, lead, bar + 4, from: p, range: leadRange, velocity: 0.85)
                _ = melody(third, lead, bar + 6, from: p, range: leadRange, velocity: 0.85, ending: false)
            case .outro:
                // The first idea one last time, landing home.
                _ = melody(main, lead, bar, from: anchor, range: leadRange, velocity: 0.75, ending: true)
            case .intro:
                switch intro {
                case .melody:
                    _ = melody(main, lead, bar, from: anchor, range: leadRange, velocity: 0.8, ending: false)
                case .piano:
                    _ = melody(third, .piano, bar, from: 72, range: 60...79, velocity: 0.7, ending: false)
                case .picked: picked(bar)
                case .bells:
                    _ = melody(third, .bell, bar, from: anchor, range: 74...93, velocity: 0.65, ending: false)
                case .chip:
                    _ = melody(main, .square, bar, from: anchor, range: leadRange, velocity: 0.8, ending: false)
                    arpeggios(bar)
                case .pickup:
                    _ = melody(third, counter, bar + 1, from: counterAnchor, range: counterRange, velocity: 0.55, ending: false)
                case .standard, .breakdown: break
                }
            }
        }

        events.sort { $0.time < $1.time }
        let end = Double(barCount * 16) * sixteenth + 2.5 * Self.sampleRate // a moment of crackle before the next
        self.init(station: station, number: number, key: key, minor: minor, tempo: tempo, events: events, length: Int(end), sound: sound)
    }
}

/// SplitMix64: tiny, fast, and the same numbers for the same seed.
struct LofiRandom {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }

    /// 0..<1
    mutating func float() -> Float { Float(next() >> 40) / Float(1 << 24) }
}
