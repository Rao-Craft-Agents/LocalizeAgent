//  WHAT: The calls whose literal argument SwiftUI and Foundation read as a localized key, and what each shows.
//  PIN:  ONLY WHAT TAKES A KEY. Each entry is an initializer or modifier whose first (or named) parameter is a
//        `LocalizedStringKey`, `LocalizedStringResource` or `String.LocalizationValue`: a literal there is looked up
//        at run time. A call that takes a `String` shows its argument as it is, so nothing of it is harvested.

import Foundation

enum LocalizableCalls {
    /// Types whose initializer takes a key as its first, unnamed argument.
    static let initializers: [String: String] = [
        "Text": "text", "Label": "a label", "Button": "a button", "Toggle": "a switch", "Section": "a section header",
        "TextField": "a text field's placeholder", "SecureField": "a password field's placeholder", "Picker": "a picker's title",
        "Menu": "a menu", "Link": "a link", "NavigationLink": "a link to another screen", "Stepper": "a stepper's label",
        "DatePicker": "a date picker's label", "ColorPicker": "a colour picker's label", "ProgressView": "a progress message",
        "LabeledContent": "a label", "GroupBox": "a group's title", "DisclosureGroup": "a disclosure group's title",
        "ContentUnavailableView": "an empty state's title", "ShareLink": "a share button", "Tab": "a tab",
        "ControlGroup": "a control group's title", "TableColumn": "a table column's title", "CommandMenu": "a menu bar menu",
        "Window": "a window's title", "WindowGroup": "a window's title", "MenuBarExtra": "a menu bar item",
        "LocalizedStringKey": "text", "LocalizedStringResource": "text", "LocalizationValue": "text", "Gauge": "a gauge's label",
        "Slider": "a slider's label", "Alert": "an alert's title", "PhotosPicker": "a photo picker's label",
    ]

    /// Modifiers whose first, unnamed argument is a key.
    static let modifiers: [String: String] = [
        "navigationTitle": "a screen title", "navigationSubtitle": "a screen subtitle", "help": "a tooltip",
        "alert": "an alert's title", "confirmationDialog": "a confirmation dialog's title",
        "accessibilityLabel": "an accessibility label read aloud", "accessibilityHint": "an accessibility hint read aloud",
        "accessibilityValue": "an accessibility value read aloud", "badge": "a badge",
        "accessibilityAction": "an accessibility action's name",
    ]

    /// Calls with a named argument that is a key.
    static let named: [String: [String: String]] = [
        "String": ["localized": "text"],
        "AttributedString": ["localized": "text"],
        "LocalizedStringKey": ["stringLiteral": "text"],
        "LocalizationValue": ["stringLiteral": "text"],
        "searchable": ["prompt": "a search field's placeholder"],
        "Slider": ["label": "a slider's label"],
    ]

    /// Named arguments that carry another source text for the same key.
    static let valueLabels: Set<String> = ["defaultValue", "value"]

    /// What a parameter of the project's own is: `GraniteAlertAction's title`, `the text of Banner`.
    static func role(forLabel label: String, callee: String) -> String {
        label.isEmpty || label == "_" ? "the text of \(callee)" : "\(callee)'s \(label)"
    }
}
