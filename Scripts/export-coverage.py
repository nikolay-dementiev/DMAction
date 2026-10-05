#!/usr/bin/env python3
"""Export library line coverage from an Xcode result bundle to LCOV."""

import argparse
import json
from pathlib import Path
import subprocess
import sys


def xccov(bundle, *options):
    return json.loads(subprocess.check_output(
        ["xcrun", "xccov", "view", *options, "--json", str(bundle)], text=True
    ))


def export(bundle, target, root):
    source_root = (root / "Sources" / target).resolve()
    report = xccov(bundle, "--report")
    paths = set()
    for entry in report["targets"]:
        if entry["name"].split(".")[0] != target:
            continue
        for file in entry["files"]:
            path = Path(file["path"]).resolve()
            if source_root in path.parents and file["executableLines"] > 0:
                paths.add(path)
    if not paths:
        raise ValueError(f"No executable library files found for {target}")

    records = []
    for path in sorted(paths):
        archive = xccov(bundle, "--archive", "--file", str(path))
        lines = {}
        for entries in archive.values():
            for entry in entries:
                if entry["isExecutable"]:
                    line, count = entry["line"], entry["executionCount"]
                    if line <= 0 or count < 0:
                        raise ValueError(f"Invalid line coverage for {path.name}")
                    # Multiple instrumented images may contain the same source line.
                    lines[line] = max(lines.get(line, 0), count)
        if not lines:
            raise ValueError(f"No executable lines in archive for {path.name}")
        records.extend(["TN:", f"SF:{path.relative_to(root).as_posix()}"])
        records.extend(f"DA:{line},{count}" for line, count in sorted(lines.items()))
        records.extend([
            f"LF:{len(lines)}", f"LH:{sum(count > 0 for count in lines.values())}",
            "end_of_record",
        ])
    return "\n".join(records) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("target")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        content = export(args.bundle, args.target, root)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content, encoding="utf-8")
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"export-coverage: {error}", file=sys.stderr)
        return 1
    print(f"export-coverage: wrote {args.output} ({content.count('SF:')} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
