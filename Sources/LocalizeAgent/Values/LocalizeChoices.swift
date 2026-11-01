import Foundation

/// Where an app's strings are kept.
public enum LocalizeFormat: String, Codable, Sendable, CaseIterable {
    /// One `Localizable.strings` a language, each in its `<lang>.lproj` folder: the default.
    case strings
    /// One String Catalog, `Localizable.xcstrings`, holding every language.
    case catalog
}
