#!/usr/bin/env python3
"""Regression checks for filtering and preserving Xcode line coverage."""

import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("exporter", Path(__file__).with_name("export-coverage.py"))
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class CoverageExportTests(unittest.TestCase):
    root = Path("/fixture/repository")
    source = root / "Sources/Library/File.swift"

    def report(self, paths=None):
        files = [{"path": str(path), "executableLines": 2} for path in (paths or [self.source])]
        return {"targets": [{"name": "Library.framework", "files": files}]}

    def render(self, report, archive):
        with patch.object(exporter, "xccov", side_effect=[report, archive]):
            return exporter.export(Path("result.xcresult"), "Library", self.root)

    def test_preserves_uncovered_lines_and_merges_duplicate_image_lines(self):
        result = self.render(self.report(), {str(self.source): [
            {"line": 1, "isExecutable": False},
            {"line": 2, "isExecutable": True, "executionCount": 0},
            {"line": 3, "isExecutable": True, "executionCount": 0},
            {"line": 3, "isExecutable": True, "executionCount": 7},
        ]})
        self.assertEqual(result, "TN:\nSF:Sources/Library/File.swift\nDA:2,0\nDA:3,7\nLF:2\nLH:1\nend_of_record\n")

    def test_filters_tests_dependencies_and_other_targets(self):
        report = self.report([self.source, self.root / "Tests/Test.swift",
                              self.root / ".build/checkouts/Library/Sources/Library/File.swift",
                              self.root / "Sources/LibraryExtra/File.swift"])
        report["targets"].append({"name": "LibraryTests", "files": [{
            "path": str(self.root / "Sources/Library/Injected.swift"), "executableLines": 1,
        }]})
        result = self.render(report, {str(self.source): [
            {"line": 2, "isExecutable": True, "executionCount": 1},
        ]})
        self.assertEqual(result.count("SF:"), 1)
        self.assertNotIn(str(self.root), result)

    def test_missing_target_fails_instead_of_producing_empty_report(self):
        with self.assertRaises(ValueError):
            self.render({"targets": []}, {})

    def test_missing_archive_lines_fails(self):
        with self.assertRaises(ValueError):
            self.render(self.report(), {})

    def test_invalid_counts_fail(self):
        with self.assertRaises(ValueError):
            self.render(self.report(), {str(self.source): [
                {"line": 2, "isExecutable": True, "executionCount": -1},
            ]})

    def test_xccov_failure_is_not_treated_as_coverage(self):
        with patch.object(exporter, "xccov", side_effect=subprocess.CalledProcessError(1, "xccov")):
            with self.assertRaises(subprocess.CalledProcessError):
                exporter.export(Path("result.xcresult"), "Library", self.root)


if __name__ == "__main__":
    unittest.main()
