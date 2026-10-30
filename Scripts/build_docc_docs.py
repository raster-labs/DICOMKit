#!/usr/bin/env python3
"""Build and validate the five public DocC archives using the Xcode toolchain.

This intentionally does not invoke the optional Swift-DocC package plugin.
Compiler-emitted symbol graphs keep dependency search paths under SwiftPM's
control and avoid publishing article-only archives when API generation fails.
"""

import argparse
import hashlib
import html
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit


MODULES = ("DICOMCore", "DICOMDictionary", "DICOMKit", "DICOMNetwork", "DICOMWeb")
REPOSITORY = Path(__file__).resolve().parent.parent


def run(arguments):
    print("+ " + shlex.join(str(value) for value in arguments), flush=True)
    subprocess.run(arguments, cwd=REPOSITORY, check=True)


def validate_graph(path, module):
    graph = json.loads(path.read_text())
    if graph.get("module", {}).get("name") != module or not graph.get("symbols"):
        raise ValueError(f"{path}: missing nonempty API symbol graph for {module}")
    return len(graph["symbols"])


def validate_archive(path, module):
    route = module.lower()
    for required in ("index.html", f"documentation/{route}/index.html", f"data/documentation/{route}.json"):
        file = path / required
        if not file.is_file() or file.stat().st_size == 0:
            raise ValueError(f"{module}: missing or empty rendered output {file}")
    root = json.loads((path / f"data/documentation/{route}.json").read_text())
    identifier = root.get("identifier", {}).get("url", "")
    if root.get("metadata", {}).get("title") != module or not identifier.lower().endswith(f"/documentation/{route}"):
        raise ValueError(f"{module}: rendered module identity does not match its archive")
    if root.get("kind") != "symbol" or root.get("metadata", {}).get("symbolKind") != "module":
        raise ValueError(f"{module}: rendered root is not an API module")
    if not root.get("topicSections"):
        raise ValueError(f"{module}: rendered API index has no topics")
    module_identifier = urlsplit(identifier)
    references = root.get("references", {})
    symbols = set()
    for section in root["topicSections"]:
        for topic_identifier in section.get("identifiers", []):
            topic = urlsplit(topic_identifier)
            # Imported symbols can belong to another bundle or module. Their
            # pages need not be duplicated inside this module's archive.
            if (topic.scheme != module_identifier.scheme or topic.netloc != module_identifier.netloc
                    or not topic.path.lower().startswith(module_identifier.path.lower() + "/")):
                continue
            reference = references.get(topic_identifier)
            if reference is None:
                raise ValueError(f"{module}: missing indexed topic reference {topic_identifier}")
            if reference.get("kind") != "symbol":
                continue
            target = urlsplit(reference.get("url", ""))
            target_path = unquote(target.path)
            if (target.scheme or target.netloc or target.query or target.fragment
                    or not target_path.startswith(f"/documentation/{route}/")
                    or ".." in Path(target_path).parts):
                raise ValueError(f"{module}: invalid local API route {reference.get('url')}")
            relative = target_path.lstrip("/")
            symbol_json = path / "data" / (relative + ".json")
            symbol_html = path / relative / "index.html"
            for file in (symbol_json, symbol_html):
                if not file.is_file() or file.stat().st_size == 0:
                    raise ValueError(f"{module}: missing or empty indexed API output {file}")
            symbol = json.loads(symbol_json.read_text())
            if (symbol.get("kind") != "symbol"
                    or not symbol.get("metadata", {}).get("symbolKind")
                    or symbol.get("metadata", {}).get("symbolKind") == "module"
                    or symbol.get("identifier", {}).get("url") != topic_identifier):
                raise ValueError(f"{module}: indexed API symbol identity does not match {symbol_json}")
            symbols.add(topic_identifier)
    if not symbols:
        raise ValueError(f"{module}: rendered API index has no local symbol pages")
    return len(symbols)


def prepare_output(path):
    if path.exists() and (not path.is_dir() or any(path.iterdir())):
        raise ValueError(f"Output must be a new or empty directory, to exclude stale archives: {path}")
    path.mkdir(parents=True, exist_ok=True)


def write_index(output):
    links = "\n".join(
        f'<li><a href="{module}/documentation/{module.lower()}/">{html.escape(module)}</a></li>'
        for module in MODULES
    )
    (output / "index.html").write_text(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DICOMKit API Documentation</title>
<style>body{{font:17px system-ui;max-width:760px;margin:4rem auto;padding:0 1.5rem;line-height:1.7}}a{{color:#0657b5}}li{{margin:.7rem 0}}</style>
</head><body><h1>DICOMKit API Documentation</h1>
<p>Reference documentation for the DICOMKit libraries.</p><ul>{links}</ul>
<p><a href="https://github.com/raster-labs/DICOMKit">Source repository</a></p>
</body></html>
""")
    (output / ".nojekyll").touch()


def build(args):
    output = args.output_path.resolve()
    scratch = args.scratch_path.resolve()
    prepare_output(output)
    scratch.mkdir(parents=True, exist_ok=True)
    common = ["swift", "build", "--disable-automatic-resolution", "--scratch-path", str(scratch), "--jobs", str(args.jobs)]
    if args.cache_path:
        common += ["--cache-path", str(args.cache_path.resolve())]
    # A fresh graph destination changes the compiler invocation: incremental
    # builds cannot silently reuse an old graph after source or toolchain changes.
    with tempfile.TemporaryDirectory(prefix="docc-symbols-", dir=scratch) as temporary:
        graph_dir = Path(temporary)
        for flag in ("-enable-cross-import-overlays", "-emit-symbol-graph", "-emit-symbol-graph-dir", str(graph_dir)):
            common += ["-Xswiftc", "-Xfrontend", "-Xswiftc", flag]
        summary = {}
        for module in MODULES:
            run(common + ["--target", module])
            main_graph = graph_dir / f"{module}.symbols.json"
            symbol_count = validate_graph(main_graph, module)
            isolated = graph_dir / module
            isolated.mkdir()
            for graph in graph_dir.glob(f"{module}*.symbols.json"):
                if graph.name == main_graph.name or graph.name.startswith(module + "@"):
                    shutil.copyfile(graph, isolated / graph.name)
            base = "/".join(part for part in (args.hosting_base_path.strip("/"), module) if part)
            archive = output / module
            run(["xcrun", "docc", "convert", str(REPOSITORY / "Sources" / module / f"{module}.docc"),
                 "--additional-symbol-graph-dir", str(isolated), "--output-path", str(archive),
                 "--fallback-bundle-identifier", f"org.dicomkit.{module}",
                 "--transform-for-static-hosting", "--hosting-base-path", base])
            rendered_symbols = validate_archive(archive, module)
            summary[module] = {"public_symbols": symbol_count,
                               "rendered_index_symbols": rendered_symbols,
                               "symbol_graph_sha256": hashlib.sha256(main_graph.read_bytes()).hexdigest(),
                               "hosting_base_path": base, "result": "Passed"}
        write_index(output)
        (output / "build-verification.json").write_text(json.dumps({"modules": summary, "result": "Passed"}, indent=2) + "\n")
    print(f"Validated all {len(MODULES)} documentation modules at {output}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-path", type=Path, default=Path("docs"))
    parser.add_argument("--scratch-path", type=Path, default=Path(".build"))
    parser.add_argument("--cache-path", type=Path)
    parser.add_argument("--hosting-base-path", default="DICOMKit", help="Site prefix, empty for a root/custom-domain site")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    try:
        build(args)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"::error::Documentation build failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
