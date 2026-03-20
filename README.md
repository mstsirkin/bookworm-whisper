# whisper for bookworms

A serverless frontend for turning PDFs and EPUBs into audiobooks.

Runs entirely in the browser from a pair of standalone HTML files.

To use: open `pdf.html` or `epub.html` respectively in a browser. Rest should
be self-explanatory.

I know, the UI is atrocious. If anyone wants to work on that, send a pull request.

## What It Does

Input:
- a local PDF in `pdf.html`
- a local EPUB in `epub.html`

Per selected page in the PDF app:
- render the page to a PNG with PDF.js
- send the page image to a vision model
- extract normalized page text
- send that text to TTS
- produce one `.txt` and one `.aac` artifact per page
- convert AAC to M4B

Per selected section in the EPUB app:
- load the EPUB with epub.js
- extract section text directly from the book spine
- split long text for TTS when needed
- produce one `.txt` and one `.aac` artifact per section
- convert AAC to M4B

## Runtime Behavior

Both UIs are organized around the same processing pipeline shape:

1. enter API credentials
2. upload a PDF / EPUB
3. optionally restrict page / section range and adjust settings
4. start processing
5. download page / section artifacts or aggregated outputs

## Current Features

- page / section range selection
- configurable parallelism
- configurable request staggering
- retry on HTTP 495 rate-limit responses
- restart individual pages / sections
- restart only failed pages / sections
- persistent local settings
- optional keepalive sound volume
- optional keepalive tick interval

## Known issues and work arounds

Parallel conversion speeds things up, but if it fails and complains about rate limits,
set max parallel pages / sections to a lower number. Maybe even 1.

Default vision model is cheaper, but if you have an especially hard to read text, change it
to gpt-5.2 (or later).


## Build on update of AAC to M4B flow

Both `pdf.html` and `epub.html` embed a vendored Mediabunny build for AAC to M4B
conversion. Should you change that part:

### Submodule

`vendor/mediabunny` is a git submodule pointing at:

- `https://github.com/mstsirkin/mediabunny.git`

Initialize it with:

```bash
make init-submodules
```

The `Makefile` checks that the submodule is initialized before trying to build the bundle.

### Targets

- `make init-submodules`
  Initializes git submodules.
- `make bundle`
  Builds the Mediabunny bundle inside the submodule checkout.
- `make update`
  Rebuilds the Mediabunny bundle and inlines it into `pdf.html` and `epub.html`.

## External Dependencies

At build time:
- Mediabunny is built from the git submodule under `vendor/mediabunny`

At runtime the browser app lazily loads some libraries from CDNs:
- PDF.js is loaded in-browser by `pdf.html`
- epub.js is loaded in-browser by `epub.html`
- JSZip is loaded in-browser
- model APIs are called directly from the browser

## Operational Notes

- This is designed for direct browser use, including local `file://`.
- Because it is serverless and frontend-only, the user's OpenAI API key has to be entered into the app.
- Large jobs are limited by browser memory, browser scheduling, and provider rate limits.
- Background-tab execution is inherently unreliable in browsers; best-effort mitigations are included.

## Typical Local Use

Just open `pdf.html` or `epub.html` directly in a modern browser.
