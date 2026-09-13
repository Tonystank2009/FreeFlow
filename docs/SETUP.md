# FreeFlow — launch setup

Everything below is a step only you can do (it needs your accounts). The code
is already written and wired; these fill in the blanks.

`scripts/release.sh` refuses to build a release while any `REPLACE_ME` value
remains, so you cannot accidentally ship a build that can't take money.

---

## 1. Xcode and your Developer ID certificate

The project is an Xcode project with asset catalogs, so Command Line Tools
alone cannot build it.

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

Then get a **Developer ID Application** certificate. Having an Apple Developer
account is not enough — the certificate has to be issued and installed:

**Xcode → Settings → Accounts → (your Apple ID) → Manage Certificates → `+` →
Developer ID Application**

Verify:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Finally, store notarization credentials once. Use an **app-specific password**
from <https://appleid.apple.com> — not your Apple ID password:

```bash
xcrun notarytool store-credentials FreeFlowNotary \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID" \
  --password "abcd-efgh-ijkl-mnop"
```

---

## 2. Supabase — accounts and entitlements

1. Create a project at <https://supabase.com>.

2. Run the migration (**SQL Editor** → paste → Run):
   `supabase/migrations/0001_entitlements.sql`

3. Enable email OTP: **Authentication → Providers → Email** → turn on
   *Enable Email provider*, and make sure **Confirm email** is on so the
   6-digit code is sent.

   In **Authentication → Email Templates → Magic Link**, ensure the template
   includes `{{ .Token }}` — that is the 6-digit code FreeFlow asks for. The
   default template only contains a link, and the in-app code entry will look
   broken without it.

4. Copy **Project URL** and the **anon / publishable key** from
   **Settings → API** into `Sources/FreeFlow/Licensing/Brand.swift`:

   ```swift
   static let projectURLString = "https://YOURPROJECT.supabase.co"
   static let anonKey = "eyJhbGciOi..."
   ```

   The anon key is public by design — it grants nothing on its own, and row
   level security restricts every read to the caller's own row. It is safe in
   a GPL binary.

5. Deploy the webhook function:

   ```bash
   supabase link --project-ref YOURPROJECTREF
   supabase functions deploy dodo-webhook --no-verify-jwt
   ```

   `--no-verify-jwt` is required: Dodo authenticates with a webhook signature,
   not a Supabase JWT. The function verifies that signature itself.

---

## 3. Dodo Payments — the $5 product

1. Create a **one-time payment** product at $5 in the Dodo dashboard.

2. Copy its **product id** (`pdt_…`) and its **payment link** into
   `Brand.swift`:

   ```swift
   static let checkoutURLString = "https://checkout.dodopayments.com/buy/pdt_..."
   static let productID = "pdt_..."
   ```

3. Add a webhook pointing at your deployed function:

   ```
   https://YOURPROJECT.supabase.co/functions/v1/dodo-webhook
   ```

   Subscribe to `payment.succeeded`, plus `refund.succeeded` and the dispute
   events if you want refunds to revoke access automatically.

4. Copy the webhook signing secret (`whsec_…`) into Supabase:

   ```bash
   supabase secrets set DODO_WEBHOOK_SECRET=whsec_...
   ```

5. Switch to live mode. In `Brand.swift`, `Dodo.useTestMode` should be `false`
   for release (set it `true` only while testing against the sandbox).

### How a purchase flows

```
App: sign in (email OTP)  ──▶  Supabase issues a session
App: "Buy — $5"           ──▶  Dodo checkout, carrying the user's id
Dodo: payment.succeeded   ──▶  your edge function (signature verified)
Function                  ──▶  upsert entitlements row (service role)
App: polls for ~40s       ──▶  sees active entitlement, unlocks
```

Someone who pays *without* signing in first still gets an account created from
their payment email, so the entitlement is waiting when they sign in later.

---

## 4. Cut the release

```bash
./scripts/release.sh
```

This builds, signs with your Developer ID, notarizes, staples, and writes
`dist/FreeFlow-1.0.0.dmg`. Expect notarization to add a few minutes.

To test the build without notarizing:

```bash
./scripts/release.sh --no-notarize
```

---

## 5. Publish — and meet the GPL obligation

FreeFlow is GPL-3. Selling it is explicitly allowed, but you **must** publish
the source for each binary you distribute.

```bash
git remote add origin https://github.com/adhyanshupadhyaya/FreeFlow.git
git push -u origin main
git tag v1.0.0 && git push origin v1.0.0
```

Attach the DMG to the GitHub release for that tag. The in-app updater reads
releases from this repo, so this is also what makes auto-update work.

---

## What buyers can do (and why that's fine)

Because FreeFlow is GPL-3, anyone may delete the licence check, rebuild, and
redistribute the result. The $5 gate is an honest request, not DRM — and it
cannot be made into DRM without violating the licence.

This model works anyway: people pay for a signed, notarised, one-click build,
for updates, and to support the work. Price accordingly, and don't spend effort
hardening a gate the licence guarantees is removable.

---

## Optional

- `Brand.supportEmail` — a public support address. Left unset on purpose; a
  shipped app broadcasts it to every user. Unset routes support to GitHub
  issues.
- `Brand.feedbackEndpoint` / `Brand.transcriptionSampleEndpoint` — both `nil`.
  The second one carries users' dictated text; only set it if you run the
  receiving service and disclose it in a privacy policy.
