import SwiftUI

/// The panel under the menu bar icon: what's on, the controls, the stations, the sleep timer.
struct PanelView: View {
    @Bindable var radio: Radio

    var body: some View {
        VStack(spacing: 16) {
            if let update = radio.updates.available {
                UpdateBanner(updates: radio.updates, update: update)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            NowPlaying(radio: radio)
            Transport(radio: radio)
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                Slider(value: $radio.volume, in: 0...1)
                    .controlSize(.small)
                    .accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            FocusCard(radio: radio)
            StationGrid(radio: radio)
            Footer(radio: radio)
        }
        .padding(16)
        .frame(width: 300)
    }
}

/// A station's cover: its colors and symbol. Also the Now Playing artwork.
struct Cover: View {
    let station: Station
    var size: CGFloat = 56
    var playing = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [station.colors.0, station.colors.1], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: station.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .symbolEffect(.breathe, isActive: playing)
            }
            .frame(width: size, height: size)
    }
}

private struct NowPlaying: View {
    let radio: Radio

    var body: some View {
        HStack(spacing: 12) {
            Cover(station: radio.station, playing: radio.isPlaying)
                .shadow(color: radio.station.colors.1.opacity(0.35), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(radio.track.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(radio.station.name) · \(radio.track.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressBar(radio: radio)
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProgressBar: View {
    let radio: Radio

    var body: some View {
        let duration = radio.track.duration
        VStack(spacing: 3) {
            Capsule()
                .fill(.primary.opacity(0.1))
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(radio.station.colors.1)
                            .frame(width: geometry.size.width * min(radio.elapsed / duration, 1))
                    }
                }
                .frame(height: 4)
            HStack {
                Text(Self.time(radio.elapsed))
                Spacer()
                Text(Self.time(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.time(radio.elapsed)) of \(Self.time(duration))")
    }

    static func time(_ seconds: Double) -> String { Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)) }
}

private struct Transport: View {
    let radio: Radio

    var body: some View {
        HStack(spacing: 30) {
            Button(action: radio.previous) {
                Image(systemName: "backward.fill").font(.title3).frame(width: 36, height: 36)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .help("Previous")
            .accessibilityLabel("Previous track")
            Button(action: radio.togglePlay) {
                Image(systemName: radio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.primary.opacity(0.08)))
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(radio.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(radio.isPlaying ? "Pause" : "Play")
            Button(action: radio.next) {
                Image(systemName: "forward.fill").font(.title3).frame(width: 36, height: 36)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .help("Next")
            .accessibilityLabel("Next track")
        }
        .buttonStyle(PressStyle())
        .frame(maxWidth: .infinity)
    }
}

/// Plain, with a soft highlight on hover and a little give when pressed.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pressable(configuration: configuration)
    }

    private struct Pressable: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .contentShape(Circle())
                .background(Circle().fill(.primary.opacity(hovering ? 0.06 : 0)))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

/// The focus timer: pick a length and the music plays; when it's up the music stops and a chime rings.
private struct FocusCard: View {
    let radio: Radio

    private var active: Bool { radio.focusEnd != nil || radio.focusLeft != nil }

    var body: some View {
        HStack(spacing: 12) {
            FocusRing(radio: radio)
                .frame(width: 46, height: 46)
            if active {
                VStack(alignment: .leading, spacing: 1) {
                    Text(radio.focusEnd == nil ? "Paused" : "Focusing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Group {
                        if let end = radio.focusEnd {
                            let now = Date.now
                            Text(timerInterval: min(now, end)...end, countsDown: true)
                        } else {
                            Text(Duration.seconds(radio.focusLeft ?? 0).formatted(.time(pattern: .minuteSecond)))
                        }
                    }
                    .font(.title2.monospacedDigit().weight(.semibold))
                }
                Spacer()
                Button("Stop", action: radio.stopFocus)
                    .buttonStyle(.plain)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.primary.opacity(0.07)))
                    .help("Stop the timer (the music keeps playing)")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Focus")
                            .font(.callout.weight(.semibold))
                        Text(radio.focusDone == 0 ? "music, then a chime" : "\(radio.focusDone) done today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        ForEach([15, 25, 45, 60], id: \.self) { minutes in
                            MinutesButton(minutes: minutes, color: radio.station.colors.1) { radio.startFocus(minutes: Double(minutes)) }
                        }
                        Text("min")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.primary.opacity(0.05)))
        .animation(.easeOut(duration: 0.2), value: active)
    }
}

private struct MinutesButton: View {
    let minutes: Int
    let color: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("\(minutes)")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(hovering ? .white : .primary)
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? AnyShapeStyle(color) : AnyShapeStyle(.primary.opacity(0.07))))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Focus for \(minutes) minutes")
        .accessibilityLabel("Focus for \(minutes) minutes")
    }
}

/// How much of the focus time has gone, as a ring in the station's colors.
private struct FocusRing: View {
    let radio: Radio

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let (light, dark) = radio.station.colors
            ZStack {
                Circle().stroke(.primary.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress(at: context.date))
                    .stroke(AngularGradient(colors: [light, dark, light], center: .center), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress(at: context.date))
                Image(systemName: radio.focusEnd != nil ? "leaf.fill" : "timer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(light.mix(with: dark, by: 0.45))
                    .symbolEffect(.breathe, isActive: radio.focusEnd != nil)
            }
        }
        .accessibilityHidden(true)
    }

    private func progress(at date: Date) -> Double {
        guard radio.focusLength > 0 else { return 0 }
        let left = radio.focusEnd.map { $0.timeIntervalSince(date) } ?? radio.focusLeft ?? radio.focusLength
        return min(max(1 - left / radio.focusLength, 0), 1)
    }
}

private struct StationGrid: View {
    let radio: Radio

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Station.allCases) { station in
                StationButton(station: station, selected: radio.station == station) { radio.select(station) }
            }
        }
    }
}

private struct StationButton: View {
    let station: Station
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: station.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? .white : colorScheme == .dark ? station.colors.0 : station.colors.1)
                Text(station.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(selected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? AnyShapeStyle(LinearGradient(colors: [station.colors.0.mix(with: station.colors.1, by: 0.4), station.colors.1],
                                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(.primary.opacity(hovering ? 0.1 : 0.05)))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(station.blurb)
        .accessibilityLabel("\(station.name) station")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct Footer: View {
    let radio: Radio

    var body: some View {
        HStack {
            Menu {
                Button("Off") { radio.sleep(minutes: nil) }
                Divider()
                ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button("\(minutes) minutes") { radio.sleep(minutes: Double(minutes)) }
                }
            } label: {
                if let end = radio.sleepEnd {
                    let now = Date.now
                    Label { Text(timerInterval: min(now, end)...end, countsDown: true) } icon: { Image(systemName: "moon.zzz.fill") }
                } else {
                    Label("Sleep timer", systemImage: "moon.zzz")
                }
            }
            .help("Stop playing after a while")
            Spacer()
            Menu {
                Toggle("Start at Login", isOn: Binding(get: { radio.startsAtLogin }, set: { radio.setStartsAtLogin($0) }))
                Button("Support on Ko-fi…") { NSWorkspace.shared.open(URL(string: "https://ko-fi.com/kian")!) }
                Divider()
                Button("Quit Menu Bar Lofi") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
