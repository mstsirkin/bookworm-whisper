# On-device JavaScript Architecture (iPhone + Android)

Goal: Run an end-to-end pipeline in JavaScript on mobile (iPhone + Android) that:
1) renders a PDF page → PNG image,
2) converts each page image → text via OpenAI (vision),
3) converts text → compressed audio via OpenAI TTS,
4) outputs one audio file per page (AAC) and bundles everything into one ZIP for sharing (e.g., WhatsApp).

This design intentionally avoids on-device re-encoding tools (no ffmpeg, no wasm audio encoders).

## 1. High-level flow

Input: PDF (local file)

Per page:
- Render PDF page to canvas (PDF.js)
- Encode canvas to PNG image blob
- Send image to OpenAI → get text
- Send text to OpenAI TTS (`aac`)
- Produce `page_###.txt` + `page_###.aac`

Output:
- ZIP of all pages
- Optional full concatenated AAC

## 2. Runtime targets

- Capacitor (recommended)
- React Native
- Safari Web App

## 3. PDF rendering

Use PDF.js.

Rules:
- One page at a time
- Scale ~1.5
- Always output PNG
- Free canvas after each page

## 4. Vision prompt (single-step)

Tools allowed for image cleanup only.

Transcription rules:
- Visual inspection only
- Remove headers/footers
- Inline footnotes:
  FOOTNOTE: [ ... ] END OF FOOTNOTE
- JSON only:
  { "file": "..." }

Default prompt (user-resettable):

You may use tools only to improve image quality (crop margins, deskew/rotate, denoise, increase contrast/sharpness).
Do not use any OCR, text-extraction, PDF text layer, or “extract text” tool.
After any cleanup, transcribe the text by visual inspection of the page image, in correct reading order.
Remove repeating page headers and footers.
If there is a footnote, insert it inline exactly as:
FOOTNOTE: [ ... ] END OF FOOTNOTE
Output JSON only with exactly:
{ "file": "<full page text>" }

## 5. TTS

- response_format: "aac"
- One AAC per page

## 6. ZIP bundling

JSZip:
- audio/page_###.aac
- text/page_###.txt
- manifest.json

## 7. WhatsApp

Send ZIP as document.
Large ZIPs supported.

## 8. Memory

- Page-by-page processing
- Optional volume ZIPs

## 9. Modules

pdf/renderPage.ts  
openai/visionToText.ts  
openai/textToAac.ts  
packaging/zipBundle.ts  
pipeline/runPipeline.ts  

## 10. Interfaces

Render → PNG Blob  
Vision → string  
TTS → Uint8Array  
ZIP → Blob  

## 11. Defaults

PNG rendering  
AAC output  
page_001 naming  

## 12. Constraints

No audio transcoding.
AAC bitrate uncontrolled.

## 13. UX core

- API key field (persisted securely)
- Prompt editor (persisted)
- Button: Reset prompt to default
- PDF upload
- Start / Cancel
- Per-page slots + progress
- Retry per page

## 14. UX additions (per-page immediacy)

Artifacts appear immediately.

Per page:
- TXT downloadable as soon as vision finishes
- AAC downloadable as soon as TTS finishes

Stages:
queued → rendering → vision → tts → ready

Global:

- When all TXT ready:
  Enable “Download all TXT (ZIP)”

- When all AAC ready:
  Enable:
   - “Download all AAC (ZIP)”
   - “Download full concatenated AAC”

Concatenated AAC = byte-append ADTS pages.

Cancel:
- Stops new pages
- Aborts in-flight
- Keeps completed results

Persistence:
- OpenAI key (secure storage)
- Prompt
- Voice/model/speed

UX summary:
- Immediate per-page TXT
- Immediate per-page AAC
- Reset-to-default prompt button
- Final buttons gated by readiness
- No waiting for full document


## 15. Vision model + prompt (current defaults)

Vision model:

- `gpt-5.2`

Default PNG → text prompt:

You may use tools only to improve image quality (crop margins, deskew/rotate, denoise, increase contrast/sharpness).
Do not use any OCR, text-extraction, PDF text layer, or “extract text” tool.
After any cleanup, transcribe the text by visual inspection of the page image, in correct reading order.
Remove repeating page headers and footers.
If there is a footnote, insert it inline exactly as:
FOOTNOTE: [ ... ] END OF FOOTNOTE
Output JSON only with exactly:
{ "file": "<full page text>" }

This prompt is persisted locally and can be edited by the user.
A “Reset prompt to default” button restores this block exactly.


## 16. Running as a single HTML file (JS inline)

The app is designed to run as a **single standalone HTML file** with all JavaScript embedded inline.

Structure:

```html
<!DOCTYPE html>
<html>
<body>

<script type="module">
  // entire app.js pasted here
</script>

</body>
</html>
```

Usage:

1. Put the full JS inside `<script type="module">`.
2. Open the file directly in a modern browser (Safari / Chrome / Edge).

If PDF.js workers fail under `file://`, run a tiny local server:

```bash
python3 -m http.server
```

Then open:

```
http://localhost:8000/app.html
```

No build step.
No backend.
Everything runs locally except OpenAI API calls.



## 17. Full combined text download

In addition to per-page TXT downloads, the UI must provide:

- **Download full text (single TXT)**

Behavior:

- As soon as **all text pages** are ready:
  - Enable a button: “Download full combined TXT”
- The combined file is created by concatenating all `page_###.txt` contents in page order,
  separated by two newlines between pages.
