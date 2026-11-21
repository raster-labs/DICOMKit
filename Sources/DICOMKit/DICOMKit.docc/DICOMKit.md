# ``DICOMKit``

A pure Swift DICOM toolkit for Apple platforms (iOS, macOS, visionOS).

## Overview

DICOMKit is a modern, Swift-native library for reading, writing, and parsing DICOM (Digital Imaging and Communications in Medicine) files. Built with Swift 6 strict concurrency and value semantics, it provides a type-safe, efficient interface for working with medical imaging data on Apple platforms.

### Key Features

- **DICOM File Operations**: Read, write, and modify DICOM Part 10 files
- **Pixel Data Handling**: Extract and render medical images with proper windowing
- **Presentation States**: Apply Grayscale, Color, and Pseudo-Color presentation states
- **Transfer Syntax Support**: Compress and decompress images (JPEG, JPEG 2000, RLE)
- **Structured Reporting**: Create and parse DICOM SR documents
- **Character Set Support**: Handle international text with ISO 2022 and Unicode
- **Performance Optimized**: Memory-mapped files, lazy loading, and SIMD acceleration

### Platform Requirements

- iOS 17.0+
- macOS 14.0+
- visionOS 1.0+
- Swift 6.2+

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:ReadingDICOMFiles>
- <doc:RenderingImages>

### Working with DICOM Files

- ``DICOMFile``
- ``DICOMParser``
- ``DataSet``
- ``DataElement``

### Pixel Data and Rendering

- ``PixelDataRenderer``
- ``PixelData``
- ``WindowSettings``

### Presentation States

- <doc:PresentationStateAndAnnotations>
- ``PresentationStateManager``
- ``PresentationStateDocument``
- ``PresentationStateParser``
- ``PresentationStateBuilder``
- ``PresentationStateViewportBridge``
- ``PresentationStateSRBridge``
- ``PresentationStateApplicator``
- ``DICOMAnnotation``
- ``DICOMAnnotationConverter``
- ``GrayscalePresentationState``
- ``ColorPresentationState``
- ``PseudoColorPresentationState``
- ``BlendingPresentationState``

### Hanging Protocols

- ``HangingProtocolDefinition``
- ``HangingProtocolMatcher``
- ``DisplaySetSequence``

### Segmentation

- ``Segmentation``
- ``SegmentationFrame``
- ``SegmentationBuilder``

### Parametric Maps

- ``ParametricMap``
- ``ParametricMapFrame``

### Real World Value Mapping

- ``RealWorldValueMapping``
- ``RealWorldValueTransform``

### Radiation Therapy

- ``RTStructureSet``
- ``RTStructureSetROI``
- ``RTPlan``
- ``RTBeam``
- ``RTDose``

### Structured Reporting

- ``SRDocument``
- ``SRDocumentBuilder``
- ``SRContentItem``

### Performance

- ``ParsingOptions``
- ``ImageCache``
- ``DICOMBenchmark``

### AI Integration

- ``DICOMAIContext``
- ``DICOMAIInsight``
