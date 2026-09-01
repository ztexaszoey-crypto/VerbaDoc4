// Supabase Edge Function: generate-cards
// Deploy: supabase functions deploy generate-cards
//
// Environment variables (Supabase Dashboard → Edge Functions → Secrets):
//   GROQ_API_KEY — get free at console.groq.com
//
// Free tier: 14,400 requests/day, 500,000 tokens/minute
// Model: llama-3.3-70b-versatile (fast, high quality, completely free)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!
  );
  const { data: { user }, error: authError } =
    await supabase.auth.getUser(authHeader.slice(7));
  if (authError || !user) {
    return json({ error: "Unauthorized" }, 401);
  }

  // ── Parse body ────────────────────────────────────────────────────────────
  let body: { text?: string; title?: string; cardCount?: number };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const { text = "", title = "Study deck", cardCount = 20 } = body;
  if (!text.trim()) return json({ error: "Missing text" }, 400);

  // ── Call Groq ─────────────────────────────────────────────────────────────
  const groqKey = Deno.env.get("GROQ_API_KEY");
  if (!groqKey) return json({ error: "Server misconfiguration" }, 500);

  const prompt = buildPrompt(text.slice(0, 6000), title, Math.min(cardCount, 25));

  let rawText = "";
  try {
    const res = await fetch(GROQ_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${groqKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "llama-3.3-70b-versatile",
        messages: [{ role: "user", content: prompt }],
        temperature: 0.4,
        max_tokens: 4096,
      }),
    });

    if (!res.ok) {
      console.error("Groq error:", res.status, await res.text());
      return json({ error: "AI unavailable" }, 503);
    }

    const data = await res.json();
    rawText = data?.choices?.[0]?.message?.content ?? "";
  } catch (e) {
    console.error("Groq exception:", e);
    return json({ error: "AI unavailable" }, 503);
  }

  // ── Parse cards ───────────────────────────────────────────────────────────
  const cards = parseCards(rawText);
  if (!cards) return json({ error: "Could not parse AI response" }, 502);

  return json({ cards }, 200);
});

// ── Helpers ───────────────────────────────────────────────────────────────────

interface CardResult { question: string; answer: string; topic: string; }

function parseCards(rawText: string): CardResult[] | null {
  const start = rawText.indexOf("[");
  const end   = rawText.lastIndexOf("]");
  if (start === -1 || end === -1) return null;
  try {
    const arr = JSON.parse(rawText.slice(start, end + 1));
    if (!Array.isArray(arr) || arr.length === 0) return null;
    return arr
      .filter((c: unknown) => {
        if (typeof c !== "object" || c === null) return false;
        const card = c as Record<string, unknown>;
        return typeof card.question === "string" && typeof card.answer === "string";
      })
      .map((c: unknown) => {
        const card = c as Record<string, unknown>;
        return {
          question: String(card.question),
          answer:   String(card.answer),
          topic:    typeof card.topic === "string" ? card.topic : "",
        };
      });
  } catch { return null; }
}

function buildPrompt(text: string, title: string, cardCount: number): string {
  return `You are an expert educator creating flashcards from study material.

Topic: "${title}"

Generate exactly ${cardCount} high-quality flashcards from the material below.

Rules:
- Questions test understanding and application, not just recall
- Answers are concise: 1-3 sentences, no fluff
- Each card has a topic tag (1-3 words)
- Avoid yes/no questions
- Questions must be self-contained

Return ONLY a valid JSON array, nothing else:
[{"question":"...","answer":"...","topic":"..."}]

Material:
${text}`;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
