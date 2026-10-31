import SwiftUI

/// A lo-fi station: one mood, and 120 tracks written out in code from the station and the track number. Six stations of
/// about five hours each make the 30 hours.
enum Station: String, CaseIterable, Identifiable {
    case chill, study, rainy, cafe, night, gameBoy

    static let trackCount = 120

    var id: String { rawValue }

    var name: String {
        switch self {
        case .chill: "Chill"
        case .study: "Study"
        case .rainy: "Rainy"
        case .cafe: "Café"
        case .night: "Night"
        case .gameBoy: "Game Boy"
        }
    }

    /// One line on what it sounds like (the station button's tooltip).
    var blurb: String {
        switch self {
        case .chill: "Warm keys, lazy beats, a tune you can hum"
        case .study: "Soft piano, quiet drums, nothing that grabs you"
        case .rainy: "Minor keys and guitar with rain on the window"
        case .cafe: "Jazzy guitar and sax over a busy café"
        case .night: "Slow, dark and dreamy, for late hours"
        case .gameBoy: "Bright handheld-RPG tunes on chip sounds"
        }
    }

    var symbol: String {
        switch self {
        case .chill: "sun.haze.fill"
        case .study: "book.fill"
        case .rainy: "cloud.rain.fill"
        case .cafe: "cup.and.saucer.fill"
        case .night: "moon.stars.fill"
        case .gameBoy: "gamecontroller.fill"
        }
    }

    /// The cover's two colors, light to dark.
    var colors: (Color, Color) {
        switch self {
        case .chill: (Color(red: 1.0, green: 0.72, blue: 0.45), Color(red: 0.93, green: 0.42, blue: 0.42))
        case .study: (Color(red: 0.55, green: 0.82, blue: 0.68), Color(red: 0.22, green: 0.55, blue: 0.52))
        case .rainy: (Color(red: 0.55, green: 0.70, blue: 0.92), Color(red: 0.26, green: 0.36, blue: 0.62))
        case .cafe: (Color(red: 0.86, green: 0.66, blue: 0.48), Color(red: 0.50, green: 0.33, blue: 0.24))
        case .night: (Color(red: 0.50, green: 0.42, blue: 0.85), Color(red: 0.16, green: 0.14, blue: 0.38))
        case .gameBoy: (Color(red: 0.62, green: 0.74, blue: 0.30), Color(red: 0.24, green: 0.40, blue: 0.22))
        }
    }

    /// Different for every station, so track 7 of Rainy isn't track 7 of Chill.
    var seed: UInt64 {
        switch self {
        case .chill: 0xC411_0F_10F1
        case .study: 0x57D7_0F_10F1
        case .rainy: 0x4A1D_0F_10F1
        case .cafe: 0xCAFE_0F_10F1
        case .night: 0x1167_0F_10F1
        case .gameBoy: 0x51CE_0F_10F1
        }
    }

    /// A made-up name for each track, all different within a station: two word lists of 12 make 144 pairs, and
    /// stepping through them 29 at a time (29 shares no factor with 144) visits each pair once.
    func title(_ number: Int) -> String {
        let (first, second) = words
        let pair = (number * 29 + rawValue.count * 7) % (first.count * second.count)
        return "\(first[pair / second.count]) \(second[pair % second.count])"
    }

    private var words: ([String], [String]) {
        switch self {
        case .chill:
            (["lazy", "golden", "soft", "slow", "warm", "hazy", "easy", "sunny", "mellow", "faded", "sleepy", "honey"],
             ["afternoon", "balcony", "polaroids", "breeze", "lemonade", "hammock", "sundays", "skyline", "rooftop",
              "postcards", "daydream", "porch"])
        case .study:
            (["quiet", "paper", "steady", "late", "pencil", "library", "gentle", "indoor", "patient", "tidy", "lamp-lit",
              "careful"],
             ["notes", "pages", "chapters", "flashcards", "margins", "drafts", "tea", "highlights", "outlines",
              "bookmarks", "desks", "sketches"])
        case .rainy:
            (["grey", "wet", "foggy", "cloudy", "drizzle", "puddle", "misty", "damp", "stormy", "window", "umbrella",
              "raincoat"],
             ["streets", "glass", "bus stop", "evening", "sidewalk", "tin roof", "letters", "reflections", "tram",
              "gutters", "lanterns", "morning"])
        case .cafe:
            (["espresso", "latte", "corner", "morning", "vanilla", "cinnamon", "oat milk", "booth", "window", "sugar",
              "mocha", "terrace"],
             ["talk", "steam", "receipts", "regulars", "crema", "napkins", "jazz", "chatter", "spoons", "tables",
              "refills", "pastries"])
        case .night:
            (["midnight", "neon", "starlit", "silver", "moonlit", "after hours", "violet", "sleepless", "velvet",
              "late", "dim", "last train"],
             ["drive", "city", "window", "radio", "satellites", "streetlights", "skyline", "static", "owls", "motel",
              "freeway", "dreams"])
        case .gameBoy:
            (["pixel", "route", "berry", "cartridge", "8-bit", "starter", "potion", "save point", "overworld",
              "sprite", "handheld", "bonus"],
             ["town", "meadow", "forest", "cave", "harbor", "garden", "inn", "bridge", "village", "map", "quest",
              "shop"])
        }
    }
}
