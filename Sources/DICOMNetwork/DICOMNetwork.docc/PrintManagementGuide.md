# Print Management Guide

Learn how to use DICOM Print Management services to print medical images to DICOM-compliant printers.

## Overview

DICOMNetwork provides complete DICOM Print Management Service Class support (PS3.4 Annex H) for printing medical images to film printers and hard copy devices. The print services support both low-level workflow control and high-level convenience APIs.

### Key Features

- **Complete Print Workflow**: Film Session, Film Box, Image Box management
- **High-Level API**: Simple one-line printing with automatic workflow
- **Print Templates**: Pre-configured layouts for common scenarios
- **Image Preparation**: Automatic windowing, resizing, and annotation
- **Print Queue**: Priority-based job scheduling with retry logic
- **Multiple Printers**: Printer registry for managing multiple devices
- **Progress Tracking**: Real-time progress updates with AsyncSequence

## Quick Start: Simple Printing

The simplest way to print a single DICOM image:

```swift
import DICOMNetwork

// Configure printer connection
let config = PrintConfiguration(
    host: "192.168.1.100",
    port: 11112,
    callingAETitle: "WORKSTATION",
    calledAETitle: "PRINT_SCP"
)

// Print with default settings
let result = try await DICOMPrintService.printImage(
    configuration: config,
    imageData: dicomPixelData,
    options: .default
)

print("Print job created: \(result.printJobUID)")
```

### Print Multiple Images

Print multiple images with automatic layout selection:

```swift
// Print 4 images in a 2×2 grid (automatic layout)
let result = try await DICOMPrintService.printImages(
    configuration: config,
    images: [image1, image2, image3, image4],
    options: PrintOptions(
        filmSize: .size14InX17In,
        filmOrientation: .landscape,
        numberOfCopies: 2
    )
)
```

## Print Options and Presets

Configure print quality with preset options:

```swift
// High quality printing
let result = try await DICOMPrintService.printImage(
    configuration: config,
    imageData: pixelData,
    options: .highQuality  // 14×17", high magnification, clear film
)

// Mammography preset
let result = try await DICOMPrintService.printImage(
    configuration: config,
    imageData: mammoPixelData,
    options: .mammography  // 14×17", MAMMO BLUE FILM, high priority
)

// Draft printing
let result = try await DICOMPrintService.printImage(
    configuration: config,
    imageData: pixelData,
    options: .draft  // 8.5×11", paper medium, low quality
)
```

### Custom Print Options

Create custom print configurations:

```swift
let options = PrintOptions(
    filmSize: .size11InX14In,
    filmOrientation: .portrait,
    magnificationType: .cubic,
    mediumType: .blueFilm,
    numberOfCopies: 3,
    priority: .high,
    filmDestination: .magazine
)
```

## Print Templates

Use templates for common multi-image layouts:

```swift
// Single large image
let template = SingleImageTemplate()
let result = try await DICOMPrintService.printWithTemplate(
    configuration: config,
    images: [ctImage],
    template: template
)

// Side-by-side comparison
let comparisonTemplate = ComparisonTemplate()
let result = try await DICOMPrintService.printWithTemplate(
    configuration: config,
    images: [preTreatment, postTreatment],
    template: comparisonTemplate
)

// 3×3 grid for 9 images
let gridTemplate = GridTemplate(rows: 3, columns: 3)
let result = try await DICOMPrintService.printWithTemplate(
    configuration: config,
    images: multiPhaseImages,
    template: gridTemplate
)

// Multi-phase temporal series (3 rows × 4 columns)
let multiPhaseTemplate = MultiPhaseTemplate(rows: 3, columns: 4)
let result = try await DICOMPrintService.printWithTemplate(
    configuration: config,
    images: temporalSeries,
    template: multiPhaseTemplate
)
```

## Progress Tracking

Monitor printing progress with real-time updates:

