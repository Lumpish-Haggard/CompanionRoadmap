# Reference data (optional)

Nothing in this project needs a reference database. The mod, the validator, the tests and the build all work without one. This page exists so that contributors who keep offline notes of their own know the rules.

## What the project relies on

1. **The game's own files**, read from your own install by `tools/extract_game_data.py`. They are the source of truth for every flag, journal step and story condition.
2. **What can be seen in game**: your own test, or a report file from a real save (see `tests/fixtures/`).
3. **Published references** such as a wiki page, a guide or a video, read the normal way and linked in your pull request. They are used to cross-check and to explain, never as a source of text.

## If you keep an offline reference

Some contributors like to keep reference material in a local database so they can search it while they work. That is private tooling, and it is entirely up to you. This project:

- does **not** provide such a database,
- does **not** provide, and will not accept, tools that copy websites,
- does **not** ask anyone to bulk-download, crawl or scrape a site.

If you want offline reference material, obtain it in a way its source allows: use an official export or dump where one is offered, ask the people who run the site, or build your own notes from your own play and your own copy of the game. Follow the source's terms of use, its robots rules and its licence, and do not put load on community-run sites.

## Rules for any reference material

- **It stays on your machine.** Keep it in `data/`, which is git-ignored. Never commit it, never attach it to an issue or pull request, and never put it in the `.pak`.
- **Its text is never copied** into the guide, the code, comments or commit messages. Guide text is written in our own words (see [DATA_FORMAT.md](DATA_FORMAT.md)). A reference tells you what is true, not how to say it. Community wikis are usually published under share-alike and often non-commercial licences, which is one more reason their text does not belong in a mod.
- **The game files win.** When a reference and the game data disagree, the game data stands until someone shows otherwise in game.
- **Say where a fact came from** in your pull request. A link to the page you read is enough.

## A layout that works well

If you build one, a single SQLite file is enough: one row per article or note, plus a full-text index.

```sql
CREATE TABLE pages (
    title         TEXT NOT NULL,   -- name of the article or note
    content       TEXT NOT NULL,   -- its text
    categories    TEXT,            -- optional: JSON array of tags
    url           TEXT,            -- optional: where it can be read online
    last_modified TEXT             -- optional: ISO date of the version you hold
);

-- Full-text index; keep its rowid equal to pages.rowid.
CREATE VIRTUAL TABLE pages_fts USING fts5(title, content, categories, tokenize = 'porter unicode61');
```

Querying it (read-only) from Python:

```python
import sqlite3

con = sqlite3.connect("file:data/reference.db?mode=ro", uri=True)
rows = con.execute(
    """
    SELECT p.title, p.url, snippet(pages_fts, 1, '[', ']', ' ... ', 20)
    FROM pages_fts
    JOIN pages p ON p.rowid = pages_fts.rowid
    WHERE pages_fts MATCH ?
    ORDER BY rank
    LIMIT 5
    """,
    ("night orchid",),
)
for title, url, snippet in rows:
    print(f"{title}: {snippet}")
```

Use what you find to decide what to check in the game files, then cite the page you read.
