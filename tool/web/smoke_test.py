#!/usr/bin/env python3
"""Playwright smoke test for the Audix Flutter web build.

Loads the app, waits for boot + drift's wasm DB, enables Flutter's
accessibility tree, navigates every bottom-nav tab and asserts the app stays
error-free and the Settings screen renders real content.

Usage:
  python3 tool/web/smoke_test.py <url> <chromium-executable> [out-dir] \
      [video-dir] [import.m4b] [subtitles.vtt]

When [video-dir] is given, a screen recording is written to
<video-dir>/audix-web-smoke.webm. When [subtitles.vtt] is given (alongside an
import file), the test also attaches the transcript to the imported book and
verifies the lyrics-style transcript screen. Exit code 0 on success, 1 on
failure.
"""
import os
import sys
from playwright.sync_api import sync_playwright

URL = sys.argv[1]
EXE = sys.argv[2]
OUT = sys.argv[3] if len(sys.argv) > 3 else "/tmp/audix-web"
VIDEO_DIR = sys.argv[4] if len(sys.argv) > 4 else None
# Optional .m4b to import; when given, the test uploads it and asserts the book
# appears in the library.
IMPORT_FILE = sys.argv[5] if len(sys.argv) > 5 else None
# Optional .vtt to attach to the imported book (exercises the transcript view).
SUBTITLE_FILE = sys.argv[6] if len(sys.argv) > 6 else None

errors = []
ok = True
os.makedirs(OUT, exist_ok=True)

# Playwright records video at the CSS *viewport* size, and Flutter's web layout
# is driven by that logical width — so a phone-sized viewport gives a tight,
# phone-like layout. device_scale_factor only adds rendering sharpness (it does
# not change the layout), so render at 2x. Default: 414x896 (phone portrait).
VIEW_W = int(os.environ.get("AUDIX_VIEW_W", "414"))
VIEW_H = int(os.environ.get("AUDIX_VIEW_H", "896"))
SCALE = float(os.environ.get("AUDIX_SCALE", "2"))

