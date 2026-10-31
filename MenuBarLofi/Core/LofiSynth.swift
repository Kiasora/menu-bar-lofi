import Foundation
import Synchronization

private let sampleRate = Float(LofiTrack.sampleRate)
private let twoPi = 2 * Float.pi

/// Per-sample multiplier that takes a level to about a third in `seconds`.
private func decayFactor(_ seconds: Float) -> Float { exp(-1 / (seconds * sampleRate)) }

/// One-pole low-pass coefficient for a cutoff in hertz.
private func lowPassFactor(_ hertz: Float) -> Float { 1 - exp(-twoPi * hertz / sampleRate) }

@inline(__always) private func wrap(_ phase: Float) -> Float { phase >= 1 ? phase - 1 : phase }

/// Smooths a waveform's jump so the pulse doesn't alias (PolyBLEP).
@inline(__always) private func polyBLEP(_ t: Float, _ dt: Float) -> Float {
    if t < dt { let x = t / dt; return x + x - x * x - 1 }
    if t > 1 - dt { let x = (t - 1) / dt; return x * x + x + x + 1 }
    return 0
}

/// White noise, -1…1 (xorshift).
@inline(__always) private func noise(_ state: inout UInt32) -> Float {
    state ^= state << 13
    state ^= state >> 17
    state ^= state << 5
    return Float(Int32(bitPattern: state)) / 2_147_483_648
}

/// Plays lo-fi tracks one after another: chords on electric piano, piano or guitar, a pad, bass, the tune on one of
/// eight voices and drums from one of five kits, through a tape echo, a small room, a dark lo-fi filter, vinyl, and
/// maybe rain or a café.
///
/// `render` runs on the audio thread, so it never locks, allocates or frees. `queue` copies a track into whichever of
/// two fixed slots isn't playing and hands it over with an atomic flag.
final class LofiSynth {
    static let fadeIn: Float = 1.5
    static let fadeOut: Float = 0.8
    /// The most notes a track can have.
    static let maxEvents = 12_000
    private static let block = 64, capacity = 4096, voiceCount = 48, echoLength = 88_200, stringLength = 1024
    /// Next fades the old track out this fast, then the new one in.
    private static let skipOut: Float = 0.2, skipIn: Float = 0.05

    private struct Slot {
        let events: UnsafeMutablePointer<LofiTrack.Event>
        var count = 0
        var length = 0
        var sound = LofiTrack.Sound()
    }

    private let slots = UnsafeMutablePointer<Slot>.allocate(capacity: 2)
    /// Bit 0: the slot that's playing. Bit 1: the other slot holds a queued track. Bit 2: start it now (Next).
    private let handoff = Atomic<Int>(0)
    private let started = Atomic<Int>(0)
    private let place = Atomic<Int>(0)
    private let targetBits = Atomic<UInt32>(0)