```swift
for try await progress in DICOMPrintService.printImagesWithProgress(
    configuration: config,
    images: images,
    options: .default
) {
    switch progress.phase {
    case .connecting:
        print("Connecting to printer...")
    case .queryingPrinter:
        print("Querying printer status...")
    case .preparingImages:
        print("Preparing images: \(Int(progress.progress * 100))%")
    case .uploadingImages:
        print("Uploading images: \(progress.current)/\(progress.total)")
    case .printing:
        print("Printing...")
    case .completed:
        print("Print job completed!")
    default:
        print("\(progress.phase): \(progress.message)")
    }
}
```

## Image Preparation Pipeline

Prepare images for optimal print quality:

```swift
import DICOMKit

// Preprocess DICOM image
let preprocessor = ImagePreprocessor()
let preparedImage = try await preprocessor.prepareForPrint(
    dataSet: dicomDataSet,
    targetSize: CGSize(width: 1024, height: 1024),
    colorMode: .grayscale
)

// Resize with quality control
let resizer = ImageResizer()
let resizedData = try await resizer.resize(
    pixelData: preparedImage.pixelData,
    from: CGSize(width: 512, height: 512),
    to: CGSize(width: 1024, height: 1024),
    mode: .fit,  // Preserve aspect ratio
    quality: .high  // Use bicubic interpolation
)

// Add annotations
let annotator = AnnotationRenderer()
let annotatedData = try await annotator.addAnnotations(
    to: resizedData,
    imageSize: CGSize(width: 1024, height: 1024),
    annotations: [
        PrintAnnotation(text: "L", position: .topLeft, fontSize: 24, color: .white),
        PrintAnnotation(text: "Patient: John Doe", position: .bottomLeft, fontSize: 16, color: .white),
        PrintAnnotation(text: "CT Chest", position: .topRight, fontSize: 16, color: .white)
    ]
)
```

## Print Queue Management

Use a print queue for managing multiple jobs:

```swift
// Create queue with retry policy
let queue = PrintQueue(
    maxHistorySize: 100,
    retryPolicy: PrintRetryPolicy(
        maxRetries: 3,
        initialDelay: 2.0,
        maxDelay: 30.0,
        backoffMultiplier: 2.0
    )
)

// Add high priority job
let urgentJob = PrintJob(
    configuration: config,
    imageURLs: [URL(fileURLWithPath: "/path/to/urgent.dcm")],
    options: .highQuality,
    priority: .high,
    label: "Urgent CT - Room 5"
)
let jobID = await queue.enqueue(job: urgentJob)

// Check job status
if let status = await queue.status(jobID: jobID) {
    switch status {
    case .queued(let position):
        print("Job queued at position \(position)")
    case .processing:
        print("Job is being processed")
    case .completed:
        print("Job completed successfully")
    case .failed(let message):
        print("Job failed: \(message)")
    case .cancelled:
        print("Job was cancelled")
    }
}

// Cancel a job
await queue.cancel(jobID: jobID)

// View job history
let history = await queue.getHistory(limit: 20)
for record in history {
    print("\(record.label): \(record.status)")
}
```

## Multiple Printer Management

Manage multiple printers with the printer registry:

```swift
let registry = PrinterRegistry()

// Add radiology film printer
let radiologyPrinter = PrinterInfo(
    name: "Radiology Film Printer",
    configuration: PrintConfiguration(
        host: "192.168.1.100",
        port: 11112,
        callingAETitle: "APP",
        calledAETitle: "RAD_PRINT"
    ),
    capabilities: PrinterCapabilities(
        supportedFilmSizes: [.size14InX17In, .size11InX14In],
        supportsColor: false,
        maxCopies: 99,
        supportedMediumTypes: [.clearFilm, .blueFilm]
    ),
    isDefault: true
)
try await registry.addPrinter(radiologyPrinter)

// Add color printer
let colorPrinter = PrinterInfo(
    name: "Color Diagnostic Printer",
    configuration: PrintConfiguration(
        host: "192.168.1.101",
        port: 11112,
        callingAETitle: "APP",
        calledAETitle: "COLOR_PRINT",
        colorMode: .color
    ),
    capabilities: PrinterCapabilities(
        supportedFilmSizes: [.size11InX14In, .a4],
        supportsColor: true,
        maxCopies: 10,
        supportedMediumTypes: [.paper]
    ),
    isDefault: false
)
try await registry.addPrinter(colorPrinter)

// Select best printer for a job
if let printer = await registry.selectPrinter(
    requiresColor: false,
    filmSize: .size14InX17In
) {
    print("Using printer: \(printer.name)")
    // Use printer.configuration for printing
}

// Track printer availability
await registry.updateAvailability(id: radiologyPrinter.id, isAvailable: true)
```