with sync_playwright() as p:
    browser = p.chromium.launch(
        executable_path=EXE,
        headless=True,
        args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
    )
    ctx_args = {
        "viewport": {"width": VIEW_W, "height": VIEW_H},
        "device_scale_factor": SCALE,
    }
    if VIDEO_DIR:
        os.makedirs(VIDEO_DIR, exist_ok=True)
        ctx_args["record_video_dir"] = VIDEO_DIR
        # Match the viewport so the app fills the whole frame.
        ctx_args["record_video_size"] = {"width": VIEW_W, "height": VIEW_H}
    context = browser.new_context(**ctx_args)
    page = context.new_page()
    page.on("pageerror", lambda e: errors.append(f"pageerror: {e}"))
    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(9000)

    # Enable Flutter's semantics tree (JS click bypasses the off-screen guard).
    page.evaluate("() => document.querySelector('flt-semantics-placeholder')?.click()")
    page.wait_for_timeout(2500)

    def labels():
        return page.eval_on_selector_all(
            "flt-semantics[aria-label]",
            "els => els.map(e => e.getAttribute('aria-label')).filter(Boolean)",
        )

    def click_label(label, timeout=8000):
        """Clicks the Flutter semantics node with the given aria-label."""
        sel = f'flt-semantics[aria-label="{label}"]'
        page.wait_for_selector(sel, timeout=timeout)
        page.query_selector(sel).click(force=True)

    def click_button(text, timeout=8000):
        """Clicks the semantics button whose text (its tooltip/label) matches.

        Flutter web exposes a button's tooltip as textContent, not aria-label.
        """
        waited = 0
        while waited < timeout:
            for e in page.query_selector_all('flt-semantics[role="button"]'):
                if (e.text_content() or "").strip() == text:
                    e.click(force=True)
                    return
            page.wait_for_timeout(300)
            waited += 300
        raise TimeoutError(f'button "{text}" not found')

    def all_semantics_text():
        return " | ".join(
            (e.text_content() or "")
            for e in page.query_selector_all("flt-semantics")
        )

    nav = labels()
    print("nav labels:", nav)
    for tab in ("Library", "Bookmarks", "Servers", "Settings"):
        if tab not in nav:
            print(f"FAIL: nav destination '{tab}' not found")
            ok = False

    for tab in ("Bookmarks", "Servers", "Settings", "Library"):
        el = page.query_selector(f'flt-semantics[aria-label="{tab}"]')
        if not el:
            continue
        el.click(force=True)
        page.wait_for_timeout(2500)
        page.screenshot(path=f"{OUT}/tab_{tab.lower()}.png")
        if tab == "Settings" and "Skip interval" not in labels():
            print("FAIL: Settings content did not render")
            ok = False

    # Import a real audiobook from the Library tab and assert it appears. The
    # bytes are stored in the browser (drift wasm DB) and played via a blob URL.
    if IMPORT_FILE:
        import_btn = next(
            (e for e in page.query_selector_all('flt-semantics[role="button"]')
             if "Import" in (e.text_content() or "")),
            None,
        )
        if import_btn is None:
            print("FAIL: import button not found")
            ok = False
        else:
            with page.expect_file_chooser(timeout=8000) as fc:
                import_btn.click(force=True)
            fc.value.set_files(IMPORT_FILE)
            page.wait_for_timeout(8000)  # import + finalize (duration probe)
            page.screenshot(path=f"{OUT}/import.png")
            joined = " | ".join(
                (e.text_content() or "")
                for e in page.query_selector_all("flt-semantics")
            )
            if "No audiobooks yet" in joined:
                print("FAIL: imported book did not appear")
                ok = False
            else:
                print("imported a book on the web")

    # Attach a transcript to the imported book, then open the lyrics-style
    # transcript screen and confirm the lines render and are seekable.
    if IMPORT_FILE and SUBTITLE_FILE and ok:
        title = os.path.splitext(os.path.basename(IMPORT_FILE))[0]
        try:
            # The book tile's overflow menu button (its tooltip is "Show menu").
            click_button("Show menu")
            page.wait_for_timeout(1000)
            with page.expect_file_chooser(timeout=8000) as fc:
                click_label("Add subtitles")  # a menuitem (aria-label set)
            fc.value.set_files(SUBTITLE_FILE)
            page.wait_for_timeout(4000)  # parse + store cues
            page.screenshot(path=f"{OUT}/subtitles_added.png")

            # Open the book (its tile is a group labelled with the title), then
            # the transcript from the player's app bar.
            click_label(title)
            page.wait_for_timeout(3000)
            click_button("Transcript")
            page.wait_for_timeout(3000)
            page.screenshot(path=f"{OUT}/transcript.png")

            transcript_text = all_semantics_text()
            if "transcript line one" in transcript_text.lower():
                print("transcript screen rendered the cues")
            else:
                print("FAIL: transcript lines did not render")
                ok = False

            # Tapping a line seeks there and starts playback.
            line = next(
                (e for e in page.query_selector_all('flt-semantics[role="button"]')
                 if "second line" in (e.text_content() or "").lower()),
                None,
            )
            if line is not None:
                line.click(force=True)
                page.wait_for_timeout(2000)
                page.screenshot(path=f"{OUT}/transcript_seek.png")
                print("tapped a transcript line to seek")
            else:
                print("FAIL: could not find a transcript line to tap")
                ok = False

            # Search the transcript, then jump from a match.
            click_button("Search")
            page.wait_for_timeout(1500)
            page.keyboard.type("second", delay=60)
            page.wait_for_timeout(2000)
            page.screenshot(path=f"{OUT}/transcript_search.png")
            results = all_semantics_text().lower()
            if "second line" in results and "match" in results:
                print("transcript search filtered to matches")
            else:
                print("FAIL: transcript search did not filter")
                ok = False
            result = next(
                (e for e in page.query_selector_all('flt-semantics[role="button"]')
                 if "second line" in (e.text_content() or "").lower()),
                None,
            )
            if result is not None:
                result.click(force=True)
                page.wait_for_timeout(2000)
                page.screenshot(path=f"{OUT}/transcript_search_jump.png")
                print("jumped from a search result")
            else:
                print("FAIL: no search result to tap")
                ok = False
        except Exception as e:
            print("FAIL: transcript flow error:", e)
            ok = False

    video = page.video
    context.close()  # flushes the recording
    if VIDEO_DIR and video:
        dest = os.path.join(VIDEO_DIR, "audix-web-smoke.webm")
        try:
            video.save_as(dest)
            print("VIDEO:", dest)
        except Exception as e:
            print("video save failed:", e)
    browser.close()

if errors:
    print("PAGE ERRORS:", errors)
    ok = False

print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
