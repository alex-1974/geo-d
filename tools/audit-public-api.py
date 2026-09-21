#!/usr/bin/env python3
"""Generate a reproducible DMD-derived inventory of geo-d's supported public API."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


V1_BASELINE_COMMIT = "86e271714ddca2a6644f874751cc4c73beebc534"

V1_EXPECTED_SURFACE_SHA256 = "3a7ab4e1186d2083a0e157acbed272065c1ae1690d6d9df06ca9ef3a09e35f55"

V1_EXPECTED = {
    "package_exports": 41,
    "top_level_declarations": 53,
    "public_aggregate_members": 69,
    "private_aggregate_members": 12,
    "enum_members": 24,
    "audit_declarations": 146,
    "unresolved_members": 0,
}

PUBLIC_BLOCKED = {
    "private",
    "package",
    "protected",
}


def die(message: str) -> None:
    raise SystemExit(f"error: {message}")


def run(
    command: list[str],
    *,
    cwd: Path,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)

        die(
            "command failed: "
            + " ".join(command)
        )

    return result


def find_repo_root(start: Path) -> Path:
    result = subprocess.run(
        [
            "git",
            "rev-parse",
            "--show-toplevel",
        ],
        cwd=start,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    if result.returncode != 0:
        die("not inside a Git repository")

    return Path(
        result.stdout.strip()
    ).resolve()


def parse_package_exports(
    package_text: str,
) -> list[tuple[str, str]]:
    pattern = re.compile(
        r"""
        public\s+import\s+
        (?P<module>[A-Za-z_][A-Za-z0-9_.]*)
        \s*:\s*
        (?P<names>.*?)
        ;
        """,
        re.VERBOSE | re.DOTALL,
    )

    exports: list[tuple[str, str]] = []

    for match in pattern.finditer(package_text):
        module = match.group("module")

        names = [
            name.strip()
            for name in
            match.group("names")
            .replace("\n", " ")
            .split(",")
            if name.strip()
        ]

        exports.extend(
            (module, name)
            for name in names
        )

    names = [
        name
        for _, name in exports
    ]

    duplicates = sorted(
        name
        for name, count
        in Counter(names).items()
        if count > 1
    )

    if duplicates:
        die(
            "duplicate package exports: "
            + ", ".join(duplicates)
        )

    return exports


def include_local_package_exports(
    exports: list[tuple[str, str]],
    modules: dict[
        str,
        dict[str, Any],
    ],
) -> list[tuple[str, str]]:
    """
    Add public declarations written directly in module `geo`.

    Selective `public import` names are discovered from package.d source.
    Local root declarations are discovered from DMD JSON so aliases,
    templates, functions, types, and future declaration forms follow the
    compiler's semantic representation rather than a second source parser.
    """

    package_module = modules.get(
        "geo"
    )

    if package_module is None:
        die(
            "missing root package module "
            "geo in DMD JSON"
        )

    local_exports: list[
        tuple[str, str]
    ] = []

    for node in package_module.get(
        "members",
        [],
    ):
        if not isinstance(
            node,
            dict,
        ):
            continue

        if node.get("kind") == "import":
            continue

        name = node.get(
            "name"
        )

        if not name:
            continue

        if name.startswith(
            "__unittest"
        ):
            continue

        if node.get(
            "protection"
        ) in PUBLIC_BLOCKED:
            continue

        local_exports.append(
            (
                "geo",
                name,
            )
        )

    combined = [
        *exports,
        *local_exports,
    ]

    names = [
        name
        for _, name in combined
    ]

    duplicates = sorted(
        name
        for name, count
        in Counter(names).items()
        if count > 1
    )

    if duplicates:
        die(
            "duplicate root package names: "
            + ", ".join(
                duplicates
            )
        )

    return combined


def template_impl(
    node: dict[str, Any],
) -> dict[str, Any]:
    if node.get("kind") != "template":
        return node

    matches = [
        member
        for member in node.get("members", [])
        if isinstance(member, dict)
        and member.get("name") == node.get("name")
        and member.get("kind") in {
            "function",
            "struct",
            "class",
            "union",
            "enum",
            "alias",
            "variable",
        }
    ]

    if len(matches) == 1:
        return matches[0]

    return node


def declaration_kind(
    node: dict[str, Any],
) -> str:
    impl = template_impl(node)

    if (
        node.get("kind") == "template"
        and impl is not node
    ):
        return (
            f"template/"
            f"{impl.get('kind')}"
        )

    return str(
        node.get("kind", "")
    )


def function_parameters(
    node: dict[str, Any],
) -> list[dict[str, Any]]:
    impl = template_impl(node)

    if impl.get("kind") == "function":
        return impl.get(
            "parameters",
            [],
        )

    return []


def source_line(
    node: dict[str, Any],
) -> int | None:
    value = node.get("line")

    if value is None:
        value = template_impl(
            node
        ).get("line")

    return value


def effective_name(name: str) -> str:
    if name == "__ctor":
        return "this"

    return name


def compact(value: Any) -> str:
    if value is None:
        return ""

    return json.dumps(
        value,
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    )


def row_for(
    *,
    module: str,
    owner: str,
    node: dict[str, Any],
    surface_kind: str,
    overload: int,
    visibility: str = "public",
) -> dict[str, Any]:
    impl = template_impl(node)
    params = function_parameters(node)

    first = (
        params[0]
        if params
        else None
    )

    name = node.get(
        "name",
        "",
    )

    return {
        "module": module,
        "surface_kind": surface_kind,
        "owner": owner,
        "name": name,
        "qualified_name": (
            name
            if not owner
            else f"{owner}.{name}"
        ),
        "overload": overload,
        "declaration_kind":
            declaration_kind(node),
        "line":
            source_line(node),
        "visibility":
            visibility,
        "documented":
            bool(
                node.get("comment")
                or impl.get("comment")
            ),
        "template_parameters": (
            node.get(
                "parameters",
                [],
            )
            if node.get("kind")
            == "template"
            else []
        ),
        "constraint":
            node.get("constraint"),
        "parameters":
            params,
        "first_parameter":
            first,
        "declaration_type":
            impl.get("type"),
        "value":
            impl.get("value"),
        "spec_value":
            impl.get("specValue"),
        "member_type":
            None,
        "init_value":
            None,
        "storage_class":
            impl.get("storageClass"),
        "ufcs_candidate":
            bool(
                surface_kind
                == "top-level"
                and impl.get("kind")
                == "function"
                and params
            ),
    }


def generate_raw_dmd_json(
    root: Path,
    out_dir: Path,
    compiler: str,
) -> tuple[Path, list[Path]]:
    source_dir = (
        root
        / "source"
        / "geo"
    )

    public_sources = sorted(
        source_dir.glob("*.d")
    )

    if not public_sources:
        die(
            "no public "
            "source/geo/*.d modules found"
        )

    raw_json = (
        out_dir
        / "raw-docs.json"
    )

    dummy = (
        out_dir
        / "__dummy.html"
    )

    command = [
        compiler,
        "-o-",
        "-w",
        f"-Xf{raw_json}",
        f"-Df{dummy}",
        "-version=Have_geo_d",
        "-Isource",
        "-preview=dip1000",
        "-vcolumns",
        *[
            str(
                path.relative_to(root)
            )
            for path
            in public_sources
        ],
    ]

    run(
        command,
        cwd=root,
    )

    dummy.unlink(
        missing_ok=True
    )

    if (
        not raw_json.is_file()
        or raw_json.stat().st_size
        == 0
    ):
        die(
            "DMD did not produce "
            "raw-docs.json"
        )

    return (
        raw_json,
        public_sources,
    )


def exported_aggregate_expressions(
    exports: list[tuple[str, str]],
    modules: dict[
        str,
        dict[str, Any],
    ],
) -> list[tuple[str, str]]:
    expressions: list[
        tuple[str, str]
    ] = []

    for (
        module_name,
        export_name,
    ) in exports:
        module = modules.get(
            module_name
        )

        if module is None:
            die(
                "missing module "
                "in DMD JSON: "
                + module_name
            )

        matches = [
            node
            for node
            in module.get(
                "members",
                [],
            )
            if isinstance(
                node,
                dict,
            )
            and node.get("name")
            == export_name
        ]

        if not matches:
            die(
                "missing exported "
                "declaration in DMD JSON: "
                f"{module_name}."
                f"{export_name}"
            )

        aggregate_nodes = []

        for node in matches:
            impl = template_impl(
                node
            )

            if impl.get("kind") in {
                "struct",
                "class",
                "union",
            }:
                aggregate_nodes.append(
                    (
                        node,
                        impl,
                    )
                )

        if not aggregate_nodes:
            continue

        if len(
            aggregate_nodes
        ) != 1:
            die(
                "ambiguous aggregate "
                "export: "
                f"{module_name}."
                f"{export_name}"
            )

        node, _ = (
            aggregate_nodes[0]
        )

        if (
            node.get("kind")
            == "template"
        ):
            parameters = node.get(
                "parameters",
                [],
            )

            if (
                len(parameters) != 1
                or parameters[0].get(
                    "kind"
                )
                != "type"
            ):
                die(
                    "cannot "
                    "auto-instantiate "
                    "aggregate template "
                    f"{export_name}; "
                    "expected exactly "
                    "one type parameter"
                )

            expression = (
                f"{export_name}!double"
            )

        else:
            expression = export_name

        expressions.append(
            (
                export_name,
                expression,
            )
        )

    return expressions


def generate_reflection_probe(
    root: Path,
    out_dir: Path,
    compiler: str,
    aggregates: list[
        tuple[str, str]
    ],
) -> tuple[
    Path,
    list[dict[str, Any]],
    list[str],
]:
    probe = (
        out_dir
        / "member-visibility.d"
    )

    log = (
        out_dir
        / "member-visibility.log"
    )

    mixins = "\n\n".join(
        (
            "mixin DumpMembers!("
            f'{expression}, '
            f'"{label}"'
            ");"
        )
        for label, expression
        in aggregates
    )

    probe.write_text(
        f'''module geo_d_api_member_visibility;

import geo;

struct MemberProbe(
    T,
    string label,
    string memberName
)
{{
    alias overloads =
        __traits(
            getOverloads,
            T,
            memberName,
            true
        );

    static if (
        overloads.length != 0
    )
    {{
        static foreach (
            member;
            overloads
        )
        {{
            pragma(
                msg,
                "VIS\\t",
                label,
                "\\t",
                memberName,
                "\\t",
                __traits(
                    getVisibility,
                    member
                ),
                "\\t",
                __traits(
                    getLocation,
                    member
                )[1],
                "\\toverload\\t\\t"
            );
        }}
    }}
    else static if (
        __traits(
            compiles,
            __traits(
                getMember,
                T,
                memberName
            )
        )
    )
    {{
        alias member =
            __traits(
                getMember,
                T,
                memberName
            );

        pragma(
            msg,
            "VIS\\t",
            label,
            "\\t",
            memberName,
            "\\t",
            __traits(
                getVisibility,
                member
            ),
            "\\t",
            __traits(
                getLocation,
                member
            )[1],
            "\\tmember\\t",
            typeof(member).stringof,
            "\\t",
            __traits(
                getMember,
                T.init,
                memberName
            )
        );
    }}
    else
    {{
        pragma(
            msg,
            "UNRESOLVED\\t",
            label,
            "\\t",
            memberName
        );
    }}

    enum bool ok = true;
}}


mixin template DumpMembers(
    T,
    string label
)
{{
    static foreach (
        memberName;
        __traits(
            derivedMembers,
            T
        )
    )
    {{
        static assert(
            MemberProbe!(
                T,
                label,
                memberName
            ).ok
        );
    }}
}}


{mixins}
'''
    )

    result = run(
        [
            compiler,
            "-o-",
            "-c",
            "-verrors=0",
            "-Isource",
            "-preview=dip1000",
            str(probe),
        ],
        cwd=root,
    )

    combined = (
        result.stdout
        + result.stderr
    )

    log.write_text(
        combined
    )

    records: list[
        dict[str, Any]
    ] = []

    unresolved: list[str] = []

    for line in (
        combined.splitlines()
    ):
        if line.startswith(
            "VIS\t"
        ):
            fields = (
                line.split("\t")
            )

            if len(fields) != 8:
                die(
                    "unexpected "
                    "reflection record: "
                    + repr(line)
                )

            (
                _,
                owner,
                name,
                visibility,
                line_no,
                mode,
                member_type,
                init_value,
            ) = fields

            records.append(
                {
                    "owner":
                        owner,
                    "name":
                        effective_name(
                            name
                        ),
                    "raw_name":
                        name,
                    "visibility":
                        visibility,
                    "line":
                        int(line_no),
                    "mode":
                        mode,
                    "member_type":
                        member_type or None,
                    "init_value":
                        init_value or None,
                }
            )

        elif line.startswith(
            "UNRESOLVED\t"
        ):
            unresolved.append(
                line
            )

    return (
        log,
        records,
        unresolved,
    )


def build_surface(
    raw: list[dict[str, Any]],
    exports: list[
        tuple[str, str]
    ],
    reflection: list[
        dict[str, Any]
    ],
) -> tuple[
    list[dict[str, Any]],
    dict[str, int],
]:
    modules = {
        node["name"]: node
        for node in raw
        if isinstance(
            node,
            dict,
        )
        and node.get("kind")
        == "module"
    }

    reflected = defaultdict(
        list
    )

    reflected_by_name = defaultdict(
        list
    )

    for record in reflection:
        reflected[
            (
                record["owner"],
                record["name"],
                record["line"],
            )
        ].append(
            record
        )

        reflected_by_name[
            (
                record["owner"],
                record["name"],
            )
        ].append(
            record
        )

    rows: list[
        dict[str, Any]
    ] = []

    top_level_count = 0
    public_member_count = 0

    private_member_count = sum(
        1
        for record in reflection
        if record["visibility"]
        == "private"
    )

    enum_member_count = 0

    relocated_reflection_matches = 0

    module_order: dict[
        str,
        int,
    ] = {}

    export_order: dict[
        tuple[str, str],
        int,
    ] = {}

    for index, (
        module_name,
        export_name,
    ) in enumerate(exports):
        module_order.setdefault(
            module_name,
            len(module_order),
        )

        export_order[
            (
                module_name,
                export_name,
            )
        ] = index

    for (
        module_name,
        export_name,
    ) in exports:
        module = modules.get(
            module_name
        )

        if module is None:
            die(
                "missing module "
                "in DMD JSON: "
                + module_name
            )

        matches = [
            node
            for node
            in module.get(
                "members",
                [],
            )
            if isinstance(
                node,
                dict,
            )
            and node.get("name")
            == export_name
            and node.get(
                "protection"
            )
            not in PUBLIC_BLOCKED
        ]

        if not matches:
            die(
                "missing exported "
                "declaration: "
                f"{module_name}."
                f"{export_name}"
            )

        for overload, node in enumerate(
            matches,
            1,
        ):
            rows.append(
                row_for(
                    module=
                        module_name,
                    owner="",
                    node=node,
                    surface_kind=
                        "top-level",
                    overload=
                        overload,
                )
            )

            top_level_count += 1

            impl = template_impl(
                node
            )

            kind = impl.get(
                "kind"
            )

            if kind in {
                "struct",
                "class",
                "union",
            }:
                member_counts = (
                    defaultdict(int)
                )

                for member in impl.get(
                    "members",
                    [],
                ):
                    if not isinstance(
                        member,
                        dict,
                    ):
                        continue

                    name = member.get(
                        "name"
                    )

                    line = source_line(
                        member
                    )

                    if (
                        not name
                        or line is None
                    ):
                        continue

                    if name.startswith(
                        "__unittest"
                    ):
                        continue

                    key = (
                        export_name,
                        name,
                        line,
                    )

                    evidence = (
                        reflected.get(
                            key,
                            [],
                        )
                    )

                    if not evidence:
                        relocated = (
                            reflected_by_name.get(
                                (
                                    export_name,
                                    name,
                                ),
                                [],
                            )
                        )

                        if len(relocated) == 1:
                            evidence = relocated

                            relocated_reflection_matches += 1

                        elif len(relocated) > 1:
                            locations = ", ".join(
                                (
                                    f"{item['line']}:"
                                    f"{item['visibility']}:"
                                    f"{item['mode']}"
                                )
                                for item in relocated
                            )

                            die(
                                "ambiguous relocated reflection "
                                "evidence for "
                                f"{export_name}.{name}: "
                                + locations
                            )

                    public_evidence = [
                        item
                        for item
                        in evidence
                        if item[
                            "visibility"
                        ]
                        == "public"
                    ]

                    private_evidence = [
                        item
                        for item
                        in evidence
                        if item[
                            "visibility"
                        ]
                        == "private"
                    ]

                    if (
                        public_evidence
                        and private_evidence
                    ):
                        die(
                            "conflicting "
                            "visibility evidence "
                            f"for {export_name}."
                            f"{name} "
                            f"line {line}"
                        )

                    if private_evidence:
                        continue

                    if not public_evidence:
                        die(
                            "no reflection "
                            "evidence for "
                            f"{export_name}."
                            f"{name} "
                            f"line {line}"
                        )

                    member_counts[
                        name
                    ] += 1

                    rows.append(
                        row_for(
                            module=
                                module_name,
                            owner=
                                export_name,
                            node=
                                member,
                            surface_kind=
                                "member",
                            overload=
                                member_counts[
                                    name
                                ],
                            visibility=
                                "public",
                        )
                    )

                    field_evidence = [
                        item
                        for item
                        in public_evidence
                        if item["mode"]
                        == "member"
                    ]

                    if len(field_evidence) > 1:
                        die(
                            "multiple field-semantic "
                            "records for "
                            f"{export_name}."
                            f"{name} "
                            f"line {line}"
                        )

                    if field_evidence:
                        rows[-1][
                            "member_type"
                        ] = field_evidence[0][
                            "member_type"
                        ]

                        rows[-1][
                            "init_value"
                        ] = field_evidence[0][
                            "init_value"
                        ]

                    public_member_count += 1

            elif kind == "enum":
                member_counts = (
                    defaultdict(int)
                )

                for member in impl.get(
                    "members",
                    [],
                ):
                    if (
                        not isinstance(
                            member,
                            dict,
                        )
                        or member.get(
                            "kind"
                        )
                        != "enum member"
                    ):
                        continue

                    name = member.get(
                        "name"
                    )

                    if not name:
                        continue

                    member_counts[
                        name
                    ] += 1

                    rows.append(
                        row_for(
                            module=
                                module_name,
                            owner=
                                export_name,
                            node=
                                member,
                            surface_kind=
                                "enum-member",
                            overload=
                                member_counts[
                                    name
                                ],
                            visibility=
                                "public",
                        )
                    )

                    enum_member_count += 1

    def sort_key(
        row: dict[str, Any],
    ) -> tuple[Any, ...]:
        module = row["module"]

        export_name = (
            row["name"]
            if row[
                "surface_kind"
            ]
            == "top-level"
            else row["owner"]
        )

        surface_rank = {
            "top-level": 0,
            "member": 1,
            "enum-member": 2,
        }[
            row["surface_kind"]
        ]

        return (
            module_order[module],
            export_order[
                (
                    module,
                    export_name,
                )
            ],
            surface_rank,
            (
                row["line"]
                if row["line"]
                is not None
                else -1
            ),
            row["name"],
            row["overload"],
        )

    rows.sort(
        key=sort_key
    )

    counts = {
        "package_exports":
            len(exports),
        "top_level_declarations":
            top_level_count,
        "public_aggregate_members":
            public_member_count,
        "private_aggregate_members":
            private_member_count,
        "enum_members":
            enum_member_count,
        "relocated_reflection_matches":
            relocated_reflection_matches,
        "audit_declarations":
            len(rows),
    }

    return (
        rows,
        counts,
    )


API_FINGERPRINT_FIELDS = (
    "module",
    "surface_kind",
    "owner",
    "name",
    "declaration_kind",
    "visibility",
    "template_parameters",
    "constraint",
    "parameters",
    "declaration_type",
    "storage_class",
    "value",
    "spec_value",
    "member_type",
    "init_value",
)


def surface_fingerprint(
    rows: list[dict[str, Any]],
) -> str:
    """
    Fingerprint API semantics rather than source layout.

    Source line numbers, documentation presence, derived UFCS flags,
    and generated overload numbering are intentionally excluded.
    """

    projected = [
        {
            key: row.get(key)
            for key in API_FINGERPRINT_FIELDS
        }
        for row in rows
    ]

    projected.sort(
        key=lambda row: json.dumps(
            row,
            sort_keys=True,
            ensure_ascii=False,
            separators=(",", ":"),
        )
    )

    canonical = json.dumps(
        projected,
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")

    return hashlib.sha256(
        canonical
    ).hexdigest()


def write_outputs(
    out_dir: Path,
    exports: list[
        tuple[str, str]
    ],
    rows: list[
        dict[str, Any]
    ],
    counts: dict[str, int],
    compiler: str,
) -> None:
    json_path = (
        out_dir
        / "public-surface.json"
    )

    tsv_path = (
        out_dir
        / "public-surface.tsv"
    )

    summary_path = (
        out_dir
        / "summary.txt"
    )

    payload = {
        "v1_baseline_commit":
            V1_BASELINE_COMMIT,
        "compiler":
            compiler,
        "package_entry_point":
            "import geo;",
        "counts":
            counts,
        "surface_sha256":
            surface_fingerprint(rows),
        "package_exports": [
            {
                "module": module,
                "name": name,
            }
            for module, name
            in exports
        ],
        "rows":
            rows,
    }

    json_path.write_text(
        json.dumps(
            payload,
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )

    columns = [
        "module",
        "surface_kind",
        "owner",
        "name",
        "qualified_name",
        "overload",
        "declaration_kind",
        "line",
        "visibility",
        "documented",
        "ufcs_candidate",
        "template_parameters",
        "constraint",
        "parameters",
        "first_parameter",
        "declaration_type",
        "storage_class",
        "value",
        "spec_value",
        "member_type",
        "init_value",
    ]

    with tsv_path.open(
        "w",
        newline="",
    ) as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=columns,
            delimiter="\t",
            lineterminator="\n",
        )

        writer.writeheader()

        for row in rows:
            rendered = dict(row)

            for key in (
                "template_parameters",
                "constraint",
                "parameters",
                "first_parameter",
                "declaration_type",
                "storage_class",
                "value",
                "spec_value",
                "member_type",
                "init_value",
            ):
                rendered[key] = (
                    compact(
                        rendered[key]
                    )
                )

            writer.writerow(
                rendered
            )

    lines = [
        (
            "package exports:             "
            f"{counts['package_exports']}"
        ),
        (
            "top-level declarations:      "
            f"{counts['top_level_declarations']}"
        ),
        (
            "public aggregate members:    "
            f"{counts['public_aggregate_members']}"
        ),
        (
            "private aggregate members:   "
            f"{counts['private_aggregate_members']}"
        ),
        (
            "enum members:                "
            f"{counts['enum_members']}"
        ),
        (
            "relocated reflection matches:"
            f" {counts['relocated_reflection_matches']}"
        ),
        (
            "total audit declarations:    "
            f"{counts['audit_declarations']}"
        ),
        (
            "surface sha256:              "
            f"{surface_fingerprint(rows)}"
        ),
    ]

    summary_path.write_text(
        "\n".join(lines)
        + "\n"
    )


def check_v1_baseline(
    counts: dict[str, int],
    unresolved_count: int,
    rows: list[dict[str, Any]],
) -> None:
    actual = dict(counts)

    actual[
        "unresolved_members"
    ] = unresolved_count

    failures = [
        (
            f"{key}: "
            f"expected {expected}, "
            f"got {actual.get(key)}"
        )
        for key, expected
        in V1_EXPECTED.items()
        if actual.get(key)
        != expected
    ]

    fingerprint = surface_fingerprint(
        rows
    )

    if (
        fingerprint
        != V1_EXPECTED_SURFACE_SHA256
    ):
        failures.append(
            "surface sha256: "
            f"expected "
            f"{V1_EXPECTED_SURFACE_SHA256}, "
            f"got {fingerprint}"
        )

    if failures:
        die(
            "v1 baseline mismatch:\n  "
            + "\n  ".join(
                failures
            )
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__
    )

    parser.add_argument(
        "--out-dir",
        default=
            "build/api-audit",
        help=(
            "generated output "
            "directory"
        ),
    )

    parser.add_argument(
        "--check-v1-baseline",
        action="store_true",
        help=(
            "require the frozen v1 "
            "inventory counts recorded "
            "by this tool"
        ),
    )

    args = parser.parse_args()

    root = find_repo_root(
        Path.cwd()
    )

    compiler = "dmd"

    if shutil.which(compiler) is None:
        die("required compiler not found: dmd")

    package_path = (
        root
        / "source"
        / "geo"
        / "package.d"
    )

    if not package_path.is_file():
        die(
            "source/geo/package.d "
            "not found"
        )

    out_dir = (
        root
        / args.out_dir
    ).resolve()

    out_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    exports = (
        parse_package_exports(
            package_path.read_text()
        )
    )

    (
        raw_path,
        public_sources,
    ) = generate_raw_dmd_json(
        root,
        out_dir,
        compiler,
    )

    raw = json.loads(
        raw_path.read_text()
    )

    if not isinstance(
        raw,
        list,
    ):
        die(
            "unexpected DMD JSON "
            "root; expected list"
        )

    modules = {
        node["name"]: node
        for node in raw
        if isinstance(
            node,
            dict,
        )
        and node.get("kind")
        == "module"
    }

    exports = (
        include_local_package_exports(
            exports,
            modules,
        )
    )

    aggregates = (
        exported_aggregate_expressions(
            exports,
            modules,
        )
    )

    (
        reflection_log,
        reflection,
        unresolved,
    ) = generate_reflection_probe(
        root,
        out_dir,
        compiler,
        aggregates,
    )

    rows, counts = (
        build_surface(
            raw,
            exports,
            reflection,
        )
    )

    write_outputs(
        out_dir,
        exports,
        rows,
        counts,
        compiler,
    )

    if args.check_v1_baseline:
        check_v1_baseline(
            counts,
            len(unresolved),
            rows,
        )

    print(
        "public modules:              "
        f"{len(public_sources)}"
    )

    print(
        "package exports:             "
        f"{counts['package_exports']}"
    )

    print(
        "top-level declarations:      "
        f"{counts['top_level_declarations']}"
    )

    print(
        "public aggregate members:    "
        f"{counts['public_aggregate_members']}"
    )

    print(
        "private aggregate members:   "
        f"{counts['private_aggregate_members']}"
    )

    print(
        "enum members:                "
        f"{counts['enum_members']}"
    )

    print(
        "relocated reflection matches:"
        f" {counts['relocated_reflection_matches']}"
    )

    print(
        "unresolved members:          "
        f"{len(unresolved)}"
    )

    print(
        "total audit declarations:    "
        f"{counts['audit_declarations']}"
    )

    print(
        "surface sha256:              "
        f"{surface_fingerprint(rows)}"
    )

    print()

    if args.check_v1_baseline:
        print(
            "PASS: frozen v1 "
            "public-surface baseline"
        )
        print()

    print("Generated:")

    print(
        "  "
        + str(
            out_dir
            / "public-surface.json"
        )
    )

    print(
        "  "
        + str(
            out_dir
            / "public-surface.tsv"
        )
    )

    print(
        "  "
        + str(
            out_dir
            / "summary.txt"
        )
    )

    print(
        "  "
        + str(raw_path)
    )

    print(
        "  "
        + str(reflection_log)
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(
        main()
    )
