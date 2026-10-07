#!/usr/bin/env python3
"""Builds one page per language from i18n/<code>.json and template.html.

Separate pages rather than a switcher in JavaScript: a search engine indexes
what is in the HTML it is served, and a page that rewrites itself after load
is one page as far as Google is concerned. Each language therefore gets its
own URL, its own <title> and description, and hreflang links to all the
others so they are understood as the same page rather than as duplicates.

English lives at the root and is the x-default; everything else lives at
/<code>/. Run: python3 build.py
"""
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).parent
FAILED: list = []
SITE = "https://nativevoice.trustbe.com"

# code -> (native name, flag). The native name is what goes in the switcher:
# somebody looking for their own language is looking for the word they call
# it, not for the English one.
LANGUAGES = {
    "en": ("English", "\U0001F1EC\U0001F1E7"),
    "be": ("Беларуская", "\U0001F1E7\U0001F1FE"),
    "bs": ("Bosanski", "\U0001F1E7\U0001F1E6"),
    "bg": ("Български", "\U0001F1E7\U0001F1EC"),
    "ca": ("Català", "\U0001F1EA\U0001F1F8"),
    "hr": ("Hrvatski", "\U0001F1ED\U0001F1F7"),
    "cs": ("Čeština", "\U0001F1E8\U0001F1FF"),
    "da": ("Dansk", "\U0001F1E9\U0001F1F0"),
    "nl": ("Nederlands", "\U0001F1F3\U0001F1F1"),
    "et": ("Eesti", "\U0001F1EA\U0001F1EA"),
    "fi": ("Suomi", "\U0001F1EB\U0001F1EE"),
    "fr": ("Français", "\U0001F1EB\U0001F1F7"),
    "gl": ("Galego", "\U0001F1EA\U0001F1F8"),
    "de": ("Deutsch", "\U0001F1E9\U0001F1EA"),
    "el": ("Ελληνικά", "\U0001F1EC\U0001F1F7"),
    "hu": ("Magyar", "\U0001F1ED\U0001F1FA"),
    "is": ("Íslenska", "\U0001F1EE\U0001F1F8"),
    "id": ("Indonesia", "\U0001F1EE\U0001F1E9"),
    "it": ("Italiano", "\U0001F1EE\U0001F1F9"),
    "ja": ("日本語", "\U0001F1EF\U0001F1F5"),
    "kn": ("ಕನ್ನಡ", "\U0001F1EE\U0001F1F3"),
    "lv": ("Latviešu", "\U0001F1F1\U0001F1FB"),
    "mk": ("Македонски", "\U0001F1F2\U0001F1F0"),
    "ms": ("Melayu", "\U0001F1F2\U0001F1FE"),
    "ml": ("മലയാളം", "\U0001F1EE\U0001F1F3"),
    "no": ("Norsk", "\U0001F1F3\U0001F1F4"),
    "pl": ("Polski", "\U0001F1F5\U0001F1F1"),
    "pt": ("Português", "\U0001F1F5\U0001F1F9"),
    "ro": ("Română", "\U0001F1F7\U0001F1F4"),
    "ru": ("Русский", "\U0001F1F7\U0001F1FA"),
    "sk": ("Slovenčina", "\U0001F1F8\U0001F1F0"),
    "es": ("Español", "\U0001F1EA\U0001F1F8"),
    "sv": ("Svenska", "\U0001F1F8\U0001F1EA"),
    "tr": ("Türkçe", "\U0001F1F9\U0001F1F7"),
    "uk": ("Українська", "\U0001F1FA\U0001F1E6"),
    "vi": ("Tiếng Việt", "\U0001F1FB\U0001F1F3"),
}


def url_for(code: str) -> str:
    return f"{SITE}/" if code == "en" else f"{SITE}/{code}/"


def href_for(code: str, current: str) -> str:
    """Relative, so the pages work when served from a subdirectory too."""
    up = "" if current == "en" else "../"
    return f"{up}" if code == "en" else f"{up}{code}/"


def load(code: str) -> dict:
    path = HERE / "i18n" / f"{code}.json"
    base = json.loads((HERE / "i18n" / "en.json").read_text())
    if code != "en":
        # Fall back to English per string rather than per page: a translation
        # that is missing one line should still be a translated page.
        base.update(json.loads(path.read_text()))
    return base


def alternates(current: str) -> str:
    rows = [
        f'<link rel="alternate" hreflang="{c}" href="{url_for(c)}">'
        for c in LANGUAGES
    ]
    rows.append(f'<link rel="alternate" hreflang="x-default" href="{url_for("en")}">')
    rows.append(f'<link rel="canonical" href="{url_for(current)}">')
    return "\n".join(rows)


