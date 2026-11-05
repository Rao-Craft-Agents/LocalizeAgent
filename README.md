# LocalizeAgent

Translate an app from its own Swift, and keep its languages in step as the code changes. Name the languages and
`localize` finds every string the app shows, writes the source language, has Craft's model translate it, checks every
translation, and adds the languages to the Xcode project. Call it again after adding screens, and only what is new or
changed is translated.

## What you can ask

```
$localize the recipe app into French, German, Japanese and Arabic
$localize the recipe app into Loom's 28 languages
$localize Spanish and Brazilian Portuguese, as a String Catalog
$localize the new screens into every language the app has
```

Craft's model writes the call (`{"languages": ["fr", "de", "ja", "ar"]}` for the first); it shows on Craft's agent map,
and the tables and project file it names are built with the turn.

## What you get

- **Every string the app shows, found for you.** The text of SwiftUI's views and modifiers, `String(localized:)`,
  `NSLocalizedString` and the app's own `LocalizedStringKey` properties, each interpolation turned into the format
  specifier the runtime asks for.
- **Translations in each language.** One `Localizable.strings` a language, or one String Catalog
  (`Localizable.xcstrings`), whichever the project uses, sorted and with each string's comment kept.
- **Languages added to the project.** Each language in the Xcode project's known regions, and the strings built into
  every app target.
- **Only what changed, next time.** Existing translations are kept, only new or changed strings are asked for, and a
  language nothing changed in is left as it is.
- **A `localized()` helper, when asked.** `String+Localized.swift`, beside the strings.

## How it works

- Translations are asked for in batches of at most 40, each string with what it is: a button, a title, its comment.
- Every answer is checked: each format specifier kept at its position and of its type, every line break kept, and not
  left in the source language. A bad one is asked for again with the reason; what still fails stays in the source
  language and is named.
- Every table is read back by the system's property list reader before it lands. A request it cannot carry out is
  refused with every problem at once, and nothing is written.
- Without a model, the source language is still written, and the answer names the languages that wait.

## Works well with

`granite` is where an app starts, and the other Rao Craft Agents fill it in: `design` and `loom` its look, `platform`
its menus and entitlements, and `localize` its languages. [Loom](https://github.com/riteshpakala/Loom) ships 28
languages; `localize` keeps an app's in step with its code, a call at a time, so call it again after the others add
pages.

## Get it

In Craft, install Localize from the Agent Store, or run
`craft agents add https://github.com/Rao-Craft-Agents/LocalizeAgent.git`, then say `$localize` in a request.

## Requirements

- A Mac on macOS 14 or later.
- An app written in Swift. When it has an Xcode project, the languages are added to it.
- A host with a model for the translations; without one, only the source language is written.
- MIT licensed.

## For developers

What a call takes and answers, which strings it reads and how the files are made are in the
[reference](Docs/Reference.md). The agent standard it follows is Granite's
[granite-agent/1](https://github.com/riteshpakala/Granite/blob/main/Schema/GraniteAgent.md), and how it is tested is
[TESTING.md](TESTING.md).
