"""Negative controls for the documentation publication gate (no Swift build)."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("build_docc_docs", Path(__file__).with_name("build_docc_docs.py"))
docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(docs)


class DocumentationGateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)

    def archive(self):
        symbol_identifier = "doc://org.dicomkit.DICOMCore/documentation/DICOMCore/Tag"
        for name in ("index.html", "documentation/dicomcore/index.html", "documentation/dicomcore/tag/index.html"):
            file = self.root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("<!doctype html><title>DICOMCore</title>")
        api = self.root / "data/documentation/dicomcore.json"
        api.parent.mkdir(parents=True, exist_ok=True)
        api.write_text(json.dumps({"kind": "symbol", "metadata": {"title": "DICOMCore", "symbolKind": "module"},
                                   "identifier": {"url": "doc://org.dicomkit.DICOMCore/documentation/DICOMCore"},
                                   "topicSections": [{"identifiers": [symbol_identifier]}],
                                   "references": {symbol_identifier: {"kind": "symbol", "url": "/documentation/dicomcore/tag"}}}))
        symbol = api.parent / "dicomcore/tag.json"
        symbol.parent.mkdir(parents=True, exist_ok=True)
        symbol.write_text(json.dumps({"kind": "symbol", "metadata": {"symbolKind": "struct"},
                                     "identifier": {"url": symbol_identifier}}))
        return api

    def test_rendered_api_archive_passes(self):
        self.archive()
        self.assertEqual(docs.validate_archive(self.root, "DICOMCore"), 1)

    def test_article_only_archive_cannot_pass_as_an_api_module(self):
        api = self.archive()
        document = json.loads(api.read_text())
        document["kind"] = "article"
        api.write_text(json.dumps(document))
        with self.assertRaisesRegex(ValueError, "not an API module"):
            docs.validate_archive(self.root, "DICOMCore")
        document["kind"] = "symbol"
        for reference in document["references"].values():
            reference["kind"] = "article"
        api.write_text(json.dumps(document))
        with self.assertRaisesRegex(ValueError, "no local symbol pages"):
            docs.validate_archive(self.root, "DICOMCore")

    def test_every_indexed_symbol_requires_json_and_static_route(self):
        self.archive()
        for name in ("data/documentation/dicomcore/tag.json", "documentation/dicomcore/tag/index.html"):
            with self.subTest(missing=name):
                file = self.root / name
                original = file.read_bytes()
                file.unlink()
                with self.assertRaisesRegex(ValueError, "missing or empty indexed API output"):
                    docs.validate_archive(self.root, "DICOMCore")
                file.write_bytes(original)

    def test_one_good_symbol_cannot_hide_another_missing_symbol(self):
        api = self.archive()
        document = json.loads(api.read_text())
        missing = "doc://org.dicomkit.DICOMCore/documentation/DICOMCore/Missing"
        document["topicSections"].append({"identifiers": [missing]})
        document["references"][missing] = {"kind": "symbol", "url": "/documentation/dicomcore/missing"}
        api.write_text(json.dumps(document))
        with self.assertRaisesRegex(ValueError, "missing or empty indexed API output"):
            docs.validate_archive(self.root, "DICOMCore")

    def test_dangling_reference_or_wrong_symbol_target_fails(self):
        api = self.archive()
        document = json.loads(api.read_text())
        reference = document["references"].popitem()
        api.write_text(json.dumps(document))
        with self.assertRaisesRegex(ValueError, "missing indexed topic reference"):
            docs.validate_archive(self.root, "DICOMCore")
        document["references"][reference[0]] = reference[1]
        api.write_text(json.dumps(document))
        symbol = self.root / "data/documentation/dicomcore/tag.json"
        for invalid in ({"kind": "article"}, {"kind": "symbol", "metadata": {"symbolKind": "struct"},
                                             "identifier": {"url": reference[0] + "Wrong"}}):
            symbol.write_text(json.dumps(invalid))
            with self.assertRaisesRegex(ValueError, "symbol identity"):
                docs.validate_archive(self.root, "DICOMCore")

    def test_external_dependency_symbols_need_no_local_copy(self):
        api = self.archive()
        document = json.loads(api.read_text())
        for identifier, url in (("doc://org.dicomkit.DICOMCore/documentation/Swift/Int", "/documentation/swift/int"),
                                ("doc://org.external/documentation/DICOMCore/Foreign", "https://example.org/foreign")):
            document["topicSections"][0]["identifiers"].append(identifier)
            document["references"][identifier] = {"kind": "symbol", "url": url}
        api.write_text(json.dumps(document))
        self.assertEqual(docs.validate_archive(self.root, "DICOMCore"), 1)

    def test_landing_page_without_api_fails(self):
        (self.root / "index.html").write_text("A plausible landing page")
        with self.assertRaisesRegex(ValueError, "missing or empty"):
            docs.validate_archive(self.root, "DICOMCore")

    def test_wrong_or_empty_api_index_fails(self):
        api = self.archive()
        document = json.loads(api.read_text())
        document["metadata"]["title"] = "DICOMKit"
        api.write_text(json.dumps(document))
        with self.assertRaisesRegex(ValueError, "identity"):
            docs.validate_archive(self.root, "DICOMCore")
        document["metadata"]["title"] = "DICOMCore"
        document["topicSections"] = []
        api.write_text(json.dumps(document))
        with self.assertRaisesRegex(ValueError, "no topics"):
            docs.validate_archive(self.root, "DICOMCore")

    def test_empty_or_wrong_symbol_graph_fails(self):
        graph = self.root / "DICOMCore.symbols.json"
        for module, symbols in [("DICOMCore", []), ("DICOMKit", [{"identifier": "wrong"}])]:
            graph.write_text(json.dumps({"module": {"name": module}, "symbols": symbols}))
            with self.assertRaisesRegex(ValueError, "nonempty API symbol graph"):
                docs.validate_graph(graph, "DICOMCore")

    def test_stale_output_cannot_make_a_failed_build_look_successful(self):
        self.archive()
        with self.assertRaisesRegex(ValueError, "stale archives"):
            docs.prepare_output(self.root)

    def test_failed_tool_is_not_swallowed(self):
        with self.assertRaises(subprocess.CalledProcessError) as failure:
            docs.run([sys.executable, "-c", "raise SystemExit(37)"])
        self.assertEqual(failure.exception.returncode, 37)


if __name__ == "__main__":
    unittest.main()