- Output filename example:
  - `full.txt`

This is independent of audio readiness and appears together with:

- “Download all TXT (ZIP)”

Summary:

- Per-page TXT → immediate
- Full combined TXT → when all text pages complete


## 18. Parallel page processing

The pipeline supports **parallel processing of pages** to improve throughput.

### User control

Add a numeric input:

- **Max parallel pages** (concurrency limit)
- Default: **30**
- Minimum: 1
- Maximum: user-defined (practically constrained by device memory and API limits)

This value controls how many pages may be simultaneously in-flight (render → vision → TTS).

### Behavior

- Pages are queued in order.
- At most **N** pages (user-selected, default 30) may run concurrently.
- As soon as one page finishes or fails, the next queued page starts.
- Per-page UI updates independently.

### UX

- Field appears near Start button:

  “Max parallel pages: [ 30 ]”

- Changing this value affects the next Start (not mid-run).

### Cancellation

- Cancel aborts all in-flight pages immediately.
- Queued pages are never started.
- Completed pages remain downloadable.

### Rationale

- Default 30 provides strong throughput on modern desktops.
- User may reduce to 1 for low-memory devices or increase for fast desktops.


## 19. Adaptive concurrency (automatic rate‑limit backoff)

Parallelism is **adaptive**, not fixed.

User selects:

- Max parallel pages (default: 30, user may set higher, e.g. 60)

Internally the app maintains:

- `effectiveParallel` (starts equal to user value)

This is the *actual* concurrency used by the scheduler.

### On OpenAI 429 (rate limit)

When any OpenAI request (vision or TTS) returns **HTTP 429**:

1. Reduce effective concurrency gently:

```
effectiveParallel = max(1, floor(effectiveParallel * 0.75))
```

2. Display status:

```
Rate limited. Reducing parallelism to X.
```

3. Retry the failed page after a short randomized delay:

- 1–3 seconds (jitter)

### If repeated 429s occur shortly after

Optionally apply stronger braking:

```
effectiveParallel = max(1, floor(effectiveParallel * 0.5))
```

This prevents oscillation when limits are tight.

### Retry behavior

- Failed page is re-queued automatically.
- Retries use the *new* reduced `effectiveParallel`.
- Queued pages wait until slots are available.

### Slow recovery (optional polish)

After several successful pages with no 429:

```
effectiveParallel += 1
```

Up to the user-defined maximum.

This provides gradual ramp-up.

### Rationale

This is classic **AIMD (Additive Increase / Multiplicative Decrease)**:

- 429 → multiply by 0.75 (gentle backoff)
- sustained success → +1 occasionally

Benefits:

- Automatically adapts to account limits
- Works across GPT‑5.2 vision + TTS
- Prevents hard failures at high user-selected concurrency
- Keeps throughput high when possible

### Summary

- User sets maximum (e.g. 30)
- System dynamically finds safe operating point
- No hard-coded OpenAI limits
- Mobile-friendly and self-correcting



## 20. Per-page restart (full page)

Each page row in the UI includes an additional action:

- **Restart Page**

### Behavior

For a given page:

1. Discard any existing:
   - extracted text
   - generated AAC
2. Reset page state to:

```
vision
```

3. Re-run:

- Vision (PNG → text)
- then TTS (text → AAC)

The PDF render step is re-run to regenerate a fresh PNG for the page.

### UX

Per page buttons:

- Download TXT (when ready)
- Download AAC (when ready)
- **Restart Page** (always enabled once rendering is complete)

Restart button is disabled while that page is actively running.

### Interaction with concurrency

- Restarted pages are re-queued into the same adaptive scheduler.
- They respect:
  - current `effectiveParallel`
  - adaptive 0.75 backoff
  - retry logic

### Rationale

Allows quick recovery from:

- bad transcription
- prompt changes
- temporary vision failures

without restarting the entire document.



### Clarification

“Restart Page” means a **full restart of that page**:

Render (PDF → PNG) → Vision → TTS

Nothing is skipped or reused. Each restart regenerates a fresh PNG and re-runs all steps.



## 21. Vision model dropdown + automatic temperature detection

### Vision model selection

Instead of a free-text field, the UI provides a **dropdown of available models**:

- On API key entry (or via a “Load models” button), the app calls:

```
GET /v1/models
```

using the user’s API key.

- Returned model IDs are filtered (e.g. `gpt-*`) and populated into a `<select>` dropdown.
- User selection updates `visionModel` and is persisted locally.
- This guarantees only models actually available to the user can be chosen.

This avoids “model does not exist” errors.

### Temperature capability detection

OpenAI does **not** expose a reliable capability flag indicating whether a model supports `temperature`.

Therefore the app uses **probe + fallback**:

1. First vision request is attempted with:

```
temperature: 0
```

2. If the API returns an error matching:

- HTTP 400
- message contains “temperature” and “not supported / unsupported / unknown”

then:

3. The request is immediately retried **without `temperature`**.

4. Result is cached locally:

```
temp_supported::<model_id> = true | false
```

5. Future requests for that model automatically include or omit `temperature`
based on this cache.

### Rationale

- Codex-style models reject sampling parameters.
- General models accept them.
- This adaptive approach:

  - requires no hardcoded model lists
  - works across future models
  - avoids user-visible failures
  - converges after a single probe

### Summary

- Vision model chosen via dropdown populated from `/v1/models`
- Temperature support detected dynamically per model
- Decision cached locally
- Vision calls become self-correcting and future-proof
