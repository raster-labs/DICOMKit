# Frequently Asked Questions

Common questions about DICOMKit.

## General Questions

### What is DICOMKit?

DICOMKit is a pure Swift DICOM toolkit for Apple platforms (iOS, macOS, visionOS). It provides native Swift implementations for reading, parsing, writing, and networking with DICOM medical imaging files.

### Which platforms does DICOMKit support?

- **iOS** 26.0 and later
- **macOS** 26.0 and later
- **visionOS** 26.0 and later
- **tvOS** 26.0 and later
- **watchOS** 26.0 and later

### What Swift version is required?

DICOMKit requires **Swift 6.4** (`swift-tools-version: 6.4`) or later and uses strict concurrency checking.

### Is DICOMKit production-ready?

Yes, DICOMKit v1.0+ is designed for production use. It includes comprehensive test coverage, performance optimizations, and follows DICOM standard compliance.

### Does DICOMKit require any external C/C++ dependencies?

No C/C++ codec libraries are required at runtime. DICOMKit uses five first-party MIT-licensed pure-Swift `raster-labs` codec packages (`SwiftJ2K 12.2.0`, `SwiftJLS 2.0.1`, `SwiftJLI 2.0.3`, `SwiftJXL 2.0.1`, and `SwiftRLE 1.0.2`) alongside `swift-argument-parser` (for CLI executables) and Apple system frameworks (Foundation, CoreGraphics, Accelerate, Metal, Network).

---

## File Handling

### How do I read a DICOM file?

```swift
import DICOMKit

let data = try Data(contentsOf: fileURL)
let dicomFile = try DICOMFile.read(from: data)

// Access patient information
let patientName = dicomFile.dataSet.patientName
```

### How do I write/create a DICOM file?

```swift
import DICOMKit

// Create a new DataSet
var dataSet = DataSet()
dataSet[.patientName] = DataElement(tag: .patientName, vr: .PN, value: "DOE^JOHN")
dataSet[.patientID] = DataElement(tag: .patientID, vr: .LO, value: "12345")
// ... add more elements

// Create DICOM file
let dicomFile = try DICOMFile.create(dataSet: dataSet, sopClassUID: sopClassUID)
let data = try dicomFile.write()
try data.write(to: outputURL)
```

### What transfer syntaxes are supported?

DICOMKit supports all standard uncompressed and compressed DICOM transfer syntaxes:
- Implicit VR Little Endian, Explicit VR Little Endian, Explicit VR Big Endian (Retired), and Deflated Explicit VR Little Endian
- RLE Lossless (`SwiftRLE`)
- JPEG Baseline, JPEG Extended, JPEG Lossless, and JPEG Lossless SV1 (`SwiftJLI`)
- JPEG-LS Lossless and JPEG-LS Near-Lossless (`SwiftJLS`)
- JPEG 2000 Part 1 & Part 2 (Lossless and Lossy) and HTJ2K Lossless, RPCL Lossless, and Lossy (`SwiftJ2K`)
- JPEG XL Lossless, JPEG XL JPEG Recompression, and JPEG XL Lossy/General (`SwiftJXL`)
- JP3D volumetric encoding/decoding/transcoding (`SwiftJ2K3D 12.2.0`, experimental private UIDs) and JPIP Referenced / JPIP HTJ2K Referenced interactive streaming (`SwiftJ2KJPIP 12.2.0`)

### Can I read DICOM files without the DICM prefix?

Yes, use the `force` parameter:

```swift
let file = try DICOMFile.read(from: data, force: true)
```

---

## Image Rendering

### How do I render a DICOM image?

```swift
import DICOMKit

let pixelData = try dicomFile.tryPixelData()
let renderer = PixelDataRenderer(pixelData: pixelData)

if let cgImage = renderer.renderFrame(0) {
    // Use the CGImage
}
```

### How do I adjust window/level?

```swift
let renderer = PixelDataRenderer(
    pixelData: pixelData,
    windowCenter: 40,
    windowWidth: 400
)

// Or specify per-frame
if let image = renderer.renderFrame(0, windowCenter: 40, windowWidth: 400) {
    // Use image
}
```

### What photometric interpretations are supported?

- MONOCHROME1 (inverted grayscale)
- MONOCHROME2 (standard grayscale)
- RGB
- PALETTE COLOR
- YBR_FULL
- YBR_FULL_422
- YBR_PARTIAL_420

### How do I handle multi-frame images?

