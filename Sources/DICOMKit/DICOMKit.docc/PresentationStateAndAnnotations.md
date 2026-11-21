# Presentation States and Annotations (GSPS, CSPS, Pseudo-CSPS, Blending & SR)

Create, save, load, discover, and render DICOM Softcopy Presentation States and Structured Report annotations across studies, series, images, and multi-frame instances.

## Overview

`DICOMKit` provides a unified, DICOM-standard-conformant API for all four Softcopy Presentation State IODs (PS3.3 Section A.33) and their bidirectional integration with DICOM Structured Reporting (PS3.16 TID 1500 & TID 2010):

- **Grayscale Softcopy Presentation State (GSPS)** — `1.2.840.10008.5.1.4.1.1.11.1` (PS3.3 Section A.33.1)
- **Color Softcopy Presentation State (CSPS)** — `1.2.840.10008.5.1.4.1.1.11.2` (PS3.3 Section A.33.2)
- **Pseudo-Color Softcopy Presentation State (PCSPS)** — `1.2.840.10008.5.1.4.1.1.11.3` (PS3.3 Section A.33.3)
- **Blending Softcopy Presentation State** — `1.2.840.10008.5.1.4.1.1.11.4` (PS3.3 Section A.33.4)

Any application (including `DICOMStudio` or third-party iOS, macOS, and visionOS viewers) can use this common API without sidecar files.

## Creating and Saving Annotations for an Image, Series, or Study

Use ``PresentationStateManager`` and ``DICOMAnnotation`` to create presentation states and optional companion Structured Reports (`TID 1500 Measurement Report` and `TID 2010 Key Object Selection`):

```swift
import DICOMCore
import DICOMKit

let ruler = DICOMAnnotation.ruler(
    from: DICOMAnnotationPoint(x: 120, y: 180),
    to: DICOMAnnotationPoint(x: 240, y: 180),
    distanceMM: 32.4,
    referencedSOPInstanceUID: imageSOPInstanceUID,
    referencedFrameNumbers: [1]
)

let roi = DICOMAnnotation.ellipse(
    topLeft: DICOMAnnotationPoint(x: 200, y: 210),
    bottomRight: DICOMAnnotationPoint(x: 290, y: 280),
    measurements: [.areaMM2(410.5), .meanHU(48.2)],
    referencedSOPInstanceUID: imageSOPInstanceUID,
    referencedFrameNumbers: [1]
)

let package = try PresentationStateManager.create(
    forImages: [ctSlice1DataSet, ctSlice2DataSet],
    configuration: PresentationStateConfiguration(
        presentationLabel: "LESION_REVIEW",
        annotations: [ruler, roi],
        voiLUT: .window(center: 40, width: 400, explanation: "Soft Tissue", function: .linear),
        palette: .hotIron, // Automatically selects Pseudo-CSPS (1.2.840.10008.5.1.4.1.1.11.3)
        companionSROptions: .both
    )
)

// Save PR (.dcm), TID 1500 Measurement Report (.dcm), and TID 2010 Key Object Selection (.dcm)
let savedFiles = try PresentationStateManager.save(package, to: studyOutputDirectory)
```

## Capturing and Restoring Live Viewport State

Use ``PresentationStateViewportBridge`` to translate between a viewer's live viewport state (window/level, zoom, pan, rotation, horizontal/vertical flip, inversion, pseudo-color palette, and annotations) and a ``PresentationStateDocument``:

```swift
let viewportState = PresentationStateViewportState(
    windowCenter: 50,
    windowWidth: 350,
    rescaleSlope: 1.0,
    rescaleIntercept: -1024.0,
    rescaleType: "HU",
    zoom: 1.5,
    panX: 0.1,
    panY: -0.05,
    rotationDegrees: 90,
    flipHorizontal: false,
    flipVertical: false,
    invert: false,
    palette: .pet,
    annotations: [ruler]
)

let document = PresentationStateViewportBridge.capture(
    viewport: viewportState,
    seriesInstanceUID: seriesUID,
    sopClassUID: sopClassUID,
    sopInstanceUID: imageSOPInstanceUID,
    photometricInterpretation: "MONOCHROME2",
    imageWidth: 512,
    imageHeight: 512,
    presentationLabel: "PET_VIEW"
)

// Later, restore for any target viewport size:
let restored = PresentationStateViewportBridge.restore(
    document,
    forImage: imageSOPInstanceUID,
    frameNumber: 1,
    imageWidth: 512,
    imageHeight: 512,
    viewportWidth: 1024,
    viewportHeight: 768,
    photometricInterpretation: "MONOCHROME2"
)
```

## Discovering and Loading PR and SR Annotations for a Study

Use ``PresentationStateManager/discover(in:recursive:imageWidth:imageHeight:targetCoordinateSpace:)`` to scan a directory or study for all GSPS, CSPS, Pseudo-CSPS, Blending, and SR documents:

```swift
let collection = try PresentationStateManager.discover(in: studyDirectoryURL)

// Filter Presentation States for a specific image and frame
let statesForFrame = collection.presentationStates(
    sopInstanceUID: imageSOPInstanceUID,
    frameNumber: 1
)

// Retrieve all combined annotations from both PR and SR instances
let annotations = collection.allAnnotations(
    forImage: imageSOPInstanceUID,
    frameNumber: 1
)
```

## Rendering Pixels with GSPS, CSPS, Pseudo-CSPS, and Blending

Use ``PresentationStateApplicator`` to render a `CGImage` with the full DICOM display pipeline:

```swift
if let pixelData = imageDataSet.pixelData() {
    let cgImage = PresentationStateApplicator.apply(
        document,
        to: pixelData,
        frameIndex: 0,
        sopInstanceUID: imageSOPInstanceUID
    )
}
```
