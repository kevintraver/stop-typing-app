#!/usr/bin/env python3
"""Renders docs/releases/*.md into the website's What's New page, changelog.html.

    scripts/update-website.py <version> [website-dir]

website-dir defaults to ~/Code/stop-typing-app-website (a clone of kevintraver/stop-typing-app-website).
Like update-cask.sh it only writes the file and prints the commands to commit and push.

<version> must have notes in docs/releases/<version>.md. Each release is dated by its v<version> tag;
the release being published is dated today when its tag hasn't been fetched yet.

The page's header and footer are copied from privacy.html: keep the three in step when they change.
"""
import datetime
import html
import pathlib
import re
import subprocess
import sys

REPO_DIR = pathlib.Path(__file__).resolve().parent.parent
NOTES_DIR = REPO_DIR / "docs" / "releases"
SITE_URL = "https://www.stoptypingapp.com"
RELEASES_URL = "https://github.com/kevintraver/stop-typing-app/releases"

TEXT = 'style="margin: 0; font-size: 17px; line-height: 1.6; color: #5B5B63"'
STRONG = 'style="color: #1D1D1F; font-weight: 600"'
CODE = 'style="font-family: \'Geist Mono\', ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 15px; color: #1D1D1F"'
LINK = 'style="color: #1D1D1F; text-decoration: underline; text-underline-offset: 3px"'


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def tag_date(version):
    result = subprocess.run(
        ["git", "-C", str(REPO_DIR), "log", "-1", "--format=%cs", f"v{version}", "--"],
        capture_output=True, text=True,
    )
    return result.stdout.strip() or None


def pretty_date(iso):
    return datetime.date.fromisoformat(iso).strftime("%B %-d, %Y")


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", rf"<code {CODE}>\1</code>", text)
    text = re.sub(r"\*\*(.+?)\*\*", rf"<strong {STRONG}>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", rf'<a href="\2" {LINK}>\1</a>', text)
    return text


def blocks(markdown):
    for block in re.split(r"\n[ \t]*\n", markdown.strip()):
        lines = [line.rstrip() for line in block.strip().split("\n")]
        if lines[0].startswith("## "):
            yield f'<h3 style="margin: 4px 0 0; font-size: 17px; line-height: 1.4; font-weight: 600; color: #1D1D1F">{inline(lines[0][3:])}</h3>'
        elif all(line.startswith("- ") for line in lines):
            items = "\n".join(f"<li {TEXT}>{inline(line[2:])}</li>" for line in lines)
            yield f'<ul style="margin: 0; padding-left: 20px; display: flex; flex-direction: column; gap: 10px">\n{items}\n</ul>'
        else:
            yield f"<p {TEXT}>{inline(' '.join(lines))}</p>"


def entry(version, date):
    anchor = "v" + version.replace(".", "-")
    dated = f'<span style="font-size: 15px; font-weight: 400; color: #5B5B63">{pretty_date(date)}</span>' if date else ""
    body = "\n".join(blocks((NOTES_DIR / f"{version}.md").read_text()))
    return f'''<section id="{anchor}" style="display: flex; flex-direction: column; gap: 10px">
<h2 style="margin: 0; display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px 14px; font-size: 22px; line-height: 1.2; font-weight: 600; letter-spacing: -0.02em; color: #1D1D1F"><a href="#{anchor}" style="color: inherit">{version}</a>{dated}</h2>
{body}
</section>'''


