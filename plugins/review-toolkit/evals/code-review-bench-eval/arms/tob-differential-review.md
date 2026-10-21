spawn: claude
allow: Read,Grep,Glob,Skill,Write,Bash(git *),Bash(find *),Bash(grep *),Bash(wc *),Bash(ls *)
requires-plugin: differential-review@trailofbits
upstream: https://github.com/trailofbits/skills plugins/differential-review @ 123037ec8aed26f0d86327cc39137ee5043e5deb
---
{rules}

Review the change with the `differential-review` skill from the installed `differential-review`
plugin (invoke the skill; do not improvise its method). Follow it through every phase it routes you
to, including its adversarial step, performed by you. Write its full markdown report under
`{scratch}` instead of where it says. Then write to `{out}` each finding of that report as one
numbered review comment, in the output form above.
