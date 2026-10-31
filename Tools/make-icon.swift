// Draws the app icon: a cassette on a sunset squircle, with the menu bar strip the other menu bar apps' icons have.
// Run: swift Tools/make-icon.swift <out.png>   (then sips it down to the other sizes)
import AppKit
import SwiftUI

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.68, blue: 0.48), Color(red: 0.86, green: 0.42, blue: 0.50),
                                              Color(red: 0.40, green: 0.27, blue: 0.62)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .top) {
                    // The menu bar, with the app's headphones in it.
                    ZStack {
                        Rectangle().fill(.white.opacity(0.16))
                        HStack(spacing: 22) {
                            Capsule().fill(.white.opacity(0.45)).frame(width: 70, height: 16)
                            Capsule().fill(.white.opacity(0.45)).frame(width: 110, height: 16)
                            Spacer()
                            Image(systemName: "headphones").font(.system(size: 60, weight: .heavy)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 150)
                    }
                    .frame(height: 104)
                }
                .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
                .frame(width: 824, height: 824)
            Cassette()
                .shadow(color: .black.opacity(0.35), radius: 30, y: 18)
                .offset(y: 48)
        }
        .frame(width: 1024, height: 1024)
    }
}

struct Cassette: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 44, style: .continuous)
            .fill(Color(red: 0.99, green: 0.95, blue: 0.88))
            .frame(width: 600, height: 390)
            .overlay(alignment: .top) {
                // The label: a stripe and the tape window.
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.93, green: 0.48, blue: 0.45)).frame(height: 30)
                    RoundedRectangle(cornerRadius: 46, style: .continuous)
                        .fill(Color(red: 0.17, green: 0.15, blue: 0.24))
                        .frame(height: 150)
                        .overlay {
                            HStack(spacing: 150) { Reel(); Reel() }
                        }
                        .padding(.top, 34)
                }
                .padding(.horizontal, 70)
                .padding(.top, 46)
            }
            .overlay(alignment: .bottom) {
                // The bottom edge where the tape shows.
                Trapezoid()
                    .fill(Color(red: 0.90, green: 0.83, blue: 0.74))
                    .frame(width: 380, height: 70)
            }
    }
}

struct Reel: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.99, green: 0.95, blue: 0.88)).frame(width: 96)
            ForEach(0..<6) { tooth in
                Rectangle().fill(Color(red: 0.17, green: 0.15, blue: 0.24)).frame(width: 12, height: 18)
                    .offset(y: -30).rotationEffect(.degrees(Double(tooth) * 60))
            }
            Circle().fill(Color(red: 0.17, green: 0.15, blue: 0.24)).frame(width: 26)
        }
    }
}

struct Trapezoid: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX + 40, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - 40, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("couldn't render") }
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