```swift
let numberOfFrames = pixelData.numberOfFrames

for frameIndex in 0..<numberOfFrames {
    if let image = renderer.renderFrame(frameIndex) {
        // Process each frame
    }
}
```

---

## Networking

### How do I query a PACS server?

```swift
import DICOMNetwork

let client = DICOMClient(
    host: "pacs.hospital.com",
    port: 11112,
    callingAETitle: "MY_APP",
    calledAETitle: "PACS"
)

try await client.associate()

let queryService = QueryService(client: client)
let results = try await queryService.findStudies(QueryKeys.study(patientID: "12345"))

try await client.release()
```

### Does DICOMKit support C-MOVE and C-GET?

Yes, both are supported through the `RetrieveService`:

```swift
let retrieveService = RetrieveService(client: client)

// C-GET (receive directly)
let files = try await retrieveService.getStudy(studyInstanceUID: uid)

// C-MOVE (send to another AE)
try await retrieveService.moveStudy(studyInstanceUID: uid, destinationAE: "WORKSTATION")
```

### Does DICOMKit support TLS/SSL?

Yes:

```swift
let tlsConfig = TLSConfiguration(
    certificatePath: "/path/to/cert.pem",
    keyPath: "/path/to/key.pem"
)

let client = DICOMClient(
    host: "secure-pacs.com",
    port: 11112,
    callingAETitle: "MY_APP",
    calledAETitle: "PACS",
    tlsConfiguration: tlsConfig
)
```

### How do I receive images as a Storage SCP?

```swift
let scp = StorageSCP(port: 11112, aeTitle: "MY_SCP")

scp.onImageReceived = { dicomFile in
    // Handle received image
    print("Received: \(dicomFile.dataSet.sopInstanceUID ?? "")")
}

try await scp.start()
```

---

## DICOMweb

### How do I use DICOMweb?

```swift
import DICOMWeb

let config = DICOMwebConfiguration(
    baseURL: URL(string: "https://server/dicom-web")!
)

let client = DICOMwebClient(configuration: config)

// Query studies (QIDO-RS)
let query = QIDOQuery.studies().patientID("12345")
let results = try await client.queryStudies(query)

// Retrieve study (WADO-RS)
let files = try await client.retrieveStudy(studyUID: uid)
```

### Does DICOMKit support OAuth2?

Yes, for DICOMweb:

```swift
let oauth2 = OAuth2Client(configuration: OAuth2Configuration(
    tokenEndpoint: URL(string: "https://auth.server/token")!,
    clientID: "my_client",
    clientSecret: "secret"
))

let client = DICOMwebClient(configuration: config, oauth2Client: oauth2)
```

---

## Presentation States

### How do I apply a Grayscale Presentation State?

```swift
let gsps = try GrayscalePresentationState.read(from: gspsFile)
let transformedImage = try gsps.apply(to: dicomFile)
```

### What presentation states are supported?

- Grayscale Softcopy Presentation State (GSPS)
- Color Softcopy Presentation State (CSPS)
- Pseudo-Color Softcopy Presentation State

### A study I imported has a PR series from another viewer. Will DICOM Studio show it?

Yes. When a study is opened in the viewer, every GSPS, CSPS and Pseudo-Color
object the library indexes for it is adopted into the app's presentation-state
store (one copy per SOP Instance UID, so reopening the study changes nothing)
and offered in the saved-view picker marked *imported*. The first one is
applied on arrival, as Weasis does: its window, zoom, rotation, flip, inversion
and palette go onto the image, and its Graphic Annotation Sequence — rulers,
angles, polygons, circles, ellipses, points and their labels — is drawn over
the image in the layer's recommended colour. Display shutters are honoured.
A Modality LUT rescale carried by the state is used to interpret its window.

Imported drawings are shown and printed exactly as the other viewer stated
them but cannot be moved or reworded here: the app has no measuring tool to
recompute a "42.3 mm" label, so the whole imported view can be taken off, but
its parts cannot be edited. Deleting an imported view is remembered — the
study's own copy is not adopted again on the next open.

When such an image is marked for print, the same drawings and shutter are
burned into the film pixels, oriented with the cell, so the Print SCP
receives them in the image box.

Not carried: a state's VOI LUT *table* (a window is), bitmap shutters that
reference an overlay group, and a CSPS's ICC profile.

### A saved view from an older build opens, but `dcmpschk` used to reject it. Why?