    /// The volume to fade to; 0 fades out. Safe to set from any thread.
    var target: Float {
        get { Float(bitPattern: targetBits.load(ordering: .relaxed)) }
        set { targetBits.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// How many queued tracks it has started. Safe to read from any thread.
    var switches: Int { started.load(ordering: .acquiring) }

    /// Samples into the track that's playing. Safe to read from any thread.
    var position: Int { place.load(ordering: .relaxed) }

    /// 0…1, how far it's faded in.
    private(set) var fade: Float = 0

    // Everything from here on belongs to the audio thread.
    private var playing = 0, cursor = 0, next = 0
    private var volume: Float = 0, skipGain: Float = 1
    private var sound = LofiTrack.Sound()
    private var kit = Kit.dusty

    private let voices = UnsafeMutablePointer<Voice>.allocate(capacity: LofiSynth.voiceCount)
    /// Each voice's guitar string.
    private let strings = UnsafeMutablePointer<Float>.allocate(capacity: LofiSynth.voiceCount * LofiSynth.stringLength)
    private var kick = Drum(), snare = Drum(), hat = Drum()
    /// Left, right, kick (never ducked), duck amount, room send, echo send.
    private let bus = UnsafeMutablePointer<Float>.allocate(capacity: LofiSynth.capacity * 6)
    private let echoL = UnsafeMutablePointer<Float>.allocate(capacity: LofiSynth.echoLength)
    private let echoR = UnsafeMutablePointer<Float>.allocate(capacity: LofiSynth.echoLength)
    private let room = Reverb()
    private var echoIndex = 0, echoDelay = 20_000
    private var echoTone: Float = 0, toneL1: Float = 0, toneL2: Float = 0, toneR1: Float = 0, toneR2: Float = 0
    private var masterTone = lowPassFactor(5600)
    private var hiss: Float = 0, crackle: Float = 0, crackleTone: Float = 0
    private var noiseState: UInt32 = 0x2545_F491
    private var wow: Float = 1, tremolo: Float = 0, gust: Float = 1
    private var wowPhase: Float = 0, flutterPhase: Float = 0, tremoloPhase: Float = 0, gustPhase: Float = 0

    // Weather: how much there is now (it glides to the track's), the rain's filters and drops, the café.
    private var rain: Float = 0, cafe: Float = 0
    private var rainL1: Float = 0, rainL2: Float = 0, rainR1: Float = 0, rainR2: Float = 0
    private var drop: Float = 0, dropTone: Float = 0, dropPan: Float = 0
    private let talkers = UnsafeMutablePointer<Talker>.allocate(capacity: 3)
    private var clink = Clink()

    private let shimmerFall = decayFactor(0.06), pianoFall = decayFactor(0.25), kickSweep = decayFactor(0.03)
    private let kickClick = decayFactor(0.0015), saxScoop = decayFactor(0.04), dropFall = decayFactor(0.004)
    private let clinkFall = decayFactor(0.15)
    private var snareBodyFall = decayFactor(0.05)
    private let leadTone = lowPassFactor(2500), arpTone = lowPassFactor(3200), padTone = lowPassFactor(1100)
    private let guitarTone = lowPassFactor(3200)

    init() {
        for index in 0..<2 {
            (slots + index).initialize(to: Slot(events: .allocate(capacity: Self.maxEvents)))
        }
        voices.initialize(repeating: Voice(), count: Self.voiceCount)
        strings.initialize(repeating: 0, count: Self.voiceCount * Self.stringLength)
        bus.initialize(repeating: 0, count: Self.capacity * 6)
        echoL.initialize(repeating: 0, count: Self.echoLength)
        echoR.initialize(repeating: 0, count: Self.echoLength)
        talkers.initialize(to: Talker(voice: 115, pan: -0.55))
        (talkers + 1).initialize(to: Talker(voice: 205, pan: 0.15))
        (talkers + 2).initialize(to: Talker(voice: 165, pan: 0.6))
    }

    deinit {
        for index in 0..<2 { slots[index].events.deallocate() }
        slots.deallocate()
        voices.deallocate()
        strings.deallocate()
        bus.deallocate()
        echoL.deallocate()
        echoR.deallocate()
        talkers.deallocate()
    }

    /// Copies `track` in to play once the current one ends, or right away with a quick fade (`now`). Replaces anything
    /// queued before. Main thread only.
    func queue(_ track: LofiTrack, now: Bool) {
        // Take back whatever's queued, so the audio thread can't start the slot while it's rewritten. Only this thread
        // queues, so once that bit is clear the free slot stays free.
        var state = handoff.load(ordering: .acquiring)
        while true {
            let (exchanged, original) = handoff.compareExchange(expected: state, desired: state & 1, ordering: .acquiringAndReleasing)
            if exchanged { break }
            state = original
        }
        let playing = state & 1
        let slot = slots + (1 - playing)
        let count = min(track.events.count, Self.maxEvents)
        track.events.withUnsafeBufferPointer { events in
            if let base = events.baseAddress { slot.pointee.events.update(from: base, count: count) }
        }
        slot.pointee.count = count
        slot.pointee.length = track.length
        slot.pointee.sound = track.sound
        handoff.store(playing | 2 | (now ? 4 : 0), ordering: .releasing)
    }

    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int) {
        let target = self.target
        guard target > 0 || fade > 0 else { // silent: the track stays where it is, but Next can switch right away
            if handoff.load(ordering: .relaxed) & 6 == 6, startQueued() { skipGain = 1 }
            left.update(repeating: 0, count: count)
            right.update(repeating: 0, count: count)
            return
        }
        var done = 0
        while done < count {
            let n = min(count - done, Self.capacity)
            renderChunk(left + done, right + done, n, target: target)
            done += n
        }
        place.store(cursor, ordering: .relaxed)
    }

    /// Starts the queued track, if there is one.
    private func startQueued() -> Bool {
        let state = handoff.load(ordering: .acquiring)
        guard state & 2 != 0 else { return false }
        let slot = 1 - (state & 1)
        guard handoff.compareExchange(expected: state, desired: slot, ordering: .acquiringAndReleasing).exchanged else { return false }
        playing = slot
        cursor = 0
        next = 0
        for index in 0..<Self.voiceCount { voices[index].active = false }
        kick.active = false
        snare.active = false
        hat.active = false
        sound = slots[slot].sound
        kit = sound.kit
        echoDelay = min(max(sound.echo, 1), Self.echoLength - 1)
        masterTone = lowPassFactor(sound.tone)
        snareBodyFall = decayFactor(kit.snareBodyDecay)
        place.store(0, ordering: .relaxed)
        started.wrappingAdd(1, ordering: .releasing)
        return true
    }

    private func renderChunk(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, _ count: Int, target: Float) {
        for index in 0..<6 { (bus + index * Self.capacity).update(repeating: 0, count: count) }
        // Next: once the old track has faded out (or if nothing's audible yet), start the new one.
        if handoff.load(ordering: .relaxed) & 6 == 6, skipGain == 0 || fade == 0 { _ = startQueued() }
        var offset = 0
        while offset < count {
            if cursor >= slots[playing].length { _ = startQueued() }
            let slot = slots[playing]
            while next < slot.count, slot.events[next].time <= cursor {
                trigger(slot.events[next])
                next += 1
            }
            let upcoming = next < slot.count ? slot.events[next].time : slot.length
            let n = min(count - offset, Self.block, cursor < slot.length ? max(1, upcoming - cursor) : Self.block)
            // Tape wobble, the electric piano's auto-pan and the rain's gusts, updated every block.
            let seconds = Float(n) / sampleRate
            wowPhase = wrap(wowPhase + 0.27 * seconds)
            flutterPhase = wrap(flutterPhase + 5.1 * seconds)
            tremoloPhase = wrap(tremoloPhase + 3.6 * seconds)
            gustPhase = wrap(gustPhase + 0.07 * seconds)
            wow = 1 + 0.0018 * sin(twoPi * wowPhase) + 0.0004 * sin(twoPi * flutterPhase)
            tremolo = 0.22 * sin(twoPi * tremoloPhase)
            gust = 1 + 0.3 * sin(twoPi * gustPhase)
            renderVoices(offset, n)
            renderDrums(offset, n)
            if cursor < slot.length { cursor += n }
            offset += n
        }
        mix(left, right, count, target: target, skipping: handoff.load(ordering: .relaxed) & 6 == 6)
    }

    private func trigger(_ event: LofiTrack.Event) {
        switch event.kind {
        case .kick: kick = Drum(velocity: event.velocity, decay: decayFactor(kit.kickDecay))
        case .snare:
            snare = Drum(velocity: event.velocity, decay: decayFactor(kit.snareDecay))
            if kit.snareAttack > 0 { snare.swell = 0; snare.swellStep = 1 / (kit.snareAttack * sampleRate) }
        case .hat, .openHat: hat = Drum(velocity: event.velocity, decay: decayFactor(event.kind == .hat ? kit.hatDecay : kit.openHatDecay))
        default: startVoice(event)
        }
    }

    private func startVoice(_ event: LofiTrack.Event) {
        var slot = 0 // a free voice, else the quietest
        for index in 0..<Self.voiceCount {
            if !voices[index].active { slot = index; break }
            if voices[index].env < voices[slot].env { slot = index }
        }
        var voice = Voice()
        voice.kind = event.kind
        voice.active = true
        voice.velocity = event.velocity
        voice.hold = max(event.length, 1)
        let frequency = 440 * pow(2, Float(event.note - 69) / 12)
        voice.step = frequency / sampleRate
        switch event.kind {
        case .keys:
            voice.shape(attack: 0.004, decay: 1.8, sustain: 0, release: 0.22)
            voice.mod = 0.7 + 1.1 * event.velocity
            voice.modDecay = decayFactor(0.5)
            voice.shimmer = 0.2 * event.velocity
        case .piano:
            voice.shape(attack: 0.003, decay: 2.4, sustain: 0, release: 0.35)
            voice.mod = 0.35 + 0.35 * event.velocity
            voice.modDecay = decayFactor(0.7)
            voice.shimmer = 0.25 * event.velocity
            voice.pan = Float(event.note - 64) / 48
        case .guitar:
            voice.shape(attack: 0.001, decay: 3, sustain: 0, release: 0.08)
            voice.period = max(2, sampleRate / frequency - 0.5)
            voice.damping = exp(-1 / (1.8 * frequency))
            voice.pan = Float(event.note - 60) / 40
            // The pluck: a burst of noise along the string, darker when played softly.
            let string = strings + slot * Self.stringLength
            let soft = 0.2 + 0.5 * event.velocity
            var low: Float = 0
            for i in 0..<Self.stringLength {
                low += soft * (noise(&noiseState) - low)
                string[i] = low
            }
        case .pad:
            voice.shape(attack: 0.7, decay: 1.5, sustain: 0.75, release: 1.2)
            voice.phase2 = 0.33
            voice.phase3 = 0.67
            voice.pan = Float(event.note % 3 - 1) * 0.3
        case .bass: voice.shape(attack: 0.008, decay: 0.45, sustain: 0.4, release: 0.07)
        case .lead, .square: voice.shape(attack: 0.006, decay: 0.25, sustain: 0.6, release: 0.11)
        case .ocarina: voice.shape(attack: 0.04, decay: 0.4, sustain: 0.8, release: 0.15)
        case .bell:
            voice.shape(attack: 0.002, decay: 1.1, sustain: 0, release: 0.45)
            voice.mod = 1.4
            voice.modDecay = decayFactor(0.22)
            voice.pan = 0.3
        case .sax:
            voice.shape(attack: 0.035, decay: 0.6, sustain: 0.75, release: 0.12)
            voice.bend = -0.03 // starts a little flat and slides up
            voice.pan = -0.15
        case .arp:
            voice.shape(attack: 0.002, decay: 0.12, sustain: 0, release: 0.05)
            voice.pan = -0.35
        default: return
        }
        voices[slot] = voice
    }

    private func renderVoices(_ offset: Int, _ count: Int) {
        let left = bus + offset, right = bus + Self.capacity + offset
        let roomSend = bus + Self.capacity * 4 + offset, echoSend = bus + Self.capacity * 5 + offset
        let wow = self.wow, tremolo = self.tremolo
        for index in 0..<Self.voiceCount where voices[index].active {
            var v = voices[index]
            switch v.kind {
            case .keys: // two-operator FM electric piano with a bell-like tine on top
                let gainL = 0.085 * (1 - tremolo), gainR = 0.085 * (1 + tremolo)
                for i in 0..<count {
                    guard v.advance() else { break }
                    let s = sin(twoPi * v.phase + v.mod * sin(twoPi * v.phase)) + v.shimmer * sin(twoPi * v.phase3)
                    let out = s * v.env * v.velocity
                    v.phase = wrap(v.phase + v.step * wow)
                    v.phase3 = wrap(v.phase3 + v.step * wow * 14)
                    v.mod *= v.modDecay
                    v.shimmer *= shimmerFall
                    left[i] += out * gainL
                    right[i] += out * gainR
                    roomSend[i] += out * 0.03
                }
            case .piano: // felt piano: the note, its 2nd and 3rd harmonics fading first, the hammer's soft knock
                let gainL = 0.075 * (1 - v.pan), gainR = 0.075 * (1 + v.pan)
                for i in 0..<count {
                    guard v.advance() else { break }
                    let p = twoPi * v.phase
                    var s = sin(p) + v.mod * sin(2 * p) + v.shimmer * sin(3 * p)
                    if v.age < 400 {
                        v.low += 0.15 * (noise(&noiseState) - v.low)
                        s += v.low * Float(400 - v.age) / 400
                    }
                    let out = s * v.env * v.velocity
                    v.phase = wrap(v.phase + v.step * wow)
                    v.mod *= v.modDecay
                    v.shimmer *= pianoFall
                    left[i] += out * gainL
                    right[i] += out * gainR
                    roomSend[i] += out * 0.04
                }
            case .guitar: // Karplus-Strong: the pluck circles a delay line one period long, softened every trip
                let string = strings + index * Self.stringLength
                let length = Float(Self.stringLength)
                let gain: Float = 0.55
                for i in 0..<count {
                    guard v.advance() else { break }
                    var read = Float(v.write) - v.period / wow
                    if read < 0 { read += length }
                    let i0 = min(Int(read), Self.stringLength - 1)
                    let i1 = i0 + 1 == Self.stringLength ? 0 : i0 + 1
                    let fraction = read - Float(i0)
                    let y = string[i0] + fraction * (string[i1] - string[i0])
                    string[v.write] = (y + v.last) * 0.5 * v.damping
                    v.last = y
                    v.write = v.write + 1 == Self.stringLength ? 0 : v.write + 1
                    v.low += guitarTone * (y - v.low)
                    let out = v.low * v.env * v.velocity * gain
                    left[i] += out * (1 - v.pan)
                    right[i] += out * (1 + v.pan)
                    echoSend[i] += out * 0.15
                    roomSend[i] += out * 0.06
                }
            case .pad: // three detuned saws, smoothed twice
                let gain: Float = 0.03
                for i in 0..<count {
                    guard v.advance() else { break }
                    let dt = v.step * wow
                    var s = 2 * v.phase - 1 - polyBLEP(v.phase, dt)
                    s += 2 * v.phase2 - 1 - polyBLEP(v.phase2, dt * 1.004)
                    s += 2 * v.phase3 - 1 - polyBLEP(v.phase3, dt * 0.996)
                    v.phase = wrap(v.phase + dt)
                    v.phase2 = wrap(v.phase2 + dt * 1.004)
                    v.phase3 = wrap(v.phase3 + dt * 0.996)
                    v.low += padTone * (s - v.low)
                    v.band += padTone * (v.low - v.band)
                    let out = v.band * v.env * v.velocity * gain
                    left[i] += out * (1 - v.pan)
                    right[i] += out * (1 + v.pan)
                    roomSend[i] += out * 0.3
                    echoSend[i] += out * 0.1
                }
            case .bass:
                for i in 0..<count {
                    guard v.advance() else { break }
                    let out = (sin(twoPi * v.phase) + 0.35 * sin(2 * twoPi * v.phase)) * v.env * v.velocity * 0.19
                    v.phase = wrap(v.phase + v.step * wow)
                    left[i] += out
                    right[i] += out
                }
            case .lead, .square, .arp: // band-limited pulse, like the Game Boy's square channels, softened
                let duty: Float = v.kind == .square ? 0.5 : v.kind == .arp ? 0.125 : 0.25
                let gain: Float = v.kind == .square ? 0.07 : v.kind == .arp ? 0.045 : 0.095
                let tone = v.kind == .arp ? arpTone : leadTone
                let vibratoDepth: Float = v.kind == .arp ? 0 : 0.0055
                let echo: Float = v.kind == .arp ? 0.15 : 0.5
                for i in 0..<count {
                    guard v.advance() else { break }
                    let dt = v.step * wow * (1 + v.vibrato(depth: vibratoDepth, rate: 5.2))
                    var y: Float = v.phase < duty ? 1 : -1
                    y += polyBLEP(v.phase, dt)
                    y -= polyBLEP(wrap(v.phase + 1 - duty), dt)
                    y -= 2 * duty - 1
                    v.phase = wrap(v.phase + dt)
                    v.low += tone * (y - v.low)
                    let out = v.low * v.env * v.velocity * gain
                    left[i] += out * (1 - v.pan)
                    right[i] += out * (1 + v.pan)
                    echoSend[i] += out * echo
                    roomSend[i] += out * 0.05
                }
            case .ocarina:
                for i in 0..<count {
                    guard v.advance() else { break }
                    v.phase = wrap(v.phase + v.step * wow * (1 + v.vibrato(depth: 0.006, rate: 4.8)))
                    let breath = noise(&noiseState) * 0.03
                    let out = (sin(twoPi * v.phase) + 0.12 * sin(2 * twoPi * v.phase) + breath) * v.env * v.velocity * 0.13
                    left[i] += out
                    right[i] += out
                    echoSend[i] += out * 0.35
                    roomSend[i] += out * 0.06
                }
            case .bell: // music box: FM with an off-ratio modulator
                for i in 0..<count {
                    guard v.advance() else { break }
                    let out = sin(twoPi * v.phase + v.mod * sin(twoPi * v.phase2)) * v.env * v.velocity * 0.085
                    v.phase = wrap(v.phase + v.step * wow)
                    v.phase2 = wrap(v.phase2 + v.step * wow * 3.5)
                    v.mod *= v.modDecay
                    left[i] += out * (1 - v.pan)
                    right[i] += out * (1 + v.pan)
                    echoSend[i] += out * 0.25
                    roomSend[i] += out * 0.08
                }
            case .sax: // a breathy saw through a filter that opens up as it gets louder, scooping into each note
                for i in 0..<count {
                    guard v.advance() else { break }
                    let dt = v.step * wow * (1 + v.vibrato(depth: 0.007, rate: 5) + v.bend)
                    v.bend *= saxScoop
                    var y = 2 * v.phase - 1 - polyBLEP(v.phase, dt)
                    v.phase = wrap(v.phase + dt)
                    y += noise(&noiseState) * 0.12
                    let f = (500 + 2600 * v.env * v.velocity) * twoPi / sampleRate
                    v.low += f * v.band // state-variable filter
                    v.band += f * (y - v.low - 1.2 * v.band)
                    let out = (v.low + 0.3 * v.band) * v.env * v.velocity * 0.1
                    left[i] += out * (1 - v.pan)
                    right[i] += out * (1 + v.pan)
                    echoSend[i] += out * 0.35
                    roomSend[i] += out * 0.07
                }
            default:
                v.active = false
            }
            voices[index] = v
        }
    }

    private func renderDrums(_ offset: Int, _ count: Int) {
        let left = bus + offset, right = bus + Self.capacity + offset
        let kickOut = bus + Self.capacity * 2 + offset, duck = bus + Self.capacity * 3 + offset
        let roomSend = bus + Self.capacity * 4 + offset
        let kit = self.kit
        var state = noiseState
        defer { noiseState = state }
        if kick.active {
            var k = kick
            for i in 0..<count {
                k.phase = wrap(k.phase + (kit.kickPitch + kit.kickSweep * k.pitch) / sampleRate) // a thump that drops in pitch
                k.pitch *= kickSweep
                // The Game Boy's is a triangle wave (starting at zero, so no click).
                let body = kit.chip ? 4 * abs(wrap(k.phase + 0.75) - 0.5) - 1 : sin(twoPi * k.phase)
                let s = body * k.env + noise(&state) * k.click * kit.kickClick
                k.click *= kickClick
                kickOut[i] += s * k.velocity * kit.kickLevel
                duck[i] = max(duck[i], k.env * k.velocity)
                k.env *= k.decay
                if k.env < 0.0003 { k.active = false; break }
            }
            kick = k
        }
        if snare.active {
            var s = snare
            let step = kit.snarePitch / sampleRate
            for i in 0..<count {
                let n = kit.chip ? s.held(&state, every: 6) : noise(&state)
                s.low += kit.snareColor * (n - s.low)
                let body = sin(twoPi * s.phase) * s.pitch
                s.phase = wrap(s.phase + step)
                s.pitch *= snareBodyFall
                s.swell = min(1, s.swell + s.swellStep)
                let out = (body * kit.snareBody + (n - s.low) * s.env * kit.snareNoise) * s.velocity * kit.snareLevel * s.swell
                left[i] += out * 0.95
                right[i] += out * 1.05
                roomSend[i] += out * 0.25
                s.env *= s.decay
                if s.env < 0.0003 { s.active = false; break }
            }
            snare = s
        }
        if hat.active {
            var h = hat
            for i in 0..<count {
                let n = kit.chip ? h.held(&state, every: 2) : noise(&state)
                h.low += kit.hatColor * (n - h.low)
                var s = (n - h.low) * (1 - kit.metal)
                if kit.metal > 0 { // two square waves at odd ratios, multiplied: a ride's clang
                    h.phase = wrap(h.phase + 3150 / sampleRate)
                    h.phase2 = wrap(h.phase2 + 4690 / sampleRate)
                    s += kit.metal * 0.35 * ((h.phase < 0.5) == (h.phase2 < 0.5) ? 1 : -1)
                }
                let out = s * h.env * h.velocity * kit.hatLevel
                left[i] += out * 0.8
                right[i] += out * 1.2
                h.env *= h.decay
                if h.env < 0.0003 { h.active = false; break }
            }
            hat = h
        }
    }

    /// Echo, room, the kick's pump, the weather, the dark lo-fi tone, vinyl, a soft clip, then the fades.
    private func mix(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, _ count: Int, target: Float, skipping: Bool) {
        let busL = bus, busR = bus + Self.capacity, kickBus = bus + Self.capacity * 2, duck = bus + Self.capacity * 3
        let roomSend = bus + Self.capacity * 4, echoSend = bus + Self.capacity * 5
        let on = target > 0
        let fadeStep = on ? 1 / (Self.fadeIn * sampleRate) : -1 / (Self.fadeOut * sampleRate)
        let skipStep = skipping ? -1 / (Self.skipOut * sampleRate) : 1 / (Self.skipIn * sampleRate)
        let rainTarget = sound.rain, cafeTarget = sound.cafe, vinyl = sound.vinyl
        var state = noiseState, echoIndex = self.echoIndex, echoTone = self.echoTone, fade = self.fade, volume = self.volume
        var toneL1 = self.toneL1, toneL2 = self.toneL2, toneR1 = self.toneR1, toneR2 = self.toneR2
        var hiss = self.hiss, crackle = self.crackle, crackleTone = self.crackleTone, skipGain = self.skipGain
        var rain = self.rain, cafe = self.cafe
        let tone = masterTone, delay = echoDelay
        for i in 0..<count {
            // Weather, gliding to this track's.
            rain += (rainTarget - rain) * 0.00002
            cafe += (cafeTarget - cafe) * 0.00002
            var weatherL: Float = 0, weatherR: Float = 0, chatter: Float = 0
            if rain > 0.0005 {
                let (l, r) = rainSample(&state)
                weatherL += l * rain
                weatherR += r * rain
            }
            if cafe > 0.0005 {
                let (l, r) = cafeSample(&state)
                weatherL += l * cafe
                weatherR += r * cafe
                chatter = (l + r) * cafe
            }
            // Tape echo bouncing left and right, darker each time.
            let read = (echoIndex - delay + Self.echoLength) % Self.echoLength
            let echoedL = echoL[read], echoedR = echoR[read]
            echoTone += 0.3 * (echoedR - echoTone)
            echoL[echoIndex] = echoSend[i] + echoTone * 0.4
            echoR[echoIndex] = echoedL * 0.4
            echoIndex = echoIndex + 1 == Self.echoLength ? 0 : echoIndex + 1
            let (roomL, roomR) = room.process(roomSend[i] + (echoedL + echoedR) * 0.1 + chatter * 0.5)
            let pump = 1 - 0.22 * duck[i]
            var l = (busL[i] + echoedL * 0.3) * pump + roomL + kickBus[i] + weatherL
            var r = (busR[i] + echoedR * 0.3) * pump + roomR + kickBus[i] + weatherR
            toneL1 += tone * (l - toneL1)
            toneL2 += tone * (toneL1 - toneL2)
            toneR1 += tone * (r - toneR1)
            toneR2 += tone * (toneR1 - toneR2)
            // Vinyl: a soft hiss and the odd crackle.
            hiss += 0.25 * (noise(&state) - hiss)
            if noise(&state) > 1 - 0.0008 * vinyl { crackle = noise(&state) * 0.12 * vinyl }
            crackle *= 0.6
            crackleTone += 0.5 * (crackle - crackleTone)
            l = tanh((toneL2 + hiss * 0.006 * vinyl + crackleTone) * 1.3) / 1.3
            r = tanh((toneR2 + hiss * 0.005 * vinyl + crackleTone * 0.85) * 1.3) / 1.3
            fade = min(max(fade + fadeStep, 0), 1)
            skipGain = min(max(skipGain + skipStep, 0), 1)
            if on { volume += (target - volume) * 0.0005 }
            let gain = volume * fade * fade * skipGain
            left[i] = l * gain
            right[i] = r * gain
        }
        noiseState = state
        self.echoIndex = echoIndex
        self.echoTone = echoTone
        self.fade = fade
        self.volume = volume
        self.skipGain = skipGain
        self.toneL1 = toneL1
        self.toneL2 = toneL2
        self.toneR1 = toneR1
        self.toneR2 = toneR2
        self.hiss = hiss
        self.crackle = crackle
        self.crackleTone = crackleTone
        self.rain = rain
        self.cafe = cafe
    }

    /// Rain on the window: a soft roar that swells with the wind, and the odd closer drop.
    private func rainSample(_ state: inout UInt32) -> (Float, Float) {
        let a = noise(&state), b = noise(&state)
        rainL1 += 0.6 * (a - rainL1)
        rainL2 += 0.06 * (rainL1 - rainL2)
        rainR1 += 0.6 * (b - rainR1)
        rainR2 += 0.06 * (rainR1 - rainR2)
        if noise(&state) > 0.9994 {
            drop = 0.3 + 0.7 * abs(noise(&state))
            dropPan = noise(&state) * 0.8
        }
        drop *= dropFall
        dropTone += 0.5 * (noise(&state) * drop - dropTone)
        let roar = 0.1 * gust
        return ((rainL1 - rainL2) * roar + dropTone * (1 - dropPan) * 0.08,
                (rainR1 - rainR2) * roar + dropTone * (1 + dropPan) * 0.08)
    }

    /// A café: three far-off voices, and now and then a cup.
    private func cafeSample(_ state: inout UInt32) -> (Float, Float) {
        var l: Float = 0, r: Float = 0
        for index in 0..<3 {
            let voice = talkers[index].speak(&state)
            l += voice * (1 - talkers[index].pan)
            r += voice * (1 + talkers[index].pan)
        }
        if noise(&state) > 0.999995 { clink = Clink(pitch: 2300 + 1500 * abs(noise(&state)), pan: noise(&state) * 0.7) }
        if clink.level > 0.0005 {
            let ring = sin(twoPi * clink.phase + 1.5 * clink.level * sin(twoPi * clink.phase * 2.76)) * clink.level * 0.06
            clink.phase = wrap(clink.phase + clink.step)
            clink.level *= clinkFall
            l += ring * (1 - clink.pan)
            r += ring * (1 + clink.pan)
        }
        return (l * 0.02, r * 0.02)
    }
}

private struct Voice {
    var kind: LofiTrack.Kind = .keys
    var active = false
    /// Cycles per sample at the note's pitch.
    var step: Float = 0
    var phase: Float = 0, phase2: Float = 0, phase3: Float = 0
    var age = 0, hold = 0, attack = 1
    var env: Float = 0, sustain: Float = 0, decay: Float = 0, release: Float = 0
    /// FM depth (electric piano, music box) or the piano's 2nd harmonic, and how fast it mellows.
    var mod: Float = 0, modDecay: Float = 1
    /// The electric piano's tine, or the piano's 3rd harmonic.
    var shimmer: Float = 0
    var velocity: Float = 0
    /// Filter memory.
    var low: Float = 0, band: Float = 0
    var pan: Float = 0
    /// The sax's scoop: how far flat it still is.
    var bend: Float = 0
    /// Guitar string: one trip's length in samples, how much each trip keeps, where it writes next, the last sample.
    var period: Float = 0, damping: Float = 0, write = 0, last: Float = 0

