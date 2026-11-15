# Nexus Mods page

The text of the mod's page on Nexus Mods:

- `description.bbcode`: the full description, in Nexus BBCode (the same text you would paste into the page editor).
- `summary.txt`: the short summary shown on mod tiles and at the top of the page (at most 350 characters, one paragraph).

[`nexus-release.yml`](../workflows/nexus-release.yml) publishes them. When a release is published, the page is updated if either file changed since the previous release. To update the page without a new release, run the workflow from the Actions tab with *page only*.

Before replacing the description, the workflow saves the text that was live on Nexus as a run artifact (`nexus-page-before`), so an edit made by hand on the website can be recovered. Edit the page here rather than on the website, or copy website edits back into these files: otherwise the next update overwrites them.
