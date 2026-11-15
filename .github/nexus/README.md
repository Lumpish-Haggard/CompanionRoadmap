# Nexus Mods page

The text of the mod's page on Nexus Mods:

- `description.bbcode`: the full description, in Nexus BBCode (the same text you would paste into the page editor).
- `summary.txt`: the short summary shown on mod tiles and at the top of the page (at most 350 characters, one paragraph).

[`nexus-release.yml`](../workflows/nexus-release.yml) publishes them when a release is published:

- the description, if it changed since the previous release (and only if the live text differs);
- the summary, if it changed since the previous release. The API cannot read the live summary back, so it is never sent blind: not on the release that first added `summary.txt`, only after a real change, or by hand.

To update the page without a new release, run the workflow from the Actions tab with *page only* and the ref `main`.

Before replacing the description, the workflow saves the text that was live on Nexus as a run artifact (`nexus-page-before`): `description.bbcode` is ready to paste back, and `description.raw.bbcode` is exactly what Nexus stored. Nexus keeps the description the way its page editor saves it, so this file follows the editor's layout (for example `[size]` and `[color]` inside each list item). Edit the page here rather than on the website, or copy website edits back into this file: otherwise the next update overwrites them.
