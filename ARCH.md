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

- App title: **PDF Whisper: Speak Low If You Speak**
- Numbered control rows:
  - `1)` OpenAI API key
  - `2)` Upload PDF
  - `3)` Execution settings toggle
  - `4)` Start processing / Cancel
  - `5)` Download actions
- API key field (persisted locally) with helper links:
  - Creating keys
  - Add to balance
- Execution settings are collapsible (Show settings / Hide settings), collapsed by default.
- Prompt editor (persisted) is inside execution settings.
- Button: **Reset all settings** (keeps API key, resets prompt + execution defaults).
- Per-page slots + progress
- Restart per page

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

- Download row shows a status emoji after `5)`:
  - Not started: `🧘😴`
  - Working: `👷‍♂⏳`
  - Ready: `👍😘`

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
- Reset-all-settings button (API key preserved)
- Final buttons gated by readiness
- No waiting for full document


## 15. Vision model + prompt (current defaults)

Vision model:

- `gpt-4o-mini` (current default in `app.html`)

Default PNG → text prompt:

look at it, remove repeating page headers and footers (but leave title in place), and note if there are footnotes and where they are referenced. then, produce the text of the page.
if there is a footnote, find where the footnote belongs (the place where the footnote is referenced by number!) and insert inline like this:
<insert space here>FOOTNOTE: [ TEXT ] END OF FOOTNOTE .
To be clear: for example, if text has reference [1] and foot note stating 1. SOMETEXT at bottom of page, replace [1] with
 FOOTNOTE: [ SOMETEXT ] END OF FOOTNOTE and completely exclude 1. SOMETEXT at the end of the file.

Do not use OCR do it manually!
return the result in field "file" in json.
Do not add any additional comments besides the markup above. in particular leave any notes outside of the file field in json.

This prompt is persisted locally and can be edited by the user.
A “Reset all settings” action restores this prompt and other execution defaults while keeping the API key.


## 16. Running as a single HTML file (JS inline)

The app is designed to run as a **single standalone HTML file** with all JavaScript embedded inline.

Structure:

```html
<!DOCTYPE html>
<html>
<body>

<script src="https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/jszip@3.10.1/dist/jszip.min.js"></script>
<script>
  // entire app logic pasted here
</script>

</body>
</html>
```

Usage:

1. Keep the CDN `<script src=...>` library tags (PDF.js + JSZip).
2. Put the full app JS inside a normal inline `<script>`.
3. Open the file directly in a modern browser (Safari / Chrome / Edge).
PDF worker behavior:

- App first attempts PDF.js worker mode.
- If browser throws:
  `Refused to cross-origin redirects of the top-level worker script`
  app retries automatically with `disableWorker: true`.

If you still want stricter local-origin behavior under `file://`, run a tiny local server:

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



## 17. Full concatenated text download

In addition to per-page TXT downloads, the UI must provide:

- **Download full concatenated TXT**

Behavior:

- As soon as **all text pages** are ready:
  - Enable a button: “Download full concatenated TXT”
- The combined file is created by concatenating all `page_###.txt` contents in page order,
  separated by two newlines between pages.
- Output filename example:
  - `full.txt`

This is independent of audio readiness and appears together with:

- “Download all TXT (ZIP)”

Summary:

- Per-page TXT → immediate
- Full concatenated TXT → when all text pages complete


## 18. Parallel page processing

The pipeline supports **parallel processing of pages** to improve throughput.

### User control

Add a numeric input:

- **Max parallel pages** (concurrency limit)
- Default: **30**
- Minimum: 0
- Maximum: user-defined (practically constrained by device memory and API limits)
- UI label: **Max parallel pages (0 to start jobs manually)**

This value controls how many pages may be simultaneously in-flight (render → vision → TTS).

### Behavior

