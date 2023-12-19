# New Alexandria Foundation Text Server

## Getting Started

So you've forked this repo, and you want to set up your own commentary. That's a reasonable approach, since we deliberately haven't enabled user accounts for this work.

You'll need to create a [TOML](https://toml.io/) file at the root of this repository called `commentary.toml`. Example configuration has been provided in `example_commentary.toml`.

The top level of the TOML file supports the following keys:

- `editions`: a list of `text` and/or `collection` objects to which your commentary refers
- `commentaries`: a list of `commentary` objects, pointing to the commentaries that you have written
- `translations`: a list of `translation` objects, pointing to translations that you have written

### `text` and `collection` objects

`text` objects refer to the critical texts on which your commentary relies. These are the primary source materials to which each of your comments should refer. 

You can refer to individual texts by pointing to a local file. You'll need to supply some information about the text to be ingested:

```toml
[[editions]]
name = "Periegesis"
file = "./priv/texts/greekLit/tlg0525/tlg0525.tlg001.perseus-grc2.xml"
urn = "urn:cts:greekLit:tlg0525.tlg001.perseus-grc2"
```

Instead of providing a `file` attribute, you can provide a `repository` or a `dir` attribute when you want to process entire collections:

```toml
[[editions]]
name = "Canonical Greek Literature"
repository = "https://github.com/PerseusDL/canonical-greekLit/"
urn = "urn:cts:greekLit"

[[editions]]
name = "Canonical Latin Literature"
dir = "./priv/texts/PerseusDL/canonical-latinLit/"
urn = "urn:cts:latinLit"
```

The main difference is that using the `repository` attribute will pull in every valid file found in the repository; the `dir` attribute allows you to curate the collection locally before parsing, so you only pull in the documents that you need.

