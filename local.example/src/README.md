# local/src — your private src/

Same tree as `src/`; each file here replaces (or adds) the public file at the same path on install.
The profile, the voice and the summary exist **only** here: the public repo ships none of them. The files in this
template are starting points; the `adorno-setup` skill (`profile` mode) helps you write your own.

| To… | Write |
| --- | --- |
| your profile (principles, method, identity) | `skills/adorno-profile/references/{personality,engineering-types,engineering-scale,process}.md` |
| your writing style | `skills/adorno-voice/references/voice.md` |
| your always-on summary | `instructions/20-owner.md` |
| one more private instruction | `instructions/NN-topic.md` |
| a private agent, workflow or skill | `agents/<type>/<specialty>.md`, `workflows/<domain>/<action>.md`, `skills/<name>/SKILL.md` |

A `skills/<name>/` folder without `SKILL.md` is laid over the public skill of the same name, file by file; with a
`SKILL.md`, it also replaces its description and body.