    mutating func shape(attack: Float, decay: Float, sustain: Float, release: Float) {
        self.attack = max(1, Int(attack * sampleRate))
        self.decay = decayFactor(decay)
        self.sustain = sustain
        self.release = decayFactor(release)
    }

    /// One sample of the envelope; false once the note has died away.
    mutating func advance() -> Bool {
        age += 1
        if age <= attack {
            env = Float(age) / Float(attack)
        } else if age < hold {
            env = sustain + (env - sustain) * decay
        } else {
            env *= release
        }
        if env < 0.0003, age > attack, age >= hold || sustain == 0 { active = false }
        return active
    }

    /// Pitch wobble that eases in after the note starts, like a singer's.
    func vibrato(depth: Float, rate: Float) -> Float {
        guard depth > 0 else { return 0 }
        let ease = min(1, max(0, Float(age) - 0.18 * sampleRate) / (0.35 * sampleRate))
        return depth * ease * sin(twoPi * rate * Float(age) / sampleRate)
    }
}

private struct Drum {
    var active = false
    var velocity: Float = 0
    var env: Float = 0
    var decay: Float = 0
    var phase: Float = 0, phase2: Float = 0
    /// The kick's pitch drop, or the snare's body.
    var pitch: Float = 0
    var click: Float = 0
    var low: Float = 0
    /// Brushes swish in: how far in, and how much more each sample.
    var swell: Float = 1, swellStep: Float = 0
    /// The Game Boy noise: the value it's holding, for how many more samples.
    var holding: Float = 0, holdLeft = 0

