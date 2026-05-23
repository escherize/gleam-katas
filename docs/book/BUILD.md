# Building the book

The book lives as plain markdown files in this directory and is
readable as-is on GitHub. The same files render to HTML / PDF /
EPUB via [Quarto](https://quarto.org).

## Install Quarto

```sh
brew install --cask quarto       # macOS, asks for sudo
# or: npm i -g @quarto/cli       # no sudo
```

The PDF format also needs a LaTeX engine. TinyTeX is the lightest
option and Quarto can install it for you:

```sh
quarto install tinytex
```

## Render

From inside `docs/book/`:

```sh
quarto render                    # all configured formats (html + pdf + epub)
quarto render --to html          # just the static site
quarto render --to pdf           # just the PDF
quarto preview                   # live HTML reload on a local server
```

Output lands in `docs/book/_book/`. The PDF is `_book/DDD-in-Gleam.pdf`,
the static site is `_book/index.html` and friends.

## Project layout

- `_quarto.yml` — project config (chapter order, output formats, theme).
- `index.md` — book cover/intro page. The first chapter shown.
- `00_introduction.md` ... `12_in_practice.md` — chapters, in order.

Adding a chapter is a two-step change: drop the markdown file in this
directory, then add it to the `chapters:` list in `_quarto.yml`.

## Publishing

GitHub Pages is one `quarto publish gh-pages` away once you've enabled
Pages on the repo. The PDF can ship as a GitHub release asset; the
HTML can ship as the Pages site. Both come from the same `quarto render`.
