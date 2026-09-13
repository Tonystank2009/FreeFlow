# FreeFlow — attribution and modification notice

FreeFlow is a modified version of **FluidVoice**, published by Altic Dev at
<https://github.com/altic-dev/FluidVoice> and licensed under the GNU General
Public License, version 3.

Forked from upstream commit `b395a7af0242b6869867abdd61e245a5a80ec218`
on **13 September 2026**.

FreeFlow remains licensed under the **GNU GPL v3** — see [LICENSE](LICENSE).
This is required: GPL-3 is copyleft, so a modified version must carry the same
licence and the same freedoms.

## Modifications made by FreeFlow

As required by GPL-3 §5(a), these are the substantive changes from upstream:

### Identity
- Renamed the product from FluidVoice to FreeFlow throughout, including bundle
  identifier, scheme, entitlements file, log directory and Keychain scopes.
- Replaced the application icon, menu bar glyph and wordmark with original
  artwork. Upstream's marks are its trademarks and are **not** covered by the
  GPL grant, so they are not redistributed here.
- Reset the version line to 1.0.0.

### Removal of upstream infrastructure
- Removed the PostHog analytics credentials embedded in `Info.plist`, which
  reported usage into upstream's analytics project.
- Disabled the endpoint that POSTed raw and AI-processed dictation text to
  `altic.dev`. Sharing a user's transcribed words now requires an explicitly
  configured service and is off by default.
- Repointed in-app feedback, support and documentation links away from
  upstream's services.

### Added: paid licensing
- Added account-based licensing: five free dictations, then a one-time
  US$5 purchase that unlocks the app permanently.
- Added Supabase email-OTP accounts so an entitlement follows the person rather
  than the machine.
- Added Dodo Payments checkout and webhook fulfilment.

## What the payment does and does not do

FreeFlow is free software. Paying is a way to support its development and to
get a signed, notarised, ready-to-run build — it is **not** a restriction on
your rights.

Under the GPL you may always:

- obtain the complete source code,
- build FreeFlow yourself at no cost,
- modify it, including removing the licence check, and
- redistribute your modified version, provided you also license it under GPL-3.

The licence gate is a request, not an enforcement mechanism, and is written
that way deliberately.

## Third-party components

FreeFlow builds on the dependencies declared in `Package.resolved`, each under
its own licence, including FluidAudio, DynamicNotchKit, AppUpdater, PromiseKit
and transcribe-cpp-swift.
