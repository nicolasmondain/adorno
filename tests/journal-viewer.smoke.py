# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright==1.64.0"]
# ///
"""Browser smoke test of the journal viewer (viewer/), driven by the keyboard, against a running `kit serve`.

Usage: uv run --script tests/journal-viewer.smoke.py URL RUN OTHER_RUN LARGE_RUN SCREENSHOT.png
       uv run --script tests/journal-viewer.smoke.py --install     (downloads the pinned Chromium, once)
Exit: 0 every check passed, 1 a check failed, 77 no browser to run them in (tests/journal-viewer.test.sh says so).
The one place where the Playwright version is pinned; the test runs it with `uv run --offline`, so nothing is
downloaded behind your back.
"""
import json
import os
import subprocess
import sys
import urllib.request

NO_BROWSER = 77
passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def api(base, path):
    with urllib.request.urlopen(base + path) as response:
        return json.load(response)


def main(argv):
    if argv == ["--install"]:
        extra = ["--with-deps"] if os.environ.get("GITHUB_ACTIONS") and sys.platform.startswith("linux") else []
        return subprocess.run([sys.executable, "-m", "playwright", "install", *extra, "chromium"]).returncode
    if len(argv) != 5:
        print(__doc__, file=sys.stderr)
        return 2
    base, run_id, other_id, large_id, shot = argv
    try:
        from playwright.sync_api import Error, expect, sync_playwright
    except ImportError:
        return NO_BROWSER
    run = api(base, f"/api/runs/{run_id}")
    with sync_playwright() as pw:
        try:
            browser = pw.chromium.launch()
        except Error as e:
            print(f"no browser: {str(e).splitlines()[0]}", file=sys.stderr)
            return NO_BROWSER
        problems, elsewhere = [], []

        def watch(page):
            page.on("console", lambda m: problems.append(m.text) if m.type == "error" else None)
            page.on("pageerror", lambda e: problems.append(str(e)))
            page.on("request", lambda r: None if r.url.startswith(base) else elsewhere.append(r.url))
            return page

        page = watch(browser.new_page(viewport={"width": 1280, "height": 800}))
        stage = page.locator("#stage")

        print("the runs")
        page.goto(base + "/")
        page.wait_for_selector("table.runs tbody tr")
        check("the page lists the runs", page.locator("table.runs tbody tr").count() >= 3)
        page.select_option('[data-filter="outcome"]', "open")
        check("a filter narrows the list", page.locator("table.runs tbody tr").count() == 2,
              str(page.locator("table.runs tbody tr").count()))
        page.select_option('[data-filter="outcome"]', "")
        page.focus(f'tr[data-run="{run_id}"] button.open')
        page.keyboard.press("Enter")
        page.wait_for_selector(".diagram .mark", state="attached")

        print("the diagram")
        check("one lane per actor", page.locator(".head").count() == len(run["lanes"]), str(page.locator(".head").count()))
        check("each fix round is framed", page.locator("rect.round").count() == len(run["rounds"]) == 2)
        check("the last round is marked", page.locator("rect.round.last").count() == 1)
        check("the owner's decision is a red disc on their lane", page.locator(".t-checkpoint .disc").count() == 1)
        check("the guard's refusal is a cross, its question a ring",
              page.locator(".t-guard .cross").count() == 1 and page.locator(".t-guard .ring").count() == 1)
        check("the idle gap is drawn as a break, with its real length",
              page.locator("rect.gap").count() >= 1 and "12 min" in page.locator(".gap-label").first.text_content())
        check("on arrival the whole run is drawn", page.locator(".mark:not(.drawn)").count() == 0
              and stage.get_attribute("data-state") == "ended")
        page.screenshot(path=shot, full_page=True)

        print("playback, keyboard only")
        page.focus(".diagram .scroll")
        page.keyboard.press("Space")
        page.wait_for_selector('#stage[data-state="playing"]')
        check("Space plays from the start", page.locator(".mark:not(.drawn)").count() > 0)
        for _ in range(3):
            page.keyboard.press(">")
        check("> speeds up to 8×", page.input_value("#speed") == "8")
        page.wait_for_selector('#stage[data-state="ended"]', timeout=30000)
        check("the replay reaches the end, every mark drawn", page.locator(".mark:not(.drawn)").count() == 0)
        check("the tokens add up to the run's total", page.locator("#spent").text_content() == "33k in · 5.9k out · 91k cache",
              page.locator("#spent").text_content())
        page.keyboard.press("Home")
        check("Home goes back to the start: nothing drawn", page.locator(".mark.drawn").count() == 0
              and stage.get_attribute("data-index") == "-1")
        for _ in range(3):
            page.keyboard.press("ArrowRight")
        check("→ steps one event at a time", stage.get_attribute("data-index") == "2", stage.get_attribute("data-index"))
        check("the current event is announced", page.locator("#live").text_content() == run["events"][2]["label"])
        page.keyboard.press("Enter")
        page.wait_for_selector("#panel:not([hidden])")
        check("Enter opens the detail of the current event", page.locator("#panel .label").text_content() == run["events"][2]["label"])
        check("focus moves into the detail", page.evaluate("document.activeElement.closest('#panel') !== null"))
        page.keyboard.press("Escape")
        check("Esc closes it and gives the focus back to the diagram",
              page.locator("#panel").is_hidden() and page.evaluate("document.activeElement.classList.contains('scroll')"))
        page.keyboard.press("]")
        check("] jumps to the next step", int(stage.get_attribute("data-index")) > 2, stage.get_attribute("data-index"))

        print("detail, views, text log")
        page.keyboard.press("End")
        page.locator(".t-agent-return").first.click()
        page.wait_for_selector("#panel:not([hidden])")
        check("a click on a mark opens its detail", "returns" in page.locator("#panel .label").text_content())
        page.locator("#panel .files button", has_text="plan.md").click()
        page.wait_for_selector("#panel .file-view:not([hidden])")
        check("a file of the run opens as text in the panel", "paginate the teams list" in page.locator("#panel .file-view").text_content())
        page.keyboard.press("Escape")
        tools = sum(1 for e in run["events"] if e["type"] == "tool.call")
        x_before = page.locator(".t-agent-spawn .shaft").first.get_attribute("x1")
        page.keyboard.press("2")
        check("the agents-only view hides the tool calls and moves nothing",
              page.locator(".mark.t-tool-call").count() == 0 and page.locator(".t-agent-spawn .shaft").first.get_attribute("x1") == x_before)
        page.keyboard.press("l")
        expect(page.locator("#log li")).to_have_count(len(run["events"]) - tools)  # a retried count: the page's policy forbids eval
        check("L shows the same events as text, minus what the view hides", True)
        page.keyboard.press("1")
        expect(page.locator("#log li")).to_have_count(len(run["events"]))
        check("the text log has one row per event", page.locator("#log li[aria-current]").count() == 1)
        page.keyboard.press("l")
        page.keyboard.press("3")
        heights = page.evaluate("[...document.querySelectorAll('.head')].map((h) => [h.dataset.lane, h.offsetHeight])")
        tall = dict(heights)
        check("the tokens view sizes a lane by what it spent", tall["session"] > tall["agent:a-fix-1"] > 0 and tall["you"] == 18, str(heights))
        page.keyboard.press("4")
        check("the workflow view shows the steps of the plan", page.locator("rect.step").count() == len(run["steps"]) == 3)
        page.keyboard.press("1")

        print("two runs")
        page.goto(f"{base}/#run={run_id}&b={other_id}")
        expect(page.locator(".diagram")).to_have_count(2)
        check("two runs are drawn one next to the other, with what differs", page.locator(".delta tbody tr").count() == 8)
        page.goto(f"{base}/#run={other_id}")
        expect(page.locator(".diagram")).to_have_count(1)
        page.wait_for_selector(".diagram .badge.open")
        check("an open run says so, and that its steps are derived",
              "still open" in page.locator("#note").text_content() and "derived" in page.locator("#note").text_content())
        check("an agent seen without its spawn is marked", page.locator(".head.orphan").count() == 1)

        print("a large run")
        page.goto(f"{base}/#run={large_id}")
        page.wait_for_selector(f'.diagram[data-run="{large_id}"] .mark', state="attached")
        nodes = page.evaluate("document.querySelectorAll('.diagram .marks *').length")
        check("thousands of events stay within the drawing budget", 0 < nodes <= 1500, str(nodes))
        page.keyboard.press("+")
        page.keyboard.press("+")
        nodes = page.evaluate("document.querySelectorAll('.diagram .marks *').length")
        check("... zoomed in too: only what is near the window is in the page", 0 < nodes <= 1500, str(nodes))

        print("reduced motion, narrow window")
        calm = watch(browser.new_page(viewport={"width": 1280, "height": 800}, reduced_motion="reduce"))
        calm.goto(f"{base}/#run={run_id}")
        calm.wait_for_selector(".diagram .mark", state="attached")
        calm.focus(".diagram .scroll")
        calm.keyboard.press("Home")
        calm.keyboard.press("Space")
        calm_stage = calm.locator("#stage")
        check("with reduced motion, Space advances one event and nothing animates",
              calm_stage.get_attribute("data-index") == "0" and calm_stage.get_attribute("data-state") == "paused")
        small = watch(browser.new_page(viewport={"width": 480, "height": 800}))
        small.goto(f"{base}/#run={run_id}")
        small.wait_for_selector("#log li")
        check("on a narrow window the text log comes first", small.locator("#diagrams").is_hidden())
        check("... and the page never scrolls sideways",
              small.evaluate("document.documentElement.scrollWidth <= window.innerWidth"),
              str(small.evaluate("[document.documentElement.scrollWidth, window.innerWidth]")))

        print("hygiene")
        check("no error in the console, the content policy included", not problems, "; ".join(problems[:3]))
        check("nothing was asked from another origin", not elsewhere, "; ".join(elsewhere[:3]))
        browser.close()
    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
