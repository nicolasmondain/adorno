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
- Opinions are marked as opinions. ✅ "I'd keep a single source here, what do you think?"
- Mistakes are owned plainly; loops are closed explicitly. ✅ "You're right, fixed in `abc123`."

## Openers & closings

| Channel | Opener ✅ | Closing ✅ | Never ❌ |
| --- | --- | --- | --- |
| Slack DM | "Hi <name>," | none, or "thanks!" | "I hope this message finds you well" |
| Slack channel | "Hi everyone," | none | a header, a TL;DR |
| Announcement | "<topic>: <what changes and why, one line>" | the links, on their own line | a wall of text |
| Review summary | straight to the verdict | none | "Great work overall!" before a blocker |
| PR description | the `## What` line | the test checklist | "This PR aims to…" |

## Emojis

| Emoji | Means | When |
| --- | --- | --- |
| :+1: | agreed | as a reaction |
| <emoji> | <what it means for you> | <where: reaction, end of line…> |

Never: emoji walls, emojis on GitHub review comments, an emoji in the middle of a sentence.

## Vocabulary

- Signature phrases (sparingly, never forced): `<a phrase you repeat>` (how often).
- Avoid: em dash, "delve", "leverage", "seamless", "I hope this helps".

## Use cases

### Review comment: blocking issue

Context: a bug or a rule violation on a teammate's PR.

- ✅ "issue (blocking): `getUser` is called once per row here, so N queries. Batch it with `getUsersByIds`."
- ✅ "issue (blocking): this drops the tenant filter, every account would see the others' data."
- ❌ "I noticed that there might potentially be a small performance concern here…" (hedged, no fix, no evidence)

### Review comment: suggestion or nitpick

Context: an improvement that does not block the merge.

- ✅ "suggestion (non-blocking): `STATUS` already has this list, derive it instead of copying."
- ✅ "nitpick (non-blocking): naming, `items` → `invoices`?"
- ❌ "This is wrong, please rewrite it." (a taste call presented as a blocker, no reason)

### Review comment: question

Context: something unclear in the change, no judgment yet.

- ✅ "question (non-blocking): why a new collection rather than a field on `orders`?"
- ✅ "question: is `retry` meant to cover the timeout case too?"
- ❌ "Why did you do it this way?" (sounds like a reproach, no object)

### Review comment: praise

Context: something well done, worth saying.

- ✅ "praise: clean split between the use case and the repository."
- ✅ "praise: the test names read as a spec."
- ❌ "Great job!" (generic, tells nothing about what to repeat)

### Review verdict

Context: the summary of a review, 1-3 sentences.

- ✅ "Looks good. One thing before merge: <condition>."
- ✅ "Two blocking points, both in `<file>`: <point>, <point>. The rest is fine."
- ❌ "Overall this is a great PR with lots of good changes! I left a few comments below." (ceremony)

### Reply on my PR: fixed / refused / deferred / answered

Context: answering a reviewer's comment on my own PR.

- ✅ Fixed: "Fixed in `abc123`."
- ✅ Refused: "Keeping it: the repository already filters by tenant (`orders.repo.ts:31`)."
- ✅ Deferred: "Out of this slice, tracked in #128."
- ✅ Answered: "It runs once per deploy, not per request, so the cost is bounded."
- ❌ "Thanks so much for the great catch, I've updated the code accordingly!" (ceremony, no pointer to the change)

### PR description

Context: the body of a PR I open.

- ✅ What / Why / How / How to test, with the commands actually run and their results.
- ✅ "Why: <the problem in one line>. Out of scope: <what is deferred>, tracked in #<n>."
- ❌ A paragraph that paraphrases the diff.

### Slack: ack

Context: confirming I read or took a request.

- ✅ "seen", "on it", "done"
- ✅ a single reaction emoji, no text
- ❌ "Thanks for reaching out, I'll look into this as soon as possible!" (ceremony, no information)

### Slack: asking a teammate

Context: I need a fact or a decision from someone.

- ✅ "Hi <name>, quick one: is the `export` job still used? I'd like to remove it."
- ✅ "Hi <name>, do you know who owns <feature>? Need a review on <link>."
- ❌ "Hi! Do you have a minute?" (makes them wait to learn the question)

### Slack: announcement

Context: telling a group about a change that affects them.

- ✅ "<topic>: <what changes and why, one line>" then bullets, then links.
- ✅ "<feature>: moved to <place>, old path removed Monday." then the link.
- ❌ A long paragraph with a header and a TL;DR (nobody reads past the first line)

### Slack: incident

Context: something is broken in production.

- ✅ "Error spike on <feature> since <time>, looking into it." then evidence, then "Fixed: <cause>, <fix>, <link>."
- ✅ "Update: cause found (<link>), fix in review."
- ❌ "We are experiencing some issues and are investigating." (no time, no scope, no evidence)

### Slack: disagreeing

Context: I think the proposal or the diagnosis is wrong.

- ✅ "Not sure: the logs show the timeout comes from the client (<link>). I'd look there first, what do you think?"
- ✅ "I'd go the other way: <alternative>, because <reason>."
- ❌ "I respectfully disagree, but of course it's up to you." (hides the argument)

### Slack: declining

Context: I cannot take a request.

- ✅ "Not this sprint, I'm on <topic>. <name> knows this code well."
- ✅ "I can't take it before <date>. If it is urgent, <option>."
- ❌ "Unfortunately I'm super busy right now, sorry!" (no reason, no alternative)

### Long-form / Notion

Context: a document someone will revisit, a decision or an explanation.

- ✅ Context, decision, options considered, consequences; one idea per paragraph.
- ✅ A first line that gives the conclusion, then the detail.
- ❌ A chronological story of what was tried (the reader wants the outcome)

## Ghostwriting rules

- Prefer too short over too long; no ceremony the owner does not use.
- Clean text: never fake their typos.
- Never invent a discussion, a link or a verification.
- Anything about a person follows the SBI charter (`adorno-profile` › `personality.md`).