    init() {}

    init(velocity: Float, decay: Float) {
        active = true
        self.velocity = velocity
        env = 1
        self.decay = decay
        pitch = 1
        click = 1
    }

    /// Noise that only changes every few samples.
    mutating func held(_ state: inout UInt32, every samples: Int) -> Float {
        if holdLeft <= 0 {
            holding = noise(&state)
            holdLeft = samples
        }
        holdLeft -= 1
        return holding
    }
}

/// A far-off voice in a café: a buzz at speaking pitch through two vowel filters that hop every syllable.
private struct Talker {
    /// Hertz, and where it sits left to right.
    let voice: Float, pan: Float
    var phase: Float = 0, pitch: Float, level: Float = 0, loudness: Float = 0
    var formant1: Float = 0.06, formant2: Float = 0.2, target1: Float = 0.06, target2: Float = 0.2, pitchTarget: Float
    var syllableLeft = 0
    var low1: Float = 0, band1: Float = 0, low2: Float = 0, band2: Float = 0

    init(voice: Float, pan: Float) {
        self.voice = voice
        self.pan = pan
        pitch = voice
        pitchTarget = voice
    }

    mutating func speak(_ state: inout UInt32) -> Float {
        syllableLeft -= 1
        if syllableLeft <= 0 { // the next syllable, or a pause
            syllableLeft = Int((0.08 + 0.14 * abs(noise(&state))) * sampleRate)
            loudness = noise(&state) > -0.4 ? 0.5 + 0.5 * abs(noise(&state)) : 0
            target1 = (320 + 450 * abs(noise(&state))) * twoPi / sampleRate
            target2 = (950 + 1300 * abs(noise(&state))) * twoPi / sampleRate
            pitchTarget = voice * (1 + 0.15 * noise(&state))
        }
        level += 0.0015 * (loudness - level)
        formant1 += 0.002 * (target1 - formant1)
        formant2 += 0.002 * (target2 - formant2)
        pitch += 0.001 * (pitchTarget - pitch)
        phase = wrap(phase + pitch / sampleRate)
        let buzz: Float = phase < 0.12 ? 1 : -0.136 // a narrow pulse with no DC
        low1 += formant1 * band1
        band1 += formant1 * (buzz - low1 - 0.25 * band1)
        low2 += formant2 * band2
        band2 += formant2 * (buzz - low2 - 0.3 * band2)
        return (band1 + 0.5 * band2) * level
    }
}

/// A spoon on a cup.
private struct Clink {
    var phase: Float = 0, step: Float = 0, level: Float = 0, pan: Float = 0

