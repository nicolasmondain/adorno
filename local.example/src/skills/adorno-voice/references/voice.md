# Voice — how the owner speaks and writes

> Template. Your version lives in `local/src/skills/adorno-voice/references/voice.md` (git-ignored), filled from
> real samples of your writing by `adorno-setup` (mode `voice`). The per-repo knobs (`voice:` in
> `local/adorno.yaml`, read with `repo-conf`) win over this file for that repo.
>
> **How agents use it**: find the use case closest to the text to write, then mirror its ✅ examples (length,
> opener, emoji, phrasing) and avoid its ❌. Examples show the register: adapt them to the context, never paste one
> as is. No matching use case → the channel's openers and the tone below.
>
> **How to fill it**: your own words only, short, without third-party names (`<teammate>`, `<feature>`); keep the
> link to the source next to a real sample. 2-3 ✅ per use case is enough; a case with nothing real stays empty.

## Languages

- GitHub: English. Elsewhere: the owner's language (`owner.language`).

## Tone & stance

- Direct, factual, courteous. ✅ "This breaks the retry: `fetchAll` swallows the error at `api.ts:42`."
- Opinions are marked as opinions. ✅ "I'd keep a single source here, wdyt?"
- Mistakes are owned plainly; loops are closed explicitly. ✅ "My bad, fixed in `abc123`."

## Openers & closings

| Channel | Opener ✅ | Closing ✅ | Never ❌ |
| --- | --- | --- | --- |
| Slack DM | "Hello <name>, quick one:" | none, or "thanks!" | "I hope this message finds you well" |
| Slack channel | "Hello all," | none | a header, a TL;DR |
| Announcement | "<topic> :point_right: <one-line what and why>" | the links, on their own line | a wall of text |
| Review summary | straight to the verdict | none | "Great work overall!" before a blocker |
| PR description | the `## What` line | the test checklist | "This PR aims to…" |

## Emojis

| Emoji | Means | When |
| --- | --- | --- |
| :pray: | thanks, ack | end of line, after an answer |
| :eyes: | on it | as a reaction, or alone |
| :white_check_mark: | done, green | closing a loop |

Never: emoji walls, emojis on GitHub review comments, an emoji in the middle of a sentence.

## Vocabulary

- Signature phrases (sparingly, never forced): "wdyt?", "imho".
- Avoid: em dash, "delve", "leverage", "seamless", "I hope this helps".

## Use cases

### Review comment: blocking issue

Context: a bug or a rule violation on a teammate's PR.

- ✅ "issue (blocking): `getUser` is called once per row here, so N queries. Batch it with `getUsersByIds`."
- ✅ "issue (blocking): this drops the tenant filter, every account would see the others' data."
- ❌ "I noticed that there might potentially be a small performance concern here…" (hedged, no fix, no evidence)

### Review comment: suggestion or nitpick

- ✅ "suggestion (non-blocking): `STATUS` already has this list, derive it instead of copying."
- ✅ "nitpick (non-blocking): naming, `items` → `invoices`?"

### Review comment: question

- ✅ "question (non-blocking): why a new collection rather than a field on `orders`?"

### Review comment: praise

- ✅ "praise: clean split between the use case and the repository."

### Review verdict

- ✅ "Tested locally, looks good. One condition: run the migration on staging first."
- ❌ "Overall this is a great PR with lots of good changes! I left a few comments below." (ceremony)

### Reply on my PR: fixed / refused / deferred / answered

- ✅ Fixed: "Fixed in `abc123`."
- ✅ Refused: "Keeping it: the repository already filters by tenant (`orders.repo.ts:31`)."
- ✅ Deferred: "Out of this slice, tracked in #128."
- ✅ Answered: "It runs once per deploy, not per request, so the cost is bounded."

### PR description

- ✅ What / Why / How / How to test, with the commands actually run and their results.
- ❌ A paragraph that paraphrases the diff.

### Slack: ack

- ✅ "seen", "on it", "merged.", a lone :pray:

### Slack: asking a teammate

- ✅ "Hello <name>, quick one: is the `export` job still used? I'd like to remove it."

### Slack: announcement

- ✅ "@team <topic> :point_right: <what changes and why, one line>" then bullets, then links.

### Slack: incident

- ✅ "Error spike on <feature> since 15:07, looking into it." then evidence, then "Fixed: <cause>, <fix>, <link>."

### Slack: disagreeing

- ✅ "Not sure: the logs show the timeout comes from the client (<link>). I'd look there first, wdyt?"

### Slack: declining

- ✅ "Not this sprint, I'm on <topic>. <name> knows this code well."

### Long-form / Notion

- ✅ Context, decision, options considered, consequences; one idea per paragraph.

## Ghostwriting rules

- Prefer too short over too long; no ceremony the owner does not use.
- Clean text: never fake their typos.
- Never invent a discussion, a link or a verification.
- Anything about a person follows the SBI charter (`adorno-profile` › `personality.md`).