def switcher(current: str) -> str:
    name, flag = LANGUAGES[current]
    options = "\n".join(
        '      <a href="{href}" lang="{c}"{aria}><i>{flag}</i>{name}</a>'.format(
            href=href_for(c, current), c=c, flag=f, name=n,
            aria=' aria-current="page"' if c == current else "")
        for c, (n, f) in LANGUAGES.items()
    )
    return (
        '<details class="picker">\n'
        f'    <summary><i>{flag}</i>{name}</summary>\n'
        '    <div class="picker-menu">\n'
        f'{options}\n'
        '    </div>\n'
        '  </details>'
    )


# What a search result can show before it cuts the sentence off mid-word.
# Checked rather than trusted: a description written to fit in English runs
# long in half the languages it is translated into, and the only sign is a
# truncated result page nobody involved will ever see.
TITLE_MAX = 60
DESCRIPTION_MAX = 155


def check(code: str, text: dict) -> list:
    import re
    english = json.loads((HERE / "i18n" / "en.json").read_text())
    def plain(key):
        return re.sub(r"<[^>]+>", "", text.get(key, ""))
    problems = []
    missing = set(english) - set(text)
    if missing:
        problems.append(f"missing keys: {', '.join(sorted(missing))}")
    if len(plain("title")) > TITLE_MAX:
        problems.append(f"title is {len(plain('title'))} characters, limit {TITLE_MAX}")
    if len(plain("description")) > DESCRIPTION_MAX:
        problems.append(
            f"description is {len(plain('description'))} characters, limit {DESCRIPTION_MAX}")
    # Tags are structure, not words: one dropped in translation takes the
    # layout or a link with it.
    for key, value in english.items():
        if value.count("<") != text.get(key, "").count("<"):
            problems.append(f"{key}: HTML tags do not match the English")
    return problems


def flags() -> str:
    """The language list, each in its own name.

    It was hardcoded in English, so a Czech reader was told their language was
    called "Czech". The names come from the same table as the switcher: the
    word a language calls itself is the one its speakers look for.
    """
    return "".join(
        f"<span><i>{flag}</i>{name}</span>"
        for name, flag in LANGUAGES.values()
    )


def build(code: str) -> None:
    text = load(code)
    problems = check(code, text)
    if problems:
        for problem in problems:
            print(f"  {code}: {problem}", file=sys.stderr)
        FAILED.append(code)
    template = (HERE / "template.html").read_text()
    # `../` for assets, because a language page sits one directory down.
    base = "" if code == "en" else "../"

    page = template
    for key, value in text.items():
        page = page.replace("{{" + key + "}}", value)
    page = (page
            .replace("{{lang}}", code)
            .replace("{{base}}", base)
            .replace("{{alternates}}", alternates(code))
            .replace("{{switcher}}", switcher(code))
            .replace("{{url}}", url_for(code))
            .replace("{{flags}}", flags())
            .replace("{{codes}}", json.dumps(list(LANGUAGES)))
            # English is the source, not a translation: its link goes to the
            # directory of all of them, not to its own file.
            .replace("{{i18n}}",
                     "tree/main/docs/i18n" if code == "en"
                     else f"blob/main/docs/i18n/{code}.json"))

    # Every English string must be gone from a translated page. A key that
    # was never wired into the template looks translated in the JSON and
    # renders in English on the page, which is the one failure nobody checks
    # for — it was "36 languages" as a section heading, and it shipped.
    if code != "en":
        english = json.loads((HERE / "i18n" / "en.json").read_text())
        for key, value in english.items():
            if key in ("title",) or len(value) < 12:
                continue
            if value != text.get(key) and value in page:
                print(f"  {code}: '{key}' is still in English on the page",
                      file=sys.stderr)
                FAILED.append(code)

    leftover = [m for m in ("{{",) if m in page]
    if leftover:
        sys.exit(f"{code}: unreplaced placeholder in output")

    out = HERE / "index.html" if code == "en" else HERE / code / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)


def sitemap() -> None:
    rows = "\n".join(
        f"  <url><loc>{url_for(c)}</loc>"
        + "".join(f'<xhtml:link rel="alternate" hreflang="{o}" href="{url_for(o)}"/>'
                  for o in LANGUAGES)
        + "</url>"
        for c in LANGUAGES
    )
    # Pages outside the language set: English only, so no hreflang.
    extra = "\n".join(f"  <url><loc>{SITE}/{path}</loc></url>"
                      for path in ("notes/quiet-microphone/",))
    rows = rows + "\n" + extra
    (HERE / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n'
        '        xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
        f"{rows}\n</urlset>\n")
    (HERE / "robots.txt").write_text(
        f"User-agent: *\nAllow: /\nSitemap: {SITE}/sitemap.xml\n")


if __name__ == "__main__":
    have = {p.stem for p in (HERE / "i18n").glob("*.json")}
    missing = [c for c in LANGUAGES if c not in have]
    for code in LANGUAGES:
        if code in have:
            build(code)
    sitemap()
    print(f"built {len(have & set(LANGUAGES))} pages")
    if FAILED:
        sys.exit(f"problems in: {' '.join(FAILED)}")
    if missing:
        print("waiting on translations:", " ".join(missing))
