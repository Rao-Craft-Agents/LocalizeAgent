//  WHAT: The `localized()` helper an app may call on a key it holds as a `String`, written when `helper` is true:
//        `"Delete".localized()` reads the key `Delete`; `"Signed in as".localized(name, formatted: true)` reads
//        `Signed in as %@` and puts `name` in its place. The harvest reads both forms, so their keys are translated.
//  PIN:  FORMATTED ONLY WHEN ASKED. A text read plainly is never passed through `String(format:)`, where a `%` in a
//        translation would read as a specifier.

import Foundation

enum LocalizedHelper {
    static let text = #"""
    import Foundation

    extension String {
        /// The text this key stands for in the person's language, from the app's `Localizable` strings. With `formatted`,
        /// the key is read with ` %@` after it and `value` takes the `%@`'s place:
        /// `"Signed in as".localized(name, formatted: true)` reads the key `Signed in as %@`.
        func localized(_ value: String = "", formatted: Bool = false) -> String {
            guard formatted else { return NSLocalizedString(self, comment: "") }
            return String(format: NSLocalizedString(self + " %@", comment: ""), value)
        }
    }

    """#
}
