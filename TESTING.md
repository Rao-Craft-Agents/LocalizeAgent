# Testing LocalizeAgent

## Conformance on Hearth

Level 1 of the regime: the call a model should write, sent straight to the installed runner over its wire
(granite-agent/1) with no model, on a copy of Hearth as the journey left it (services, mock data and loom's views
made), then checked by building, testing and screenshotting the app. A pass here means the agent can produce the
result deterministically; whether Craft's model writes this call is tested by the prompts above.

### Hearth's strings, five languages asked

*2026-11-01 · straight to the runner, no model*

**The call**:

```json
{
  "languages": [
    "es",
    "fr",
    "de",
    "ja",
    "pt-BR"
  ]
}
```

**Checks**:
- found 143 strings in 117 Swift files; wrote en.lproj/Localizable.strings
- the five languages wait for a model and the answer says so: translations are tested through Craft
- macOS build: BUILD SUCCEEDED
