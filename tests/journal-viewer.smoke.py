# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright==1.64.0"]
# ///
"""Browser smoke test of the journal viewer (viewer/), driven by the keyboard, against a running `kit serve`.

Usage: uv run --script tests/journal-viewer.smoke.py URL RUN OTHER_RUN LARGE_RUN SCREENSHOT.png
       uv run --script tests/journal-viewer.smoke.py --install     (downloads the pinned Chromium, once)
A second screenshot, the text log with a focused row, goes next to the first as viewer-log-focus.png.
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

        def retried(assertion):
            """A state the page reaches in time (a retried Playwright assertion: the page's policy forbids the eval a
            wait_for_function needs), as (ok, detail) for check()."""
            try:
                assertion()
                return True, ""
            except AssertionError as e:
                return False, str(e).strip().splitlines()[0]

        def counted(locator, n):
            return retried(lambda: expect(locator).to_have_count(n))

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
        check("the Play button says Pause, with no pressed state on top of its label",
              page.locator("#play").text_content() == "Pause" and page.locator("#play").get_attribute("aria-pressed") is None)
        check("the clock and the tokens, rewritten every frame, are not live regions",
              page.locator("#clock").get_attribute("aria-live") == "off" and page.locator("#spent").get_attribute("aria-live") == "off")
        for _ in range(3):
            page.keyboard.press(">")
        check("> speeds up to 8×", page.input_value("#speed") == "8")
        page.wait_for_selector('#stage[data-state="ended"]', timeout=30000)
        check("the replay reaches the end, every mark drawn", page.locator(".mark:not(.drawn)").count() == 0)
        check("the tokens add up to the run's total", page.locator("#spent").text_content() == "33k in · 5.9k out · 91k cache",
              page.locator("#spent").text_content())
        check("the scrubber reads as the clock", page.locator("#scrub").get_attribute("aria-valuetext") == page.locator("#clock").text_content(),
              str(page.locator("#scrub").get_attribute("aria-valuetext")))
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
        reasoned = next(e["i"] for e in run["events"] if e["d"].get("reasoning"))
        page.keyboard.press("Home")
        for _ in range(reasoned + 1):
            page.keyboard.press("ArrowRight")
        page.keyboard.press("Enter")
        page.wait_for_selector("#panel summary")
        page.focus("#panel summary")
        page.keyboard.press("Enter")
        check("Enter on the reasoning's summary opens it", page.locator("#panel details[open]").count() == 1)
        page.keyboard.press("Space")
        check("... and Space closes it", page.locator("#panel details[open]").count() == 0)
        page.keyboard.press("Escape")

        print("detail, views, text log")
        page.keyboard.press("End")
        page.locator(".t-agent-return").first.click()
        page.wait_for_selector("#panel:not([hidden])")
        check("a click on a mark opens its detail", "returns" in page.locator("#panel .label").text_content())
        lanes = {lane["id"]: lane for lane in run["lanes"]}
        returns = [e for e in run["events"] if e["type"] == "agent.return"]
        planner = lanes[returns[0]["from"]]["wrote"]
        check("an agent's return lists what it wrote, a file of the run as a button",
              page.locator("#panel .wrote li").all_text_contents() == [w["path"] for w in planner]
              and page.locator("#panel .wrote button").count() == sum(1 for w in planner if w["file"]),
              str(page.locator("#panel .wrote li").all_text_contents()))
        page.locator("#panel .wrote button").first.click()
        page.wait_for_selector("#panel .file-view:not([hidden])")
        check("... which opens it in the panel", "paginate the teams list" in page.locator("#panel .file-view").text_content())
        page.keyboard.press("Escape")
        page.keyboard.press("End")   # the click moved the playhead back: a mark not drawn yet has no shaft to click
        page.locator(".t-agent-return").nth(1).click()
        builder = lanes[returns[1]["from"]]["wrote"]
        check("... and a file outside the run as plain text",
              page.locator("#panel .wrote code").all_text_contents() == [w["path"] for w in builder if not w["file"]] != []
              and page.locator("#panel .wrote button").count() == 0, str(builder))
        page.locator(".t-agent-return").first.click()
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
        check("L shows the same events as text, minus what the view hides", *counted(page.locator("#log li"), len(run["events"]) - tools))
        page.keyboard.press("1")
        check("the text log has one row per event", *counted(page.locator("#log li"), len(run["events"])))
        check("... and one current row", page.locator("#log li[aria-current]").count() == 1)
        page.focus("#help-open")
        page.keyboard.press("Tab")   # onto the first row: a row clips what it paints outside itself (content-visibility)
        ring = page.locator("#log li").first.locator("button").evaluate(
            "(b) => { const s = getComputedStyle(b); return [b === document.activeElement && b.matches(':focus-visible'),"
            " s.outlineStyle, parseFloat(s.outlineWidth), parseFloat(s.outlineOffset)]; }")
        check("Tab onto a log row draws its focus ring inside the button",
              ring[0] and ring[1] != "none" and ring[2] > 0 and ring[2] + ring[3] <= 0, str(ring))
        page.mouse.move(0, 0)   # no hovered row in the picture
        page.screenshot(path=os.path.join(os.path.dirname(shot), "viewer-log-focus.png"))
        page.evaluate("document.activeElement.blur()")
        page.keyboard.press("Home")
        page.keyboard.press("Space")
        page.wait_for_timeout(400)
        page.keyboard.press("Space")
        marked = page.locator("#log li[aria-current]")
        check("played in the text log, one row is current: the event the playhead is on",
              marked.count() == 1 and marked.get_attribute("data-i") == stage.get_attribute("data-index") != "-1",
              f'{marked.count()} {stage.get_attribute("data-index")}')
        page.keyboard.press("l")
        page.keyboard.press("3")
        heights = page.evaluate("[...document.querySelectorAll('.head')].map((h) => [h.dataset.lane, h.offsetHeight])")
        tall = dict(heights)
        check("the tokens view sizes a lane by what it spent", tall["session"] > tall["agent:a-fix-1"] > 0 and tall["you"] == 18, str(heights))
        page.keyboard.press("4")
        check("the workflow view shows the steps of the plan", page.locator("rect.step").count() == len(run["steps"]) == 3)
        page.keyboard.press("1")
        turn = max((e for e in run["events"] if e["type"] == "model.turn"), key=lambda e: e["dur"])
        page.focus(".diagram .scroll")
        page.keyboard.press("0")
        size = "[document.querySelector('.diagram .scroll').clientWidth, +document.querySelector('.diagram .canvas').getAttribute('width')]"
        for _ in range(20):   # zoom in until a screen is less than a third of the longest model turn
            seen, canvas = page.evaluate(size)
            zoom = (canvas - 24) / run["time"]["width"]
            if seen / zoom < turn["dur"] / 3:
                break
            page.keyboard.press("+")
        page.evaluate("(x) => { document.querySelector('.diagram .scroll').scrollLeft = x; }",
                      12 + (turn["u"] + turn["dur"] / 2) * zoom - seen / 2)
        page.wait_for_timeout(200)
        check("zoomed into the middle of a long model turn, its bar is still drawn",
              page.locator(f'.diagram .mark.bar[data-i="{turn["i"]}"]').count() == 1, f"screen {seen / zoom:.0f} ms of {turn['dur']}")
        page.keyboard.press("0")
        page.focus("#home")
        page.keyboard.press("Enter")
        page.wait_for_timeout(200)
        check("Enter on the home link goes back to the list", page.locator("#picker").is_visible() and page.locator("#stage").is_hidden())

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
        # once the buckets widen (a run zoomed out), a question and a refusal on the same lanes are one mark
        shapes = page.evaluate("""async (id) => {
            const { Diagram } = await import('/diagram.js');
            const run = await (await fetch('/api/runs/' + id)).json();
            const guards = run.events.filter((e) => e.type === 'guard' && e.from === 'session').map((e) => e.i);
            const box = document.createElement('div');
            document.body.append(box);
            const d = new Diagram(box, run, () => {});
            d.layout();
            const shapes = [...d.node({ kind: 'arrow', type: 'guard', from: 'session', to: 'guard', x: 0, width: 0, events: guards })
              .querySelectorAll('.cross, .ring')].map((n) => n.getAttribute('class'));
            box.remove();
            return [guards.map((i) => run.events[i].d.decision), shapes];
        }""", large_id)
        check("a guard mark that stands for a question then a refusal shows the refusal's cross",
              shapes == [["ask", "deny"], ["cross"]], str(shapes))
        page.keyboard.press("+")
        page.keyboard.press("+")
        nodes = page.evaluate("document.querySelectorAll('.diagram .marks *').length")
        check("... zoomed in too: only what is near the window is in the page", 0 < nodes <= 1500, str(nodes))

        print("reduced motion, forced colours, narrow window")
        calm = watch(browser.new_page(viewport={"width": 1280, "height": 800}, reduced_motion="reduce"))
        calm.goto(f"{base}/#run={run_id}")
        calm.wait_for_selector(".diagram .mark", state="attached")
        calm.focus(".diagram .scroll")
        calm.keyboard.press("Space")   # right after opening: the playhead is at the end
        calm_stage = calm.locator("#stage")
        check("with reduced motion, Space starts over from the first event and nothing animates",
              calm_stage.get_attribute("data-index") == "0" and calm_stage.get_attribute("data-state") == "paused",
              f'{calm_stage.get_attribute("data-index")} {calm_stage.get_attribute("data-state")}')
        calm.keyboard.press("Space")
        check("... then advances one event at a time", calm_stage.get_attribute("data-index") == "1",
              calm_stage.get_attribute("data-index"))
        contrast = watch(browser.new_page(viewport={"width": 1280, "height": 800}, forced_colors="active"))
        contrast.goto(f"{base}/#run={run_id}")
        contrast.wait_for_selector(".diagram .mark", state="attached")
        contrast.keyboard.press("l")
        current = contrast.locator("#log li[aria-current] > button")
        found = retried(lambda: expect(current).to_have_count(1))
        check("in forced colours, where a shadow is not drawn, the current row of the text log keeps a mark",
              found[0] and current.evaluate("(b) => getComputedStyle(b).outlineStyle") != "none", found[1])
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
