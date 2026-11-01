import GraniteAgents

/// The localize agent's place in Granite's roster: an app that links this package finds the `localize` agent by this
/// record, with nothing listed by hand.
@used @section("__DATA_CONST,__granite")
let localizeRecord: GraniteRoster.Record = { GraniteRoster.record(LocalizeAgent.self) }