In both cases, it is assumed that these repositories or directories will follow the [CapiTainS directory structure](http://capitains.org/pages/guidelines#directory-structure) --- they should have a `data` directory at the root of the repository, which can contain any number of subdirectories whose names should match the `textgroup`s to which they refer. 

Each `textgroup` subdirectory should contain a `__cts__.xml` [Textgroup Metadata File](http://capitains.org/pages/guidelines#textgroup-metadata-file) and any number of subdirectories referring to works within that textgroup.

Each `work` subdirectory should contain a `__cts__.xml` [Work Metadata File](http://capitains.org/pages/guidelines#work-metadata-file) detailing all of the TEI XML `version`s (editions, translations, and commentaries) of the given `work` that should be processed.

You can mix and match as needed:

```toml
[[texts]]
name = "Iliad"
file = "./priv/texts/greekLit/tlg0012/tlg0012.tlg001.perseus-grc2.xml"
urn = "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2"

[[texts]]
name = "Canonical Latin Literature"
dir = "./priv/texts/latinLit"
urn = "urn:cts:latinLit"
```

### `commentary` objects

Like a `text` object, a `commentary` object should point to a file and provide some additional information. At present, Open Commentaries should be able to handle commentaries in docx, markdown, and TEI XML. ("Should" because this is still very much beta software.)

Theoretically, we should be able to support any format that can be transformed into Pandoc's [AST](https://pandoc.org/using-the-pandoc-api.html), but for now we are aiming for full support of docx, markdown, and the subset of TEI commonly used for Perseus texts (which happens mostly to look like [EpiDoc](https://epidoc.stoa.org/)).

A `commentaries` array in the `commentary.toml` might look like the following:

```toml
[[commentaries]]
name = "A Pausanias Commentary in Progress"
file = "./priv/commentaries/tlg0525.tlg001.apcip-en.docx"
urn = "urn:cts:greekLit:tlg0525.tlg001.apcip-en"

[[commentaries.references]]
urn = "urn:cts:greekLit:tlg0525.tlg001.perseus-grc2"

[[commentaries.references]]
unr = "urn:cts:greekLit:tlg0525.tlg001.perseus-eng2"
```

Note the `references` attribute: each item in the `commentaries` array can have any number of items in its `references` sub-array, each of which has a `urn` pointing to a valid edition or translation.

Although the [CTS specification](https://www.degruyter.com/document/doi/10.1515/9783110599572-007/html?lang=en) treats a `commentary` as a child of a `work` (with potential `translation` and `edition` siblings), this was probably a mistake. Commentaries need to refer to specific `edition` versions of a text in order to properly resolve citations.

Any `references` that you provide should contain valid nodes for any citations in your commentary. This means that if you have a gloss on, e.g., _Agamemnon_ v. 288, you should be sure that v. 288 is valid for your gloss in any of the versions of `tlg0085.tlg005` that you cite.

### `translation` objects

Like `commentaries`, `translations` should reference the `edition` on which they are based. (If you do not know or if the information is not available, it might be best for now to treat the `translation` as another `edition` that happens to be in a different language than the original. This workaround is a consequence of the overloading of the `version` level of the CTS URN.)

```toml
[[translations]]
name = "A Pausanias Reader in Progress"
file = "./priv/translations/tlg0525.tlg001.aprip-en.docx"
urn = "urn:cts:greekLit:tlg0525.tlg001.aprip-en"
```

## Development

For now, enable S3 uploads by proxying the MinIO server with `fly proxy 9000`.

## What are we doing?

We have canonical texts that have been digitized, and we have people who have been writing commentaries in formats that are not compatible with these digital versions. How do we fit these two things together?

Digital preservation and presentation.

## Named Entity Recognition TODOs

- Smith's dictionaries for authority list for entities
- Loeb identifiers for Pausanias

## About the schema

We follow the [CTS URN spec](http://cite-architecture.github.io/ctsurn_spec/),
which can at times be confusing.

Essentially, every `collection` (which is roughly analogous to a git repository)
contains one or more `text_group`s. It can be helpful to think of each
`text_group` as an author, but remember that "author" here designates not a
person but rather a loose grouping of works related by style, content, and
(usually) language. Sometimes the author is "anonymous" or "unknown" --- hence
`text_group` instead of "author".

Each `text_group` contains one or more `work`s. You might think of these as
texts, e.g., "Homer's _Odyssey_" or "Lucan's _Bellum Civile_".

A `work` can be further specified by a `version` URN component that points to
either an `edition` (in the traditional sense of the word) or a `translation`.

So in rough database speak:

- A `version` has a type indication of one of `commentary`, `edition`, or `translation`
- A `version` belongs to a `work`
- A `work` belongs to a `text_group`
- A `text_group` belongs to a `collection`

In reverse:

- A `collection` has many `text_group`s
- A `text_group` has many `work`s
- A `work` has many `version`s,
  each of which is typed as `commentary`, `edition`, or `translation`

Note that the [CTS specification](http://cite-architecture.github.io/cts_spec/) allows for
an additional level of granularity known as `exemplar`s. In our experience, creating
exemplars mainly introduced unnecessary redundancy with versions, so we have
opted not to include them in our API. See also http://capitains.org/pages/vocabulary.

## Running in development

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Front-end environment and development

We're leveraging Phoenix LiveView as much as possible for the front-end, but
occasionally we need modern niceties for CSS and JS. If you need to install a
dependency:

1. Think very carefully.
2. Do we really need this dependency?
3. What happens if it breaks?
4. Can we just use part of the dependency in the `vendor/` directory with proper attribution?
5. If you really must install a dependency --- like `@tailwindcss/forms` --- run `npm i -D <dependency>`
from within the `assets/` directory.

## Commentaries

Comments get as specific as possible (e.g., up to a specific lemma); but if that
fails, specificity falls back up the citation chain (e.g., on the specific
section in Pausanias).

## Funding

https://research.fas.harvard.edu/deans-competitive-fund-promising-scholarship


## TODO: Organize comparanda by version type (edition, translation, commentary)

## TODO: Sync to Dropbox

## TODO: Tagging

- Don't build into the interface
- Build into XML parser
- Hash tags and then Word/Open XML indexes
- We need to be able to add definitions for tags
  - make comments about tags themselves (build this into the interface)

## TODO: Blog posts

Allow writing blog posts on commentaries in progress

## TODO: Two-up view

Two panels with editions that can be synced. For example,
we can have the Pausanias translation alongside the
Pausanias commentary.

## TODO: oc.newalexandria.info -> opencommentaries.org pipeline

Migrate commentaries from oc.newalexandria to opencommentaries

## TODO (and notes)

- [ ] Scaife viewer-like URN navigation
- [ ] Alexandria 1.0--style comments
- Tags and/as index (#example-tag)
- Logging for error reports
- Anchor comments (ask for what these are) --- longer comments that fall under
  a given tag. Can be divided into parts, sorted by text location order
  when viewing a given tag's page.
- Named-entity recognition from Neil Smith and Chris Blackwell
- Mobile/responsive layout optimizations
- Global find-and-replace
- Version diffing (where in the pipeline?)
- Need to support uploading multiple docxs
- Show that so-and-so modified a text (important scholarly principle)
- Different approaches for translations, editions, and commentaries
  - Accommodate all three together, but don't enforce it
  - Translation could be secondary to edition and commentary
  - If the commentary is keyed to the original text (edition), translation is secondary
  - If the commentary is keyed to the translation, the edition is secondary
- Let the reader find the alignment between edition and translation
- Let the commenter point to a reference text
- Prioritize commentaries/comments --- just bring up comments
- Aim for most people to create translations and commentaries from scratch on the platform
- Use Perseus commentaries
  - Pre-ingest things to show what people can do on the platform

## TODO - Data from oc.newalexandria.info

- Pull in comments from A Pausanias Commentary in Progress
- Search functionality
- Tagging!

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix

# License

    Open Commentaries: Collaborative, cutting-edge editions of ancient texts
    Copyright (C) 2022 New Alexandria Foundation

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