    init() {}

    init(pitch: Float, pan: Float) {
        step = pitch / sampleRate
        level = 1
        self.pan = pan
    }
}

/// A small Freeverb-style room: four combs and two allpasses a side.
private final class Reverb {
    private static let lengths = [1116, 1188, 1277, 1356, 1139, 1211, 1300, 1379, 556, 441, 579, 464]
    private let lines = UnsafeMutablePointer<DelayLine>.allocate(capacity: Reverb.lengths.count)

    init() {
        for (index, length) in Self.lengths.enumerated() { (lines + index).initialize(to: DelayLine(length)) }
    }

    deinit {
        for index in Self.lengths.indices { lines[index].buffer.deallocate() }
        lines.deallocate()
    }

    func process(_ input: Float) -> (Float, Float) {
        let x = input * 0.2
        var l: Float = 0, r: Float = 0
        for index in 0..<4 { l += lines[index].comb(x) }
        for index in 4..<8 { r += lines[index].comb(x) }
        l = lines[9].allpass(lines[8].allpass(l))
        r = lines[11].allpass(lines[10].allpass(r))
        return (l * 0.5, r * 0.5)
    }
}

private struct DelayLine {
    let buffer: UnsafeMutablePointer<Float>
    let length: Int
    var index = 0
    var damped: Float = 0

    init(_ length: Int) {
        self.length = length
        buffer = .allocate(capacity: length)
        buffer.initialize(repeating: 0, count: length)
    }

    mutating func comb(_ input: Float) -> Float {
        let out = buffer[index]
        damped = out * 0.7 + damped * 0.3
        buffer[index] = input + damped * 0.8
        index = index + 1 == length ? 0 : index + 1
        return out
    }

    mutating func allpass(_ input: Float) -> Float {
        let delayed = buffer[index]
        buffer[index] = input + delayed * 0.5
        index = index + 1 == length ? 0 : index + 1
        return delayed - input
    }
}