def page(entries):
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>What’s new · Stop Typing App</title>
<meta name="description" content="What changed in each release of Stop Typing App.">
<meta name="theme-color" content="#F5F5F7">
<link rel="icon" type="image/png" href="/favicon.png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="stylesheet" href="/fonts/fonts.css">
<script>
window.va = window.va || function () {{ (window.vaq = window.vaq || []).push(arguments); }};
</script>
<script defer src="/_vercel/insights/script.js"></script>
<script>
window.si = window.si || function () {{ (window.siq = window.siq || []).push(arguments); }};
</script>
<script defer src="/_vercel/speed-insights/script.js"></script>
<style>
body{{margin:0;background:#F5F5F7}}
a{{color:#1D1D1F;text-decoration:none}}a:hover{{color:#5B5B63}}
h1,h2,h3{{text-wrap:balance}}
a:focus-visible{{outline:2px solid #0A84FF;outline-offset:3px;border-radius:8px}}
section:target h2 a{{text-decoration:underline;text-underline-offset:4px}}
@media (max-width: 600px){{.nav-link{{display:none}}}}
</style>
</head>
<body>
<div id="top" style="min-height: 100vh; background: #F5F5F7; color: #1D1D1F; font-family: 'Geist', system-ui, -apple-system, sans-serif; font-size: 17px; line-height: 1.55; -webkit-font-smoothing: antialiased">

<header style="max-width: 1160px; margin: 0 auto; padding: 20px 24px; display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 16px">
<a href="/" style="display: flex; align-items: center; gap: 10px; font-weight: 600; font-size: 18px; letter-spacing: -0.01em; min-height: 44px">
<img src="/icon.png" alt="" style="width: 34px; height: 34px; filter: drop-shadow(0 0 0.5px rgba(0,0,0,0.4)) drop-shadow(0 1px 2px rgba(0,0,0,0.14))">
<span>Stop Typing App</span>
</a>
<nav aria-label="Main" style="display: flex; flex-wrap: wrap; align-items: center; gap: 4px 24px; font-size: 15px">
<a href="/#how" class="nav-link" style="color: #5B5B63; padding: 10px 0">How it works</a>
<a href="/#privacy" class="nav-link" style="color: #5B5B63; padding: 10px 0">Privacy</a>
<a href="/#features" class="nav-link" style="color: #5B5B63; padding: 10px 0">Features</a>
<a href="/#faq" class="nav-link" style="color: #5B5B63; padding: 10px 0">FAQ</a>
<a href="/#download" style="background: #1D1D1F; color: #FFFFFF; padding: 11px 18px; border-radius: 999px; font-weight: 500">Download</a>
</nav>
</header>

<main style="max-width: 720px; margin: 0 auto; padding: clamp(32px, 6vw, 56px) 24px clamp(64px, 10vw, 96px); display: flex; flex-direction: column; gap: 48px">
<div style="display: flex; flex-direction: column; gap: 14px">
<h1 style="margin: 0; font-size: clamp(34px, 4.4vw, 54px); line-height: 1.05; font-weight: 650; letter-spacing: -0.035em">What’s new</h1>
<p style="margin: 0; font-size: 19px; line-height: 1.6; color: #5B5B63">What changed in each release. The app installs updates itself once you turn on automatic checks in Settings, and every version is on <a href="{RELEASES_URL}" {LINK}>GitHub</a>.</p>
</div>

{entries}
</main>

<footer>
<div style="max-width: 1160px; margin: 0 auto; padding: 18px 24px; display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 8px 24px; font-size: 14px; color: #5B5B63">
<span style="display: flex; align-items: center; gap: 10px"><img src="/icon.png" alt="" style="width: 20px; height: 20px; filter: drop-shadow(0 0 0.5px rgba(0,0,0,0.4)) drop-shadow(0 1px 1.5px rgba(0,0,0,0.14))"><span style="font-weight: 600; color: #1D1D1F">Stop Typing App</span><span>© 2026 Kevin Traver</span></span>
<nav aria-label="Footer" style="display: flex; flex-wrap: wrap; align-items: center; gap: 0 20px">
<a href="/#how" style="color: #5B5B63; padding: 12px 0">How it works</a>
<a href="/privacy.html" style="color: #5B5B63; padding: 12px 0">Privacy</a>
<a href="/#features" style="color: #5B5B63; padding: 12px 0">Features</a>
<a href="/#faq" style="color: #5B5B63; padding: 12px 0">FAQ</a>
<a href="/changelog.html" style="color: #5B5B63; padding: 12px 0">What’s new</a>
<a href="/#download" style="color: #5B5B63; padding: 12px 0">Download</a>
<span style="display: flex; align-items: center; gap: 4px">
<a href="https://github.com/kevintraver/stop-typing-app" aria-label="Stop Typing App on GitHub" style="display: inline-flex; align-items: center; justify-content: center; width: 44px; height: 44px; color: #5B5B63"><svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4"></path><path d="M9 18c-4.51 2-5-2-7-2"></path></svg></a>
<a href="https://x.com/kevintraver" aria-label="Kevin Traver on X" style="display: inline-flex; align-items: center; justify-content: center; width: 44px; height: 44px; color: #5B5B63"><svg aria-hidden="true" width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"></path></svg></a>
</span>
</nav>
</div>
</footer>

</div>
</body>
</html>
'''


def main(argv):
    if len(argv) not in (2, 3):
        print(f"usage: {argv[0]} <version> [website-dir]", file=sys.stderr)
        return 2
    version = argv[1]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        print(f'error: "{version}" isn\'t a version like 1.2.3', file=sys.stderr)
        return 2
    site_dir = pathlib.Path(argv[2]) if len(argv) == 3 else pathlib.Path.home() / "Code" / "stop-typing-app-website"
    if not (NOTES_DIR / f"{version}.md").is_file():
        print(f"error: no release notes at docs/releases/{version}.md", file=sys.stderr)
        return 1
    if not (site_dir / ".git").is_dir():
        print(f'error: {site_dir} isn\'t a git checkout; clone it with: gh repo clone kevintraver/stop-typing-app-website "{site_dir}"', file=sys.stderr)
        return 1

    versions = sorted((path.stem for path in NOTES_DIR.glob("*.md")), key=version_key, reverse=True)
    today = datetime.date.today().isoformat()
    entries = "\n\n".join(entry(v, tag_date(v) or (today if v == version else None)) for v in versions)
    target = site_dir / "changelog.html"
    target.write_text(page(entries))

    print(f"Wrote {target} with {len(versions)} releases, newest {versions[0]}.")
    print(f"""
Check it, then commit and push the website (Vercel deploys on push):
  git -C "{site_dir}" add changelog.html
  git -C "{site_dir}" commit -m "What's new: {version}"
  git -C "{site_dir}" push""")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
