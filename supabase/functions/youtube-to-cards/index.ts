import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"

// ── Extract video ID from any YouTube URL format ──────────────────────────────
function extractVideoId(url: string): string | null {
  const patterns = [
    /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/|youtube\.com\/v\/)([a-zA-Z0-9_-]{11})/,
    /youtube\.com\/shorts\/([a-zA-Z0-9_-]{11})/,
  ]
  for (const p of patterns) {
    const m = url.match(p)
    if (m) return m[1]
  }
  return null
}

// ── Fetch YouTube transcript by scraping the page ─────────────────────────────
async function fetchTranscript(videoId: string): Promise<{ transcript: string; title: string }> {
  const res = await fetch(`https://www.youtube.com/watch?v=${videoId}`, {
    headers: {
      "Accept-Language": "en-US,en;q=0.9",
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    },
  })

  if (!res.ok) throw new Error("Could not reach YouTube")
  const html = await res.text()

  // Extract page title
  const titleMatch = html.match(/<title>(.+?)\s*-\s*YouTube<\/title>/)
  const title = titleMatch ? titleMatch[1].trim() : "YouTube Video"

  // Find caption tracks in the page source
  const captionMatch = html.match(/"captionTracks":(\[.*?\])/)
  if (!captionMatch) {
    throw new Error("No captions found. This video may not have subtitles enabled.")
  }

  let captionTracks: any[]
  try {
    captionTracks = JSON.parse(captionMatch[1])
  } catch {
    throw new Error("Failed to parse caption data")
  }

  if (!captionTracks.length) {
    throw new Error("No caption tracks available for this video")
  }

  // Prefer English, fall back to first available
  const track =
    captionTracks.find((t: any) => t.languageCode === "en") ??
    captionTracks.find((t: any) => t.languageCode?.startsWith("en")) ??
    captionTracks[0]

  if (!track?.baseUrl) throw new Error("No usable caption track found")

  // Fetch caption XML
  const captionRes = await fetch(track.baseUrl + "&fmt=xml")
  if (!captionRes.ok) throw new Error("Failed to fetch captions")
  const xml = await captionRes.text()

  // Parse XML text nodes
  const segments: string[] = []
  const matches = xml.matchAll(/<text[^>]*>([\s\S]*?)<\/text>/g)
  for (const m of matches) {
    const text = m[1]
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&apos;/g, "'")
      .replace(/<[^>]+>/g, "")
      .replace(/\n/g, " ")
      .trim()
    if (text) segments.push(text)
  }

  if (!segments.length) throw new Error("Transcript is empty")

  return { transcript: segments.join(" "), title }
}

// ── Generate cards with Groq ──────────────────────────────────────────────────
async function generateCards(
  transcript: string,
  videoTitle: string,
  cardCount: number,
  groqKey: string,
): Promise<{ question: string; answer: string; topic: string }[]> {

  // Trim transcript to ~12k chars to stay within token limits
  const trimmed = transcript.slice(0, 12000)

  const prompt = `You are an expert educator. Below is a transcript from a YouTube video titled "${videoTitle}".

Create exactly ${cardCount} high-quality flashcards from the most important ideas in this transcript.

Rules:
- Each question must be specific and educational
- Answers should be clear, 1-3 sentences max
- Topic should be a short category label (2-4 words)
- Cover a range of concepts from the video
- Do NOT include timestamps or filler phrases

Respond ONLY with valid JSON, no markdown:
{"cards":[{"question":"...","answer":"...","topic":"..."}]}

TRANSCRIPT:
${trimmed}`

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
  })

  if (!res.ok) {
    const err = await res.text()
    throw new Error(`Groq error: ${err}`)
  }

  const data = await res.json()
  const raw = data.choices?.[0]?.message?.content ?? ""

  // Strip markdown code fences if present
  const cleaned = raw.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim()

  let parsed: any
  try {
    parsed = JSON.parse(cleaned)
  } catch {
    // Try to extract JSON object
    const jsonMatch = cleaned.match(/\{[\s\S]*\}/)
    if (!jsonMatch) throw new Error("Could not parse Groq response as JSON")
    parsed = JSON.parse(jsonMatch[0])
  }

  return (parsed.cards ?? []).slice(0, cardCount)
}

// ── Handler ───────────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS })

  try {
    // Auth: verify Supabase JWT
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) return new Response("Unauthorized", { status: 401, headers: CORS })

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
    )
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", "")
    )
    if (authError || !user) return new Response("Unauthorized", { status: 401, headers: CORS })

    const { url, cardCount = 20 } = await req.json()
    if (!url) return new Response(JSON.stringify({ error: "url is required" }), { status: 400, headers: CORS })

    const videoId = extractVideoId(url)
    if (!videoId) {
      return new Response(JSON.stringify({ error: "Invalid YouTube URL. Paste a full YouTube link." }), {
        status: 400, headers: CORS,
      })
    }

    const groqKey = Deno.env.get("GROQ_API_KEY")
    if (!groqKey) throw new Error("GROQ_API_KEY not set")

    // 1. Fetch transcript
    const { transcript, title } = await fetchTranscript(videoId)

    // 2. Generate cards
    const cards = await generateCards(transcript, title, cardCount, groqKey)

    return new Response(
      JSON.stringify({ cards, title, videoId, transcriptLength: transcript.length }),
      { headers: { ...CORS, "Content-Type": "application/json" } },
    )

  } catch (err: any) {
    console.error(err)
    return new Response(
      JSON.stringify({ error: err.message ?? "Something went wrong" }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    )
  }
})
