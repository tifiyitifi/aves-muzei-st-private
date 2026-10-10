#!/usr/bin/env python3
"""Extract one release section from CHANGELOG.md into CHANGELOG_<version>.md.

Adapted for the Aves changelog heading format, which carries an HTML anchor and
a bracketed version, e.g.:

    ## <a id="v1.15.5"></a>[v1.15.5] - 2026-10-02

Usage: python3 scripts/extract_log.py v1.15.5
Prints nothing on success except the output path; writes CHANGELOG_<version>.md.
"""

import re
import sys


def extract_log(version: str) -> None:
    try:
        with open("CHANGELOG.md", "r", encoding="utf-8") as f:
            lines = f.readlines()
    except FileNotFoundError:
        print("Error: CHANGELOG.md not found")
        return

    heading = re.compile(r"^##\s.*\[" + re.escape(version) + r"\]")
    found = False
    body: list[str] = []

    for line in lines:
        if not found:
            if heading.match(line):
                found = True
            continue
        # Stop at the next section heading.
        if line.startswith("## "):
            break
        body.append(line)

    while body and not body[-1].strip():
        body.pop()

    if not found:
        print(f"Error: no '## ...[{version}]' section in CHANGELOG.md", file=sys.stderr)
        sys.exit(1)

    output_file = f"CHANGELOG_{version}.md"
    with open(output_file, "w", encoding="utf-8") as f:
        f.write("".join(body).strip())
    print(f"Changelog for {version} saved to {output_file}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 scripts/extract_log.py <version>")
        sys.exit(1)
    extract_log(sys.argv[1])
