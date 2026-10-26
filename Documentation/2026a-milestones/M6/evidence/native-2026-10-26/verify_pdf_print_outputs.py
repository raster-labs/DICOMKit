#!/usr/bin/env python3
"""Read-only PDF pixel qualification of previously captured synthetic print output."""
import argparse
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageChops, ImageStat
from pypdf import PdfReader


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pixels(image):
    image = image.convert("RGBA")
    return {"size": list(image.size), "rgbaSHA256": digest(image.tobytes())}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--renderer", type=Path, default=Path("/Users/raster/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/override/pdftoppm"))
    args = parser.parse_args()
    root = args.root.resolve()
    out = root / "pdf-raster-verification"
    out.mkdir(exist_ok=True)
    checks, artifacts, rendering_observations = [], {}, []

    def check(name, passed, detail=None):
        checks.append({"check": name, "status": "Passed" if passed else "Failed", "detail": detail})

    cases = [
        ("native-simulation", "gui-simulated/native-001.pdf", "gui-simulated/native-001.tiff"),
        ("cli-simulation", "cli-simulated-post-repair/native-001.pdf", "cli-simulated-post-repair/native-001.tiff"),
        ("native-gray-received", "gui-received/native-001.pdf", "gui-received/native-001.png"),
        ("native-rgb-received", "gui-received/native-002.pdf", "gui-received/native-002.png"),
    ]
    for name, pdf, raster in cases:
        pdf, raster = root / pdf, root / raster
        original = pdf.read_bytes()
        reader = PdfReader(pdf)
        check(name + " one unencrypted page", len(reader.pages) == 1 and not reader.is_encrypted)
        page = reader.pages[0]
        check(name + " physical film dimensions", [float(v) for v in page.mediabox] == [0, 0, 1008, 1224]
              and int(page.get("/Rotate", 0)) == 0, {"mediaBoxPoints": [float(v) for v in page.mediabox]})
        images = list(page.images)
        check(name + " one embedded film image", len(images) == 1)
        operations = page.get_contents().operations
        matrices = [[float(v) for v in args] for args, operator in operations if operator == b"cm"]
        drawn = [str(args[0]) for args, operator in operations if operator == b"Do"]
        check(name + " complete film image mapped to physical page",
              matrices == [[1008, 0, 0, 1224, 0, 0]] and drawn == ["/Im1"],
              {"matrices": matrices, "imagesDrawn": drawn})
        with Image.open(raster) as companion:
            expected = pixels(companion)
            expected_image = companion.convert("RGBA")
        embedded = pixels(images[0].image)
        check(name + " independent embedded pixels equal companion raster", embedded == expected,
              {"PDFImage": embedded, "companion": expected})
        prefix = out / name
        command = [str(args.renderer), "-f", "1", "-singlefile", "-r", "36", "-png", str(pdf), str(prefix)]
        result = subprocess.run(command, text=True, capture_output=True, timeout=60)
        (out / (name + ".render.json")).write_text(json.dumps({"argv": command, "exit": result.returncode,
            "stdout": result.stdout, "stderr": result.stderr}, indent=2) + "\n")
        check(name + " renderer completed", result.returncode == 0, result.stderr)
        result.check_returncode()
        with Image.open(prefix.with_suffix(".png")) as rendered:
            decoded = pixels(rendered)
            rendered_image = rendered.convert("RGBA")
        check(name + " rendered film size", decoded["size"] == expected["size"], decoded)
        # PDF asks for interpolation and supplies an ICC profile. An independent
        # renderer therefore need not match the unrendered TIFF/PNG byte-for-byte.
        # Preserve this observation; qualify exact stored pixels above and exact
        # CLI/native complete-page rendering below, without a tolerance waiver.
        image_object = page["/Resources"]["/XObject"]["/Im1"]
        rendering_observations.append({"case": name, "exactCompanionEquality": decoded == expected,
            "PDFInterpolate": bool(image_object.get("/Interpolate", False)),
            "PDFColorSpace": str(image_object.get("/ColorSpace")),
            "meanAbsoluteRGBAError": ImageStat.Stat(ImageChops.difference(rendered_image, expected_image)).mean,
            "meaning": "Cross-format renderer interpolation/color-management observation; not the CLI/native parity oracle"})
        check(name + " source PDF unchanged", pdf.read_bytes() == original)
        artifacts[name] = {"pdf": str(pdf), "pdfSHA256": digest(original), "companion": str(raster),
                           "companionSHA256": digest(raster.read_bytes()), "embeddedPixels": embedded,
                           "renderedPixels": decoded, "renderedPNG": str(prefix.with_suffix(".png"))}
    check("CLI/native simulation decoded PDF pixel parity",
          artifacts["native-simulation"]["renderedPixels"] == artifacts["cli-simulation"]["renderedPixels"])
    report = {"recordedUTC": datetime.now(timezone.utc).isoformat(),
              "purpose": "M6.2(2) finite software PDF raster comparison of existing synthetic print artifacts",
              "methods": ["pypdf independently decodes embedded film images; exact pixels equal saved TIFF/PNG", "Bundled pdftoppm renders complete pages at original36DPI; compare exact CLI/native simulation RGBA pixels"],
              "renderer": str(args.renderer), "rendererSHA256": digest(args.renderer.read_bytes()),
              "counts": {s: sum(c["status"] == s for c in checks) for s in ["Passed", "Failed"]},
              "artifacts": artifacts, "checks": checks, "crossFormatRenderingObservations": rendering_observations,
              "initialOracle": "pdf-raster-verification.initial-cross-format-oracle.json retains four failed exact rendered-PDF-vs-unrendered-raster comparisons; explicit PDF Interpolate=true and ICC profiles explain why this is not the required CLI/native parity assertion.",
              "limits": ["No DICOMKit product, UI, print job or peer was run; original PDFs/raster files are unchanged.",
                         "This finite pixel/page comparison does not establish physical printer, calibration, diagnostic display or printed-film quality."]}
    (root / "pdf-raster-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["counts"]))
    return 1 if report["counts"]["Failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
