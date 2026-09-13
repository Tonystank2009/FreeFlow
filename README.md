<div align="center">

# FreeFlow

**Local-first voice dictation for macOS.**
Hold a key, speak, and your words land in whatever app you're in.

Five dictations free. Then $5, once, forever.

</div>

---

## What it is

FreeFlow transcribes your speech on-device and types it into the app you're
already using — your editor, your browser, Slack, anywhere. Transcription runs
locally, so your audio never leaves your Mac.

- **On-device transcription** — Parakeet and Whisper models run locally
- **Types anywhere** — global hotkey, text goes to the focused app
- **Optional AI cleanup** — bring your own key (OpenAI, Anthropic, Groq,
  Gemini, OpenRouter, Cerebras, xAI) or run it locally with Ollama or LM Studio
- **Command and rewrite modes** — dictate an instruction, not just text
- **Custom dictionary** — teach it names and jargon it keeps getting wrong
- **Meeting transcription** and searchable history

Requires macOS 15 or later.

## Pricing

Five free dictations, then a one-time **$5**. No subscription. All future
updates included. The purchase is tied to your account, so it works on every
Mac you sign into.

## It's free software

FreeFlow is licensed under the **GNU GPL v3**. You can read the source, build
it yourself for nothing, modify it, and share it.

So what is the $5 for? A signed and notarized build that opens with one click,
updates, and the work of maintaining it. The licence check is an honest
request, not DRM — and under the GPL it can't be anything else, because you're
entitled to remove it and rebuild.

If money's tight, build it yourself:

```bash
git clone https://github.com/adhyanshupadhyaya/FreeFlow
cd FreeFlow
./build.sh
```

That's not a loophole. It's the licence working as intended.

## Built on FluidVoice

FreeFlow is a modified version of
[FluidVoice](https://github.com/altic-dev/FluidVoice) by Altic Dev, also
GPL-3. Full credit to them for the original work.

[NOTICE.md](NOTICE.md) lists every change, as the GPL requires — the short
version is: renamed and reskinned, upstream's analytics and telemetry removed,
paid licensing added.

## Building and releasing

See [docs/SETUP.md](docs/SETUP.md) for the full setup (Xcode, Developer ID
certificate, Supabase, Dodo Payments).

```bash
./build.sh                  # local debug build
./scripts/release.sh        # signed, notarized DMG in dist/
```

## Licence

[GNU General Public License v3](LICENSE).

Copyright © 2026 FreeFlow contributors.
Copyright © Altic Dev and FluidVoice contributors.
