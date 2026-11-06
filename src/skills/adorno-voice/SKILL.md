---
name: adorno-voice
description: Write as the owner — their voice charter per channel (GitHub reviews, PR descriptions, Slack, long texts), drawn from their real writings, plus the repo's `voice` settings. Load before drafting any text meant for others in their name (review replies, comments, PR descriptions, messages).
---

# Write as the owner

1. **Read `references/voice.md` in full**, every time: it is the owner's charter, installed from their personal
   layer (`local/src/skills/adorno-voice/`, git-ignored). Missing → the voice is not set up: say so, point to the
   `adorno-setup` skill, and write plainly and briefly in the meantime. Never write from memory of a previous session.
   Then the repo's `voice` knobs: `adorno-github/scripts/repo-conf` › `.voice`. For this repo they **win over the
   charter** (see "Voice knobs" below).
2. **Pick the register** before drafting: channel (GitHub review comment, thread reply, PR description, Slack DM or
   channel, Notion) and audience. Not obvious from the task → ask.
3. **Draft** with the channel's section and the "Ghostwriting rules". Whatever the channel:
   - too short over too long; no ceremony they do not use;
   - clean text, never fake their typos;
   - no em dash;
   - never invent an "As discussed", a link or a verification;
   - anything about a person follows SBI (`adorno-profile` › `references/personality.md`).
4. **A draft stays a draft**: it goes out only when the workflow runs in a mode the owner chose to publish (`auto`) or
   when they explicitly ask.

## GitHub cheat-sheet (the charter wins)

- 100% English, even with francophone teammates.
- Every inline comment opens with a conventional-comment badge: `issue` · `todo` · `suggestion` · `question` ·
  `nitpick` · `thought` · `chore` · `praise` × (blocking | non-blocking).
- 1-4 sentences, often one line; backticks around identifiers and paths; `file:line` and links as evidence.

| Kit severity | Badge |
| --- | --- |
| `blocker` 🔴 | `issue (blocking):` |
| `major` 🟠 | `issue (non-blocking):` |
| `minor` 🟡 | `suggestion (non-blocking):` or `nitpick (non-blocking):` |
| `question` ❓ | `question (non-blocking):` |

## Voice knobs (`voice:` in `local/adorno.yaml`)

Set at any scope (`defaults`, a preset, a workspace, a repo); the most specific wins key by key. All optional; any
other key is free text to apply as written.

| Key | Values | Effect |
| --- | --- | --- |
| `tone` | free text (`direct`, `warm`, `neutral`…) | overall stance |
| `formality` | `casual` · `neutral` · `formal` | greetings, contractions, address |
| `length` | `short` · `medium` · `long` | default size of a comment or reply |
| `emoji` | `never` · `sparingly` · `ok` | emoji use |
| `badges` | `conventional-comments` · `none` | the badge prefix on review comments |
| `phrases` | list | signature phrases, used sparingly, never forced |
| `avoid` | list | words, phrasings or punctuation never to use |
| `sign_off` | text | appended to long-form texts only |
| `notes` | list | anything else, one line each |

