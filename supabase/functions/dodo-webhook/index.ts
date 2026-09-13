// FreeFlow — Dodo Payments webhook receiver
//
// Verifies a Standard Webhooks signature, then grants the buyer's account an
// entitlement. Runs on the service role, so it is the only thing in the system
// that can write to public.entitlements.
//
// Deploy:
//   supabase functions deploy dodo-webhook --no-verify-jwt
//   supabase secrets set DODO_WEBHOOK_SECRET=whsec_...
//
// --no-verify-jwt is required: Dodo calls this with a webhook signature, not a
// Supabase JWT. The signature check below is what authenticates the request.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const WEBHOOK_SECRET = Deno.env.get("DODO_WEBHOOK_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/** Events that grant access, and those that take it away. */
const GRANT_EVENTS = new Set(["payment.succeeded"]);
const REVOKE_EVENTS = new Set([
  "payment.failed",
  "refund.succeeded",
  "dispute.won",
  "dispute.accepted",
]);

function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/**
 * Standard Webhooks verification.
 *
 * Signed content is `${id}.${timestamp}.${body}`, HMAC-SHA256 with the secret
 * (base64 after the `whsec_` prefix). The header may carry several
 * space-separated `v1,<sig>` values during a secret rotation, so any match
 * counts.
 */
async function verify(
  body: string,
  id: string,
  timestamp: string,
  signatureHeader: string,
): Promise<boolean> {
  if (!WEBHOOK_SECRET) return false;

  // Reject replays outside a five-minute window.
  const sent = Number(timestamp);
  if (!Number.isFinite(sent)) return false;
  if (Math.abs(Date.now() / 1000 - sent) > 300) return false;

  const rawSecret = WEBHOOK_SECRET.startsWith("whsec_")
    ? WEBHOOK_SECRET.slice(6)
    : WEBHOOK_SECRET;

  let keyBytes: Uint8Array;
  try {
    keyBytes = Uint8Array.from(atob(rawSecret), (c) => c.charCodeAt(0));
  } catch {
    keyBytes = new TextEncoder().encode(rawSecret);
  }

  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signed = `${id}.${timestamp}.${body}`;
  const mac = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signed)),
  );

  for (const part of signatureHeader.split(" ")) {
    const value = part.includes(",") ? part.split(",")[1] : part;
    if (!value) continue;
    try {
      const provided = Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
      if (timingSafeEqual(mac, provided)) return true;
    } catch {
      // Malformed segment — keep checking the rest.
    }
  }
  return false;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const body = await req.text();
  const id = req.headers.get("webhook-id") ?? "";
  const timestamp = req.headers.get("webhook-timestamp") ?? "";
  const signature = req.headers.get("webhook-signature") ?? "";

  if (!id || !timestamp || !signature) {
    return new Response("Missing signature headers", { status: 400 });
  }

  if (!(await verify(body, id, timestamp, signature))) {
    // Do not leak why.
    return new Response("Invalid signature", { status: 401 });
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(body);
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const type = String(event.type ?? "");
  const data = (event.data ?? {}) as Record<string, unknown>;

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // Idempotency — Standard Webhooks redelivers on any non-2xx.
  const { error: seenError } = await admin
    .from("processed_webhooks")
    .insert({ webhook_id: id, event_type: type });

  if (seenError) {
    // Primary-key collision means we already handled this event.
    if (seenError.code === "23505") {
      return new Response(JSON.stringify({ ok: true, deduped: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    console.error("dedupe insert failed", seenError);
    return new Response("Storage error", { status: 500 });
  }

  const isGrant = GRANT_EVENTS.has(type);
  const isRevoke = REVOKE_EVENTS.has(type);
  if (!isGrant && !isRevoke) {
    return new Response(JSON.stringify({ ok: true, ignored: type }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Resolve which account this payment belongs to.
  const metadata = (data.metadata ?? {}) as Record<string, string>;
  const customer = (data.customer ?? {}) as Record<string, string>;
  const email = (customer.email ?? "").trim().toLowerCase();

  let userId = metadata.supabase_user_id ?? metadata.metadata_supabase_user_id ?? "";

  if (!userId) {
    if (!email) {
      console.error("no user id and no email on event", id);
      return new Response("Unresolvable customer", { status: 422 });
    }

    // Someone who paid from the website without signing in first still gets an
    // account, so the entitlement is waiting when they sign in with that email.
    const { data: existing } = await admin.auth.admin.listUsers({
      page: 1,
      perPage: 1,
      // @ts-expect-error: filter is supported by GoTrue admin API
      filter: `email.eq.${email}`,
    });

    const found = existing?.users?.find(
      (u: { email?: string }) => (u.email ?? "").toLowerCase() === email,
    );

    if (found) {
      userId = found.id;
    } else {
      const { data: created, error: createError } = await admin.auth.admin
        .createUser({ email, email_confirm: true });
      if (createError || !created?.user) {
        console.error("could not create user for", email, createError);
        return new Response("User creation failed", { status: 500 });
      }
      userId = created.user.id;
    }
  }

  const productID = String(
    (data.product_id ?? metadata.product_id ?? "") as string,
  );
  const paymentID = String((data.payment_id ?? data.id ?? "") as string);

  const { error: writeError } = await admin
    .from("entitlements")
    .upsert({
      user_id: userId,
      status: isGrant ? "active" : "refunded",
      source: "dodo",
      product_id: productID || null,
      payment_id: paymentID || null,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });

  if (writeError) {
    console.error("entitlement write failed", writeError);
    return new Response("Storage error", { status: 500 });
  }

  return new Response(
    JSON.stringify({ ok: true, user_id: userId, status: isGrant ? "active" : "refunded" }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
