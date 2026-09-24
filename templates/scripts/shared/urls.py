"""Every URL we ship actually resolves.

Every other check validates the SHAPE of a URL. Shape is not the failure mode.
`https://owner.github.io/repo/privacy` is a perfectly well-formed URL and
returns 404 until someone enables GitHub Pages and writes the page. An app can
pass every check, push metadata to App Store Connect, and only discover at
submission that Apple rejects the listing because the privacy URL is dead.

Source: Hosting/config.json -> anything URL-shaped under "urls". (Store listing URLs
live in Firebase now and are checked by the website repo's data audit.)

A 4xx/5xx is a hard failure: the server answered, and the answer was "no".
A connection error, DNS failure or timeout is a warning instead — CI runners
lose the network often enough that failing on it would train everyone to
re-run checks, and a check people reflexively re-run means nothing.

Placeholders ({{...}}) are skipped.
"""
import json
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path


TIMEOUT = 15
ATTEMPTS = 3
# Some hosts (GitHub Pages included) answer HEAD differently from GET, and a
# few reject HEAD outright, so a HEAD failure is retried as a GET before it
# counts against the URL.
USER_AGENT = "pes-validate-urls/1.0 (+https://github.com/erbittuu-studio/handbook)"


def collect_urls(root) -> dict[str, list[str]]:
    """Map each URL to the places it came from, so one report covers duplicates."""
    found: dict[str, list[str]] = {}

    def note(url: str, source: str) -> None:
        if not isinstance(url, str) or not url.strip():
            return
        if "{{" in url or "}}" in url:
            return  # unsubstituted placeholder
        if not url.startswith(("http://", "https://")):
            return  # malformed
        found.setdefault(url.strip(), []).append(source)

    config_file = root / "Hosting" / "config.json"

    if config_file.is_file():
        try:
            config = json.loads(config_file.read_text())
        except (json.JSONDecodeError, OSError):
            config = {}
        # "urls" is the config schema's key; "links" is accepted too since an
        # earlier draft read only "links" and reported false success.
        for section in ("urls", "links"):
            block = config.get(section) if isinstance(config, dict) else None
            if isinstance(block, dict):
                for key, value in block.items():
                    note(value, f"config.json:{section}.{key}")

    return found


def probe(url: str) -> tuple[str, str]:
    """Return (status, detail): status is "ok", "dead" or "unknown"."""
    last_network_error = ""
    context = ssl.create_default_context()

    for attempt in range(ATTEMPTS):
        for method in ("HEAD", "GET"):
            request = urllib.request.Request(url, method=method, headers={"User-Agent": USER_AGENT})
            try:
                with urllib.request.urlopen(request, timeout=TIMEOUT, context=context) as response:
                    return "ok", f"HTTP {response.status}"
            except urllib.error.HTTPError as e:
                if method == "HEAD" and e.code in (403, 405, 501):
                    continue  # host dislikes HEAD — try GET before judging
                return "dead", f"HTTP {e.code}"
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                last_network_error = str(getattr(e, "reason", e))
                break  # network problem, not a verdict on the URL — retry
        if attempt < ATTEMPTS - 1:
            continue

    return "unknown", last_network_error or "no response"


def check(ctx):
    urls = collect_urls(ctx.root)
    if not urls:
        return []  # no Hosting/config.json, so this app ships no URLs of its own to probe

    dead: list[str] = []

    for url, sources in sorted(urls.items()):
        status, detail = probe(url)
        where = ", ".join(sources)
        if status == "ok":
            print(f"  ok       {url}  ({detail})")
        elif status == "dead":
            print(f"  DEAD     {url}  ({detail})  <- {where}")
            dead.append(
                f"{url} returned {detail} — referenced by {where}. Apple rejects "
                f"listings whose privacy or support page 404s."
            )
        else:
            # Not a verdict on the URL: the network, not the page, failed.
            print(f"  unknown  {url}  ({detail})  <- {where}")
            print(f"::warning::{url} could not be reached ({detail}) — referenced by {where}")

    if not dead:
        print(f"  {len(urls)} URL(s) reachable")
    return dead
