import AVFoundation

/// The end-of-focus chime: four soft bell notes rising up a major chord, ringing out together.
enum Chime {
    static let length = 4.5

    static func buffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(length * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        let notes: [(note: Double, start: Double, pan: Double)] = [(76, 0, -0.3), (79, 0.32, 0.25), (84, 0.64, -0.1), (88, 1.05, 0.3)]
        for frame in 0..<Int(frames) {
            let t = Double(frame) / rate
            var left = 0.0, right = 0.0
            for bell in notes where t >= bell.start {
                let age = t - bell.start
                let frequency = 440 * pow(2, (bell.note - 69) / 12)
                // A sine with a quickly fading off-ratio shimmer (FM), like a struck bowl.
                let shimmer = 1.1 * exp(-age / 0.18)
                let tone = sin(2 * .pi * frequency * age + shimmer * sin(2 * .pi * frequency * 2.76 * age))
                let level = min(age / 0.006, 1) * exp(-age / 1.4) * 0.16
                left += tone * level * (1 - bell.pan)
                right += tone * level * (1 + bell.pan)
            }
            let fadeOut = min((length - t) / 0.5, 1) // no click at the very end
            channels[0][frame] = Float(left * fadeOut)
            if format.channelCount > 1 { channels[1][frame] = Float(right * fadeOut) }
        }
        return buffer
    }
}