- Pages are queued in order.
- If `N > 0`: at most **N** pages run concurrently.
- If `N = 0`: pages are queued but no jobs auto-start.
- When `N > 0`, as soon as one page finishes or fails, the next queued page starts.
- Per-page UI updates independently.
- In manual mode (`N = 0`), user starts jobs page-by-page via **Restart Page**.

### UX

- Field appears in the `3)` execution settings panel (opened via “Show settings”):

  “Max parallel pages (0 to start jobs manually): [ 30 ]”

- Changing this value affects the next Start (not mid-run).

### Cancellation

- Cancel aborts all in-flight pages immediately.
- Queued pages are never started.
- Completed pages remain downloadable.

### Rationale

- Default 30 provides strong throughput on modern desktops.
- User may reduce to 1 for low-memory devices or increase for fast desktops.
- `0` enables manual per-page start workflows.


## 19. Adaptive concurrency (automatic rate‑limit backoff)

Current status in `app.html`:

- Adaptive 429 backoff is **not implemented yet**.
- Scheduler uses the user-selected fixed value (`maxParallel`).
- HTTP 429 does not auto-reduce concurrency.
- `maxParallel = 0` remains reserved for manual-start mode only.



## 20. Per-page restart (full page)

Each page row in the UI includes an additional action:

- **Restart Page**

### Behavior

For a given page:

1. Discard any existing:
   - extracted text
   - generated AAC
2. Reset page state (clear text/audio/error for that page).
3. Re-run full pipeline:

- Render (PDF → PNG)
- Vision (PNG → text)
- TTS (text → AAC)

### UX

Per page buttons:

- Download TXT (when ready)
- Download AAC (when ready)
- **Restart Page**

Restart button is disabled only while a restart is already pending for that page.

### Interaction with concurrency

- Restarted pages are managed by the same scheduler pool.
- If page is already running:
  - restart marks pending
  - aborts in-flight request(s)
  - immediately starts a fresh run for that same page.
- If page is queued or idle while pipeline is running:
  - restart starts it immediately, even if this temporarily exceeds `maxParallel`.

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



## 21. Vision model input + automatic temperature detection

### Vision model selection

UI currently uses a **free-text model field** (persisted locally), e.g.:

- `gpt-4o-mini`
- codex-family IDs (if available to the API key)

The app does not currently pre-load model IDs from `/v1/models`.

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

- Vision model entered via persisted text field
- Temperature support detected dynamically per model
- Decision cached locally
- Vision calls become self-correcting and future-proof


## 22. Future ideas

The following items were previously described as active behavior but are now tracked as future enhancements.

### Vision model dropdown from `/v1/models`

Possible implementation:

- Call `GET /v1/models` using the user API key.
- Filter returned IDs to relevant vision-capable model families.
- Populate a `<select>` dropdown instead of free-text input.
- Persist selected model ID locally.

Expected benefit:

- Fewer invalid-model errors.
- Better discoverability of models available to each user key.

### Scale
should be integer by default. switch to 2

### Handling 429
- retry later
- stargger starting connections - e.g. by 1sec
- 429 error from openai actually tells you how long to wait


### Adaptive concurrency backoff on 429

Possible implementation:

- Keep user `maxParallel` as an upper bound.
- Track runtime `effectiveParallel`.
- On HTTP 429:
  - reduce `effectiveParallel` (e.g., multiplicative decrease),
  - re-queue failed page with jittered retry delay.
- After sustained success:
  - slowly increase `effectiveParallel` (additive increase).
- Clamp automatic backoff floor to `1` so manual mode (`maxParallel = 0`) remains user-controlled.

Expected benefit:

- Better throughput under changing rate limits.
- Fewer hard failures at high concurrency settings.

#  failed job handling

if some job failed show a shrug emoji not thumbs up
add a button to restart all failed jobs

#  cost estimate
show cost - do we get it from openai?
what about disconnects we still get charged possibly?
maybe stress it is an estimate
a button to reset cost counter
show cost per page