Until 2026-08-31 the presentation-state builder chose Value Representations by
hand, and chose seven of them wrongly: Image Rotation, the Displayed Area
corners, the Graphic Layer recommended display values, Graphic Data, the
Bounding Box corners and Anchor Point were all written as `IS` where the
standard says `US`, `SL` or `FL`. The library's own parser read back the same
wrong forms, so every round-trip test passed against a file no other toolkit
would accept.

VRs now come from DICOMKit's data dictionary (the full PS3.6 table it already
ships) rather than from the call site, so a write path cannot disagree with the
standard. Objects written by an older build still open — numbers are read
whatever VR they were stored under — but re-save a view if you need the file
itself to validate.

**Writing your own elements?** Prefer the dictionary-driven setters
(`setInteger(s)`, `setReals`, `setStringFromDictionary`) over passing a VR by
hand. Note that a round-trip test can never catch a wrong VR; only a dictionary
check or an external validator such as `dcmpschk` can.

---

## Structured Reporting

### How do I create an SR document?

```swift
let builder = SRDocumentBuilder(
    title: "Imaging Report",
    templateID: "TID1500"
)

builder.addTextContent(
    conceptName: CodedConcept(meaning: "Finding", value: "121071"),
    text: "Normal chest X-ray"
)

let srDocument = try builder.build()
```

### What SR templates are supported?

DICOMKit supports:
- Basic Text SR
- Enhanced SR
- Comprehensive SR
- Comprehensive 3D SR
- TID 1500 (Measurement Report)

---

## Performance

### How do I optimize memory usage for large files?

```swift
// Use metadata-only parsing
let options = ParsingOptions(mode: .metadataOnly)
let file = try DICOMFile.read(from: data, options: options)

// Or use lazy loading
let options = ParsingOptions(mode: .lazyPixelData)
```

### How do I enable SIMD acceleration?

SIMD acceleration is automatic on Apple platforms when the Accelerate framework is available. No configuration needed.

### How do I cache images?

```swift
let cache = ImageCache(configuration: .default)

// Store
cache.set(cgImage, for: "key")

// Retrieve
if let cached = cache.get(key: "key") {
    // Use cached image
}
```

---

## Compliance

### Is DICOMKit HIPAA compliant?

DICOMKit is a library that helps you build HIPAA-compliant applications. It:
- Does not transmit PHI to third parties
- Supports TLS encryption
- Provides anonymization utilities
- Does not log sensitive data

Your application is responsible for overall HIPAA compliance.

### Which DICOM standard version does DICOMKit follow?

DICOMKit follows DICOM 2026a and aims for full compliance with relevant parts of the standard.

### Where can I find the Conformance Statement?

See [Documentation/ConformanceStatement.md](ConformanceStatement.md) for the detailed DICOM Conformance Statement.

---

## Troubleshooting

### Why does my file fail to parse?

See the [Troubleshooting Guide](Troubleshooting.md) for common issues and solutions.

### Another viewer says this image is 4 of 31; DICOM Studio says 17 of 31. Which is right?

Check first whether the two viewers are showing the *same pixels*. If they are,
this is a numbering disagreement, not a misplaced presentation state — a state
references its image by SOP Instance UID, so ordering cannot land one on the
wrong slice.

The cause is a stale library index. Instance Number is an `IS` — text — and was
read as binary until 2026-07-30, which always answered nil, leaving affected
series filed in file-system order. Re-importing does not fix it: imports are
deduplicated by SOP Instance UID and never refresh metadata. Opening the study
now repairs it, reading the numbers off the headers of just the series that are
missing them and writing them back, so the cost is paid once rather than on
every open.

### I deleted a study. Are its files gone?

Yes, if the app imported them. Import copies each file into
`Imports/<StudyInstanceUID>/`, and deleting the study removes that copy along
with the index row — previously the row went and the files stayed, invisible to
the browser but still holding pixel data and patient identification.

Files outside that import directory are never deleted. A study the library
points at in place — an older import, or a fixture opened from a source tree —
loses its row and keeps its files, because those belong to you and not to the
app.

### Where can I get help?

1. Check the [GitHub Issues](https://github.com/raster-image/DICOMKit/issues)
2. Read the documentation
3. Create a new issue with a minimal reproduction case

---

## Contributing

### How can I contribute to DICOMKit?

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on:
- Reporting bugs
- Suggesting features
- Submitting pull requests
- Code style guidelines

### Is DICOMKit open source?

Yes, DICOMKit is released under the MIT License. See [LICENSE](../LICENSE) for details.
