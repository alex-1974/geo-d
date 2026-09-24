#!/usr/bin/env python3

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import re
import sys


SECTION_RE = re.compile(
    r"^## `(?P<module>geo(?:\.[^`]+)?)`"
)

ROW_RE = re.compile(
    r"^\| `(?P<declaration>[^`]+)` "
    r"\| \*\*(?P<classification>existing|add|family)\*\* \|"
)


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Verify the public API example audit against generated DDox HTML."
        )
    )

    parser.add_argument(
        "audit",
        nargs="?",
        default="docs/public-api-example-audit.md",
        type=Path,
    )

    parser.add_argument(
        "site",
        nargs="?",
        default="build/ddox/site",
        type=Path,
    )

    return parser.parse_args()


def page_for(
    site: Path,
    module: str,
    declaration: str,
) -> Path:
    if module == "geo":
        return site / "geo" / f"{declaration}.html"

    module_name = module.removeprefix("geo.")

    return (
        site /
        "geo" /
        module_name.replace(".", "/") /
        f"{declaration}.html"
    )


def public_symbol_pages(site: Path) -> set[Path]:
    source_dir = Path("source/geo")

    if not source_dir.is_dir():
        fail("source/geo is missing")

    excluded = {
        site / "index.html",
        site / "geo.html",
    }

    for source in source_dir.glob("*.d"):
        if source.name == "package.d":
            continue

        excluded.add(
            site /
            "geo" /
            f"{source.stem}.html"
        )

    return {
        page
        for page in site.rglob("*.html")
        if page not in excluded
    }


def main() -> None:
    args = parse_arguments()

    if not args.audit.is_file():
        fail(f"audit file is missing: {args.audit}")

    if not args.site.is_dir():
        fail(f"DDox site is missing: {args.site}")

    current_module: str | None = None
    entries: list[tuple[str, str, Path]] = []

    for line_number, line in enumerate(
        args.audit.read_text().splitlines(),
        start=1,
    ):
        section_match = SECTION_RE.match(line)

        if section_match:
            current_module = section_match.group("module")
            continue

        row_match = ROW_RE.match(line)

        if not row_match:
            continue

        if current_module is None:
            fail(
                "classified audit row appears before a geo module heading "
                f"at line {line_number}"
            )

        declaration = row_match.group("declaration")
        classification = row_match.group("classification")

        entries.append(
            (
                declaration,
                classification,
                page_for(
                    args.site,
                    current_module,
                    declaration,
                ),
            )
        )

    if not entries:
        fail("no classified public API rows found")

    pages = [entry[2] for entry in entries]

    duplicates = [
        page
        for page, count in Counter(pages).items()
        if count > 1
    ]

    if duplicates:
        for page in sorted(duplicates):
            print(
                f"duplicate audited page: "
                f"{page.relative_to(args.site)}",
                file=sys.stderr,
            )

        fail("duplicate public API audit entries")

    expected_pages = set(pages)
    actual_pages = public_symbol_pages(args.site)

    missing = sorted(expected_pages - actual_pages)
    unclassified = sorted(actual_pages - expected_pages)

    if missing:
        for page in missing:
            print(
                f"missing documented symbol page: "
                f"{page.relative_to(args.site)}",
                file=sys.stderr,
            )

    if unclassified:
        for page in unclassified:
            print(
                f"unclassified documented symbol page: "
                f"{page.relative_to(args.site)}",
                file=sys.stderr,
            )

    if missing or unclassified:
        fail("public DDox symbol inventory differs from the audit")

    counts = Counter(
        classification
        for _, classification, _ in entries
    )

    if counts["add"]:
        for declaration, classification, page in entries:
            if classification == "add":
                print(
                    f"incomplete example audit entry: "
                    f"{page.relative_to(args.site)} "
                    f"({declaration})",
                    file=sys.stderr,
                )

        fail("public API example audit still contains add entries")

    mismatches = []

    for declaration, classification, page in entries:
        html = page.read_text(errors="replace")
        has_example = ">Example<" in html

        if classification == "existing" and not has_example:
            mismatches.append(
                (
                    page,
                    declaration,
                    "classified existing but no Example is rendered",
                )
            )

        if classification == "family" and has_example:
            mismatches.append(
                (
                    page,
                    declaration,
                    "classified family but an Example is rendered",
                )
            )

    if mismatches:
        for page, declaration, message in mismatches:
            print(
                f"{page.relative_to(args.site)} "
                f"({declaration}): {message}",
                file=sys.stderr,
            )

        fail("rendered Example state differs from the audit")

    print(
        "PASS: public API example audit "
        f"({len(entries)} symbol pages; "
        f"{counts['existing']} existing; "
        f"{counts['family']} family; "
        f"{counts['add']} add)"
    )


if __name__ == "__main__":
    main()
