# LocalizeAgent

An app's translations, harvested from its own Swift, shipped as a [Granite](https://github.com/riteshpakala/Granite)
agent package. A call names the languages; the package reads every localizable string out of the app's code, writes the
source language, has the host's model translate what is new or changed into each language in checked batches, and adds
the languages to the Xcode project.

It is one of the [Rao Craft Agents](https://github.com/Rao-Craft-Agents): independent packages that, tagged in prompts
along the life of a project, build an app of [Loom](https://github.com/riteshpakala/Loom)'s quality. Loom ships 28
languages; `localize` keeps an app's in step with its code, a call at a time.

## How an app finds it

LocalizeAgent is a `GraniteAgentPackage`, and it carries a record in its binary:

```swift
@used @section("__DATA_CONST,__granite")
let localizeRecord: GraniteRoster.Record = { GraniteRoster.record(LocalizeAgent.self) }
```

In [Craft](https://github.com/riteshpakala/Craft), install it from the Agent Store or with
`craft agents add https://github.com/Rao-Craft-Agents/LocalizeAgent.git`, then say `$localize` in a request:

```
$localize the recipe app into French, German, Japanese and Arabic
```

The model writes the call (`{"languages": ["fr", "de", "ja", "ar"]}`); the call shows on Craft's agent map as
`localize-1`, and the tables and project file it names are built with the turn.

## What a call takes and answers

| Field | | |
|---|---|---|
| `languages` | optional | codes such as `fr`, `de`, `ja`, `zh-Hans`, `pt-BR` (names like `French` are read too), or `loom` for Loom's 28; every language the app has when left out |
| `source` | optional | the language the Swift's strings are written in; `en` when left out |
| `format` | optional | `strings` (one `Localizable.strings` a language) or `catalog` (one `Localizable.xcstrings`); what the project uses when left out |
| `into` | optional | the folder holding the `.lproj` folders or the catalog; where the project keeps them, else `Shared/i18n` |
| `scan` | optional | folders or Swift files to read; the whole project when left out |
| `refresh` | optional | `true` translates every string of the languages named again; existing translations are kept when left out |
| `helper` | optional | `true` writes `String+Localized.swift` with `localized()` beside the strings' folder |
| `rounds` | optional | how many times a batch is asked for before what fails stays in the source language; 3, at most 6 |
| `directory` | the host's | the folder the host works in; a host fills it and does not show it to a model |

The answer is a `LocalizeResult`: every file written (`path`, `paths`, absolute; a file that came out the same is not
written), the app's languages, how many strings were found, added and translated, the languages that still wait, and a
sentence for anything left out.

```json
{"languages": ["fr", "de", "ja", "ar"]}
{"languages": ["loom"]}
{}
{"languages": ["es", "pt-BR"], "format": "catalog"}
{"languages": ["fr"], "refresh": true}
{"languages": ["it"], "helper": true}
{"languages": ["ko"], "scan": ["Components", "Shared/Views"]}
```

## The strings

A literal is a key where SwiftUI or Foundation looks it up at run time: the first argument of `Text`, `Label`, `Button`,
`Toggle`, `Section`, `TextField`, `Picker`, `Menu`, `Link`, `ContentUnavailableView` and the other views that take a
`LocalizedStringKey`; `.navigationTitle`, `.help`, `.alert`, `.confirmationDialog`, `.accessibilityLabel`;
`String(localized:)`, `LocalizedStringResource`, `LocalizedStringKey`, `NSLocalizedString`, `"KEY".localized()`; a ternary
of literals in those places; and a literal given to a property or parameter the app declares as a `LocalizedStringKey`, or
returned by a computed one. An interpolation becomes the specifier the runtime asks for: an `Int` is `%lld`, an `Int32`
`%d`, a `Double` `%lf`, a `specifier:` its own, anything else `%@`; a `%` beside one is doubled. A key with several
specifiers reads numbered in the source language (`Cooked by %1$@ in %2$lld minutes`), so a language can reorder them.
The call's `comment:` is kept above its entry.

Not a key: `Text(verbatim:)`, a literal built into a `String`, a string with no letters (`"•"`, `"\(name)"`), another
table's or a package's string, and a preview's sample text. `.build`, `DerivedData`, packages and tests are not read
unless `scan` names them.

## How the files are made

| Step | What |
|---|---|
| Read | the call checked; every problem refused at once, and nothing written |
| Harvest | every Swift file's declarations read (a name's type, a parameter that takes a key), then every file's keys |
| Table | the app's strings read from its `.lproj` files or catalog; a key the Swift no longer shows is kept (a key built at run time is not seen) |
| Source | a key in capitals (`RECIPES_EMPTY_TITLE`) gets its source text from the model; every other key is its own |
| Translate | what a language lacks, what stands in for a translation, and what was made from a changed source text, asked for in batches of at most 40 by id, with what each string is (a button, a title, its comment) |
| Check | every answer: every specifier kept at its position and of its type, every line break, not left in the source language, not a paragraph; a bad one is asked for again with the reason, and what fails every round stays in the source language and is named |
| Write | one table a language, sorted, its comments kept; a language's entry says the source text it was made from when that is not the key, and marks a stand-in; a language nothing changed in is left as it is; every table is read back by the system's property list reader before it lands |
| Project | the languages in `knownRegions`, and the strings' folder inside a synchronized folder of every app target (a classic project gets each language's file in its `Localizable.strings` group); idempotent text edits read back before they land |

Without a model the source language is still written, and the answer names the languages that wait.

## Testing

```
swift test                       # the record, the schema, the harvest (matched against the compiler's own), the tables, the checks, whole calls
LOCALIZE_BUILD=1 swift test      # a recipe app localized into four languages, built for macOS and the iOS Simulator, and run
```

MIT licensed.