## Low-Level Print Workflow

For full control, use the low-level print workflow API:

```swift
// Step 1: Query printer status
let printerStatus = try await DICOMPrintService.getPrinterStatus(
    configuration: config
)
print("Printer: \(printerStatus.printerName), Status: \(printerStatus.status)")

// Step 2: Create film session
let filmSession = FilmSession(
    numberOfCopies: 2,
    printPriority: .high,
    mediumType: .clearFilm,
    filmDestination: .magazine,
    filmSessionLabel: "CT Study - 2024-01-15"
)
let filmSessionUID = try await DICOMPrintService.createFilmSession(
    configuration: config,
    filmSession: filmSession
)

// Step 3: Create film box
let filmBox = FilmBox(
    imageDisplayFormat: .standard(rows: 2, columns: 2),
    filmOrientation: .landscape,
    filmSizeID: .size14InX17In,
    magnificationType: .cubic,
    filmSessionUID: filmSessionUID
)
let filmBoxResult = try await DICOMPrintService.createFilmBox(
    configuration: config,
    filmBox: filmBox
)

// Step 4: Set image box contents
for (index, imageData) in imageDataArray.enumerated() {
    try await DICOMPrintService.setImageBox(
        configuration: config,
        content: ImageBoxContent(
            imageBoxUID: filmBoxResult.imageBoxUIDs[index],
            position: UInt16(index + 1),
            pixelData: imageData,
            polarity: .normal
        )
    )
}

// Step 5: Print the film box
let printJobUID = try await DICOMPrintService.printFilmBox(
    configuration: config,
    filmBoxUID: filmBoxResult.filmBoxUID
)

// Step 6: Monitor print job
let jobStatus = try await DICOMPrintService.getPrintJobStatus(
    configuration: config,
    printJobUID: printJobUID
)
print("Print job status: \(jobStatus.executionStatus)")

// Step 7: Cleanup
try await DICOMPrintService.deleteFilmSession(
    configuration: config,
    filmSessionUID: filmSessionUID
)
```

## Film Sizes and Layouts

### Standard Film Sizes

Common film sizes available:

| Size | Description | Typical Use |
|------|-------------|-------------|
| `.size8InX10In` | 8×10 inches | Small format |
| `.size10InX12In` | 10×12 inches | Standard format |
| `.size11InX14In` | 11×14 inches | Large format |
| `.size14InX17In` | 14×17 inches | Extra large format |
| `.a4` | 210×297 mm | International standard |
| `.a3` | 297×420 mm | Large international |

### Image Display Formats

Standard multi-image layouts:

| Format | Layout | Images | Description |
|--------|--------|--------|-------------|
| `STANDARD\1,1` | 1×1 | 1 | Single image, full film |
| `STANDARD\1,2` | 1×2 | 2 | Horizontal comparison |
| `STANDARD\2,1` | 2×1 | 2 | Vertical comparison |
| `STANDARD\2,2` | 2×2 | 4 | Small grid |
| `STANDARD\2,3` | 2×3 | 6 | Medium grid |
| `STANDARD\3,3` | 3×3 | 9 | Large grid |
| `STANDARD\3,4` | 3×4 | 12 | Multi-phase |
| `STANDARD\4,5` | 4×5 | 20 | Dense layout |

## Error Handling

Handle print errors with detailed recovery suggestions:

```swift
do {
    let result = try await DICOMPrintService.printImage(
        configuration: config,
        imageData: pixelData,
        options: .default
    )
} catch let error as PrintError {
    print("Print error: \(error.description)")
    print("Suggestion: \(error.recoverySuggestion)")
    
    switch error {
    case .printerUnavailable:
        // Printer is offline - notify user
    case .filmSessionCreationFailed:
        // Failed to create session - check printer status
    case .imageBoxSetFailed(let position, let statusCode):
        // Failed to set image at position - may need to retry
    case .insufficientMemory:
        // Printer out of memory - reduce image count or size
    default:
        // Other error - see recovery suggestion
    }
}
```

### Partial Print Results

Handle scenarios where some images print successfully:

```swift
if result is PartialPrintResult {
    let partial = result as! PartialPrintResult
    print("Printed \(partial.successCount) of \(partial.totalCount) images")
    print("Failed positions: \(partial.failedPositions)")
    
    // Retry failed images
    for error in partial.errors {
        if case .imageBoxSetFailed(let position, _) = error {
            print("Image at position \(position) failed")
        }
    }
}
```

## Best Practices

### 1. Always Query Printer Status First

```swift
let status = try await DICOMPrintService.getPrinterStatus(configuration: config)
guard status.status == .normal else {
    throw PrintError.printerUnavailable(message: status.statusInfo)
}
```

### 2. Use Appropriate Film Sizes

Match film size to clinical requirements:
- **CT/MR**: 14×17" for detailed anatomy
- **Mammography**: 14×17" with MAMMO BLUE FILM
- **Ultrasound**: 11×14" or 10×12"
- **Documentation**: A4 or 8.5×11" paper

### 3. Optimize Image Quality

- Apply appropriate window/level for modality
- Use high quality resize mode for diagnostic images
- Choose correct magnification type (cubic for smooth images)
- Use proper polarity (NORMAL for most, REVERSE for presentation)

### 4. Handle Retry Logic

Use `PrintRetryPolicy` for automatic retry on transient failures:

```swift
let retryPolicy = PrintRetryPolicy(
    maxRetries: 3,
    initialDelay: 2.0,
    maxDelay: 30.0,
    backoffMultiplier: 2.0
)

let options = PrintOptions(
    filmSize: .size14InX17In,
    retryPolicy: retryPolicy
)
```

### 5. Clean Up Sessions

Always delete film sessions after printing to free printer resources:

```swift
defer {
    try? await DICOMPrintService.deleteFilmSession(
        configuration: config,
        filmSessionUID: filmSessionUID
    )
}
```

## Command-Line Tool

Use the `dicom-print` CLI tool for testing and automation:

```bash
# Query printer status
dicom-print status pacs://192.168.1.100:11112 --aet WORKSTATION

# Print single image
dicom-print send pacs://192.168.1.100:11112 scan.dcm --aet WORKSTATION --copies 2

# Print multiple images with layout
dicom-print send pacs://server:11112 *.dcm --aet APP --layout 2x3 --film-size 14x17

# Configure and use saved printer
dicom-print add-printer --name rad-printer --host 192.168.1.100 --port 11112 --called-ae PRINT_SCP --default
dicom-print send --printer rad-printer scan.dcm
```

See `dicom-print --help` for complete command reference.

## DICOM Standard Reference

The print management implementation conforms to:

- **PS3.4 Annex H**: Print Management Service Class
- **PS3.7 Section 10.1**: DIMSE-N Services (N-CREATE, N-SET, N-GET, N-ACTION, N-DELETE)
- **PS3.3 Section C.13**: Print Management Modules
  - C.13.1 - Film Session Module
  - C.13.3 - Film Box Module
  - C.13.5 - Image Box Module
  - C.13.8 - Print Job Module
  - C.13.9 - Printer Module

## See Also

- ``DICOMPrintService``
- ``PrintConfiguration``
- ``PrintOptions``
- ``PrintTemplate``
- ``PrintQueue``
- ``PrinterRegistry``
- ``ImagePreprocessor``
- ``ImageResizer``
- ``AnnotationRenderer``
