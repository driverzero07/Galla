// Reference Edge Function for the OPTIONAL photo import (Part 6).
// NOT DEPLOYED and NOT TESTED. The app has this feature switched off
// (FeatureFlags.ocrImport = false). Before turning it on:
//   supabase secrets set VISION_API_KEY=... VISION_API_URL=... VISION_MODEL=...
//   supabase functions deploy ocr-ledger
// The key lives only in the function's secrets, never in the app.
//
// Request : { "image_base64": "...", "mime": "image/jpeg" }
// Response: { "entries": [ { "name": "Akram", "amount": "3400", "confidence": 0.93 } ] }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const PROMPT =
  "This is a photo of a shopkeeper's handwritten udhaar ledger (names and " +
  "amounts owed, Urdu or Roman Urdu). Return ONLY JSON: " +
  '{"entries":[{"name":string,"amount":string,"confidence":number 0..1}]}. ' +
  "Copy the amount as written; put a ? after it if unsure. Skip headings.";

serve(async (req) => {
  if (req.method !== "POST") return new Response("method", { status: 405 });
  // Only signed-in shop owners may call this (Supabase checks the JWT).
  if (!req.headers.get("authorization")) {
    return new Response("unauthorized", { status: 401 });
  }
  const key = Deno.env.get("VISION_API_KEY");
  const url = Deno.env.get("VISION_API_URL");
  const model = Deno.env.get("VISION_MODEL");
  if (!key || !url || !model) {
    return new Response("not configured", { status: 503 });
  }
  const { image_base64, mime } = await req.json();
  if (typeof image_base64 !== "string" || image_base64.length > 8_000_000) {
    return new Response("bad image", { status: 400 });
  }

  // Adapt this request body to the vision provider you choose.
  const upstream = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
    body: JSON.stringify({ model, prompt: PROMPT, image: image_base64, mime }),
  });
  if (!upstream.ok) return new Response("upstream", { status: 502 });

  // The provider's reply text must be the JSON above; anything else = empty.
  let entries: unknown[] = [];
  try {
    const out = await upstream.json();
    const text = typeof out === "string" ? out : out.text ?? out.output ?? "";
    const parsed = typeof text === "string" ? JSON.parse(text) : text;
    if (Array.isArray(parsed?.entries)) entries = parsed.entries;
  } catch (_) { /* leave empty */ }

  return new Response(JSON.stringify({ entries }), {
    headers: { "content-type": "application/json" },
  });
});
