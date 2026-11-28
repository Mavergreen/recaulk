# Release notes

The generator (`release-notes.sh`, from mavericks-shipyard) writes the notes file for every
release: the title, a "What changed" section, a "Build ingredients" section when a pin moved,
and the footer. That file becomes both the Sparkle appcast `<description>` and the GitHub
Release body -- the same bytes, read twice.

Every release that changes more than pins commits its notes before it publishes, under the tag
`release-version.sh --product recaulk` derives at the commit being released:
`release-notes/<tag>/changes/<slug>`, one file per change, slug `[a-z0-9-]+`, a sentence or two
for someone who uses Recaulk. A pins-only release (UPSTREAM_VERSION, components/*/version or
other declared state alone) needs none. The publish refuses a release whose notes are missing.

The `<full-version>.md` files here are the older hand-written prose for releases already
published; new releases don't add them.
