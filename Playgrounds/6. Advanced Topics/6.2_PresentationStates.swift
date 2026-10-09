// DICOMKit Sample Code: Grayscale Presentation States (GSPS)
//
// This example demonstrates how to:
// - Load GSPS files
// - Apply grayscale transformations (Modality LUT, VOI LUT, Presentation LUT)
// - Render graphic annotations (lines, polylines, circles, ellipses, text)
// - Apply spatial transformations (rotation, flip, zoom, pan)
// - Handle shutters (rectangular, circular, polygonal)
// - Manage multi-layer annotations
// - Build presentation state picker UI

import DICOMKit
import DICOMCore
import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Example 1: Loading GSPS Files

func example1_loadGSPSFile() throws {
    let gspsURL = URL(fileURLWithPath: "/path/to/presentation/state.dcm")
    let gspsFile = try DICOMFile.read(from: gspsURL)
    
    // Verify this is a Grayscale Softcopy Presentation State
    let sopClassUID = gspsFile.dataSet.string(for: .sopClassUID) ?? ""
    guard sopClassUID == "1.2.840.10008.5.1.4.1.1.11.1" else {
        print("Not a Grayscale Presentation State")
        return
    }
    
    // Parse GSPS metadata
    let presentationLabel = gspsFile.dataSet.string(for: Tag(0x0070, 0x0080)) ?? "Unnamed"
    let presentationDescription = gspsFile.dataSet.string(for: Tag(0x0070, 0x0081))
    let creatorName = gspsFile.dataSet.string(for: Tag(0x0070, 0x0084))
    
    print("✅ Loaded GSPS:")
    print("   Label: \(presentationLabel)")
    if let desc = presentationDescription {
        print("   Description: \(desc)")
    }
    if let creator = creatorName {
        print("   Creator: \(creator)")
    }
    
    // Get referenced image series
    if let referencedSeriesSeq = gspsFile.dataSet[Tag(0x0008, 0x1115)],
       case .sequence(let seriesItems) = referencedSeriesSeq.value {
        for seriesItem in seriesItems {
            if let seriesUID = seriesItem.dataSet.string(for: .seriesInstanceUID) {
                print("   Referenced Series: \(seriesUID)")
            }
        }
    }
}

// MARK: - Example 2: Applying Grayscale Transformations

#if canImport(CoreGraphics)
func example2_applyGrayscaleTransformations() throws {
    let imageURL = URL(fileURLWithPath: "/path/to/image.dcm")
    let gspsURL = URL(fileURLWithPath: "/path/to/presentation/state.dcm")
    
    let imageFile = try DICOMFile.read(from: imageURL)
    let gspsFile = try DICOMFile.read(from: gspsURL)
    
    guard let pixelData = imageFile.pixelData else {
        print("No pixel data")
        return
    }
    
    // Step 1: Apply Modality LUT (Stored Values → Modality Values)
    let rescaleIntercept = imageFile.dataSet.float64(for: .rescaleIntercept) ?? 0.0
    let rescaleSlope = imageFile.dataSet.float64(for: .rescaleSlope) ?? 1.0
    
    print("Modality LUT:")
    print("  Intercept: \(rescaleIntercept)")
    print("  Slope: \(rescaleSlope)")
    
    // Step 2: Apply VOI LUT from GSPS (Modality Values → Values of Interest)
    var windowCenter: Double = 0.0
    var windowWidth: Double = 4096.0
    
    // Check for Softcopy VOI LUT Sequence in GSPS
    if let voiLutSeq = gspsFile.dataSet[Tag(0x0028, 0x3110)],
       case .sequence(let voiItems) = voiLutSeq.value,
       let firstVOI = voiItems.first {
        
        // Get window center and width from GSPS
        if let centers = firstVOI.dataSet.string(for: .windowCenter) {
            windowCenter = Double(centers.split(separator: "\\")[0]) ?? 0.0
        }
        if let widths = firstVOI.dataSet.string(for: .windowWidth) {
            windowWidth = Double(widths.split(separator: "\\")[0]) ?? 4096.0
        }
        
        print("VOI LUT from GSPS:")
        print("  Window Center: \(windowCenter)")
        print("  Window Width: \(windowWidth)")
    }
    
    // Step 3: Apply Presentation LUT (optional, for calibrated displays)
    let presentationLUTShape = gspsFile.dataSet.string(for: Tag(0x2050, 0x0020))
    print("Presentation LUT Shape: \(presentationLUTShape ?? "IDENTITY")")
    
    // Render image with transformations
    if let cgImage = try pixelData.createCGImage(
        frame: 0,
        windowCenter: windowCenter,
        windowWidth: windowWidth
    ) {
        print("✅ Applied GSPS transformations")
        print("   Image size: \(cgImage.width) × \(cgImage.height)")
    }
}
#endif

// MARK: - Example 3: Rendering Graphic Annotations

#if canImport(CoreGraphics)
func example3_renderGraphicAnnotations() throws {
    let gspsURL = URL(fileURLWithPath: "/path/to/presentation/state.dcm")
    let gspsFile = try DICOMFile.read(from: gspsURL)
    
    // Parse Graphic Annotation Sequence (0070,0001)
    guard let graphicAnnotationSeq = gspsFile.dataSet[Tag(0x0070, 0x0001)],
          case .sequence(let annotationLayers) = graphicAnnotationSeq.value else {
        print("No graphic annotations found")
        return
    }
    
    print("✅ Found \(annotationLayers.count) annotation layer(s)")
    
    for (layerIndex, layer) in annotationLayers.enumerated() {
        let layerName = layer.dataSet.string(for: Tag(0x0070, 0x0002)) ?? "Layer \(layerIndex)"
        print("\nLayer: \(layerName)")
        
        // Parse Graphic Object Sequence (0070,0009)
        guard let graphicObjectSeq = layer.dataSet[Tag(0x0070, 0x0009)],
              case .sequence(let graphicObjects) = graphicObjectSeq.value else {
            continue
        }
        
        for object in graphicObjects {
            // Graphic Type: POINT, POLYLINE, INTERPOLATED, CIRCLE, ELLIPSE
            let graphicType = object.dataSet.string(for: Tag(0x0070, 0x0023)) ?? "UNKNOWN"
            
            // Graphic Data: Array of (x, y) coordinates in image pixels
            let graphicData = object.dataSet.string(for: Tag(0x0070, 0x0022))?
                .split(separator: "\\")
                .compactMap { Float($0) } ?? []
            
            // Number of points
            let numPoints = object.dataSet.uint16(for: Tag(0x0070, 0x0021)) ?? 0
            
            print("  \(graphicType): \(numPoints) points")
            
            // Draw based on type
            switch graphicType {
            case "POINT":
                // Draw point marker
                if graphicData.count >= 2 {
                    let x = graphicData[0]
                    let y = graphicData[1]
                    print("    Point at (\(x), \(y))")
                }
                
            case "POLYLINE", "INTERPOLATED":
                // Draw line or curve through points
                var points: [(Float, Float)] = []
                for i in stride(from: 0, to: graphicData.count, by: 2) {
                    if i + 1 < graphicData.count {
                        points.append((graphicData[i], graphicData[i + 1]))
                    }
                }
                print("    Polyline with \(points.count) points")
                
            case "CIRCLE":
                // First 2 values: center (x, y)
                // Second 2 values: point on circumference
                if graphicData.count >= 4 {
                    let cx = graphicData[0]
                    let cy = graphicData[1]
                    let px = graphicData[2]
                    let py = graphicData[3]
                    let radius = sqrt(pow(px - cx, 2) + pow(py - cy, 2))
                    print("    Circle at (\(cx), \(cy)), radius \(radius)")
                }
                
            case "ELLIPSE":
                // 4 points: major axis endpoints, minor axis endpoints
                if graphicData.count >= 8 {
                    print("    Ellipse with 4 control points")
                }
                
            default:
                break
            }
            
            // Check for text annotations
            if let unformattedText = object.dataSet[Tag(0x0070, 0x0006)],
               case .string(let text) = unformattedText.value {
                print("    Text: \"\(text)\"")
            }
        }
    }
}
#endif

// MARK: - Example 4: Drawing Annotations on Image

#if canImport(CoreGraphics)
func example4_drawAnnotationsOnImage(
    baseImage: CGImage,
    annotations: [GraphicAnnotation]
) -> CGImage? {
    let width = baseImage.width
    let height = baseImage.height
    
    // Create bitmap context
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        return nil
    }
    
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    
    // Draw base image
    context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    // Draw annotations
    context.setLineWidth(2.0)
    context.setStrokeColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)  // Yellow
    
    for annotation in annotations {
        switch annotation.type {
        case .polyline(let points):
            guard let firstPoint = points.first else { continue }
            context.beginPath()
            context.move(to: CGPoint(x: CGFloat(firstPoint.x), y: CGFloat(firstPoint.y)))
            for point in points.dropFirst() {
                context.addLine(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
            }
            context.strokePath()
            
        case .circle(let center, let radius):
            let rect = CGRect(
                x: CGFloat(center.x - radius),
                y: CGFloat(center.y - radius),
                width: CGFloat(radius * 2),
                height: CGFloat(radius * 2)
            )
            context.strokeEllipse(in: rect)
            
        case .point(let point):
            // Draw crosshair
            let size: CGFloat = 5.0
            context.beginPath()
            context.move(to: CGPoint(x: CGFloat(point.x) - size, y: CGFloat(point.y)))
            context.addLine(to: CGPoint(x: CGFloat(point.x) + size, y: CGFloat(point.y)))
            context.move(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y) - size))
            context.addLine(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y) + size))
            context.strokePath()
            
        case .text(let point, let text):
            // Draw text (simplified - real implementation would use proper font rendering)
            context.textPosition = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
            context.setFillColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
            // Note: CoreText would be used for actual text rendering
            print("Would render text '\(text)' at (\(point.x), \(point.y))")
        }
    }
    
    return context.makeImage()
}

struct GraphicAnnotation {
    enum AnnotationType {
        case point(Point2D)
        case polyline([Point2D])
        case circle(center: Point2D, radius: Float)
        case text(position: Point2D, text: String)
    }
    
    let type: AnnotationType
}

struct Point2D {
    let x: Float
    let y: Float
}
#endif

// MARK: - Example 5: Spatial Transformations

#if canImport(CoreGraphics)
func example5_applySpatialTransformations() throws {
    let gspsURL = URL(fileURLWithPath: "/path/to/presentation/state.dcm")
    let gspsFile = try DICOMFile.read(from: gspsURL)
    
    // Parse Rotation (0070,0042)
    let rotation = gspsFile.dataSet.uint16(for: Tag(0x0070, 0x0042)) ?? 0
    
    // Parse Flip (horizontal/vertical)
    let horizontalFlip = gspsFile.dataSet.string(for: Tag(0x0070, 0x0041)) == "Y"
    
    // Parse Magnification (zoom factor)
    let magnification = gspsFile.dataSet.float64(for: Tag(0x0070, 0x0043)) ?? 1.0
    
    print("Spatial Transformations:")
    print("  Rotation: \(rotation)°")
    print("  Horizontal Flip: \(horizontalFlip)")
    print("  Magnification: \(magnification)x")
    
    // Apply transformations to image (example using CGImage)
    // In practice, you'd apply these transforms when rendering
    guard let imageFile = try? DICOMFile.read(from: URL(fileURLWithPath: "/path/to/image.dcm")),
          let pixelData = imageFile.pixelData,
          let baseImage = try pixelData.createCGImage(frame: 0) else {
        return
    }
    
    var transform = CGAffineTransform.identity
    
    // Apply rotation
    let rotationRadians = CGFloat(rotation) * .pi / 180.0
    transform = transform.rotated(by: rotationRadians)
    
    // Apply flip
    if horizontalFlip {
        transform = transform.scaledBy(x: -1.0, y: 1.0)
    }
    
    // Apply magnification
    transform = transform.scaledBy(x: CGFloat(magnification), y: CGFloat(magnification))
    
    print("✅ Created transformation matrix")
}
#endif

// MARK: - Example 6: Display Shutters

#if canImport(CoreGraphics)
func example6_applyDisplayShutters() throws {
    let gspsURL = URL(fileURLWithPath: "/path/to/presentation/state.dcm")
    let gspsFile = try DICOMFile.read(from: gspsURL)
    
    // Parse Shutter Shape (0018,1600)
    let shutterShape = gspsFile.dataSet.string(for: Tag(0x0018, 0x1600))
    
    print("Display Shutter:")
    print("  Shape: \(shutterShape ?? "NONE")")
    
    if let shape = shutterShape {
        switch shape {
        case "RECTANGULAR":
            // Parse rectangular shutter coordinates
            let left = gspsFile.dataSet.int32(for: Tag(0x0018, 0x1602)) ?? 0
            let right = gspsFile.dataSet.int32(for: Tag(0x0018, 0x1604)) ?? 0
            let top = gspsFile.dataSet.int32(for: Tag(0x0018, 0x1606)) ?? 0
            let bottom = gspsFile.dataSet.int32(for: Tag(0x0018, 0x1608)) ?? 0
            
            print("  Rectangular: L=\(left), R=\(right), T=\(top), B=\(bottom)")
            
        case "CIRCULAR":
            // Parse circular shutter
            let centerX = gspsFile.dataSet.int32(for: Tag(0x0018, 0x1610)) ?? 0
            let centerY = gspsFile.dataSet.int32(for: Tag(0x0018, 0x1612)) ?? 0
            let radius = gspsFile.dataSet.int32(for: Tag(0x0018, 0x1614)) ?? 0
            
            print("  Circular: Center=(\(centerX), \(centerY)), Radius=\(radius)")
            
        case "POLYGONAL":
            // Parse polygonal shutter
            if let vertices = gspsFile.dataSet.string(for: Tag(0x0018, 0x1620)) {
                let points = vertices.split(separator: "\\").compactMap { Int($0) }
                print("  Polygonal: \(points.count / 2) vertices")
            }
            
        default:
            break
        }
        
        // Shutter Presentation Value (color for shuttered area)
        let shutterValue = gspsFile.dataSet.uint16(for: Tag(0x0018, 0x1622)) ?? 0
        print("  Shutter Color Value: \(shutterValue)")
    }
}
#endif

// MARK: - Example 7: Applying Rectangular Shutter to Image

#if canImport(CoreGraphics)
func example7_applyRectangularShutter(
    image: CGImage,
    left: Int,
    right: Int,
    top: Int,
    bottom: Int
) -> CGImage? {
    let width = image.width
    let height = image.height
    
    guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray) else {
        return nil
    }
    
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: colorSpace,
        bitmapInfo: 0
    ) else {
        return nil
    }
    
    // Draw original image
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    // Apply shutter (black out areas outside the rectangle)
    context.setFillColor(gray: 0.0, alpha: 1.0)
    
    // Top shutter
    if top > 0 {
        context.fill(CGRect(x: 0, y: 0, width: width, height: top))
    }
    
    // Bottom shutter
    if bottom < height {
        context.fill(CGRect(x: 0, y: bottom, width: width, height: height - bottom))
    }
    
    // Left shutter
    if left > 0 {
        context.fill(CGRect(x: 0, y: top, width: left, height: bottom - top))
    }
    
    // Right shutter
    if right < width {
        context.fill(CGRect(x: right, y: top, width: width - right, height: bottom - top))
    }
    
    return context.makeImage()
}
#endif

// MARK: - Example 8: Multi-Layer Annotation Management

struct PresentationStateLayer {
    let order: Int
    let label: String
    let description: String?
    let visible: Bool
    let annotations: [GraphicAnnotation]
}

func example8_manageAnnotationLayers() throws {
    let gspsURL = URL(fileURLWithPath: "/path/to/presentation/state.dcm")
    let gspsFile = try DICOMFile.read(from: gspsURL)
    
    var layers: [PresentationStateLayer] = []
    
    // Parse Graphic Annotation Sequence
    guard let graphicAnnotationSeq = gspsFile.dataSet[Tag(0x0070, 0x0001)],
          case .sequence(let annotationLayers) = graphicAnnotationSeq.value else {
        print("No annotation layers found")
        return
    }
    
    for (index, layer) in annotationLayers.enumerated() {
        let label = layer.dataSet.string(for: Tag(0x0070, 0x0002)) ?? "Layer \(index)"
        let description = layer.dataSet.string(for: Tag(0x0070, 0x0003))
        
        // Parse annotations in this layer
        var annotations: [GraphicAnnotation] = []
        
        if let graphicObjectSeq = layer.dataSet[Tag(0x0070, 0x0009)],
           case .sequence(let graphicObjects) = graphicObjectSeq.value {
            
            for object in graphicObjects {
                let graphicType = object.dataSet.string(for: Tag(0x0070, 0x0023)) ?? ""
                let graphicData = object.dataSet.string(for: Tag(0x0070, 0x0022))?
                    .split(separator: "\\")
                    .compactMap { Float($0) } ?? []
                
                switch graphicType {
                case "POLYLINE":
                    var points: [Point2D] = []
                    for i in stride(from: 0, to: graphicData.count, by: 2) {
                        if i + 1 < graphicData.count {
                            points.append(Point2D(x: graphicData[i], y: graphicData[i + 1]))
                        }
                    }
                    annotations.append(GraphicAnnotation(type: .polyline(points)))
                    
                case "CIRCLE":
                    if graphicData.count >= 4 {
                        let center = Point2D(x: graphicData[0], y: graphicData[1])
                        let px = graphicData[2]
                        let py = graphicData[3]
                        let radius = sqrt(pow(px - center.x, 2) + pow(py - center.y, 2))
                        annotations.append(GraphicAnnotation(type: .circle(center: center, radius: radius)))
                    }
                    
                default:
                    break
                }
            }
        }
        
        let presentationLayer = PresentationStateLayer(
            order: index,
            label: label,
            description: description,
            visible: true,  // Default to visible
            annotations: annotations
        )
        
        layers.append(presentationLayer)
    }
    
    print("✅ Loaded \(layers.count) annotation layers:")
    for layer in layers {
        print("   [\(layer.order)] \(layer.label): \(layer.annotations.count) annotations")
    }
}

// MARK: - Example 9: Presentation State Picker UI

#if canImport(SwiftUI)
import SwiftUI

struct PresentationStatePickerView: View {
    let presentationStates: [PresentationStateInfo]
    @Binding var selectedState: PresentationStateInfo?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presentation States")
                .font(.headline)
            
            ForEach(presentationStates) { state in
                Button(action: {
                    selectedState = state
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.label)
                                .font(.body)
                                .fontWeight(selectedState?.id == state.id ? .bold : .regular)
                            
                            if let description = state.description {
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let creator = state.creatorName {
                                Text("By: \(creator)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if selectedState?.id == state.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedState?.id == state.id ? 
                                  Color.accentColor.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}

struct PresentationStateInfo: Identifiable {
    let id: String  // SOP Instance UID
    let label: String
    let description: String?
    let creatorName: String?
    let windowCenter: Double?
    let windowWidth: Double?
    let hasAnnotations: Bool
    let hasShutters: Bool
}

// Usage:
// @State private var selectedState: PresentationStateInfo? = nil
// PresentationStatePickerView(
//     presentationStates: loadedStates,
//     selectedState: $selectedState
// )
#endif

// MARK: - Running the Examples

// Uncomment to run individual examples:
// try? example1_loadGSPSFile()
// try? example2_applyGrayscaleTransformations()
// try? example3_renderGraphicAnnotations()

// MARK: - Quick Reference

/*
 Grayscale Presentation States (GSPS):
 
 SOP Class UID:
 • 1.2.840.10008.5.1.4.1.1.11.1 - Grayscale Softcopy Presentation State
 
 Key Concepts:
 • GSPS              - Grayscale Softcopy Presentation State
 • VOI LUT           - Value of Interest Lookup Table
 • Modality LUT      - Stored to Modality values transformation
 • Presentation LUT  - Final display calibration
 • Graphic Layer     - Collection of annotations
 • Shutter           - Mask to hide parts of image
 
 DICOM Tags (Presentation State):
 • (0070,0080) - Presentation Label
 • (0070,0081) - Presentation Description  
 • (0070,0084) - Presentation Creator's Name
 • (0008,1115) - Referenced Series Sequence
 • (0008,1140) - Referenced Image Sequence
 
 DICOM Tags (Display Transformation):
 • (0028,3110) - Softcopy VOI LUT Sequence
 • (0028,1050) - Window Center
 • (0028,1051) - Window Width
 • (2050,0020) - Presentation LUT Shape (IDENTITY, INVERSE)
 
 DICOM Tags (Spatial Transformation):
 • (0070,0042) - Image Rotation (0, 90, 180, 270 degrees)
 • (0070,0041) - Image Horizontal Flip (Y/N)
 • (0070,0043) - Displayed Area Selection - Magnification Factor
 
 DICOM Tags (Graphic Annotations):
 • (0070,0001) - Graphic Annotation Sequence
 • (0070,0002) - Graphic Layer
 • (0070,0003) - Graphic Layer Description
 • (0070,0009) - Graphic Object Sequence
 • (0070,0021) - Number of Graphic Points
 • (0070,0022) - Graphic Data (x\y\x\y\...)
 • (0070,0023) - Graphic Type (POINT, POLYLINE, CIRCLE, ELLIPSE)
 • (0070,0006) - Unformatted Text Value
 
 DICOM Tags (Display Shutters):
 • (0018,1600) - Shutter Shape (RECTANGULAR, CIRCULAR, POLYGONAL)
 • (0018,1602) - Shutter Left Vertical Edge
 • (0018,1604) - Shutter Right Vertical Edge
 • (0018,1606) - Shutter Upper Horizontal Edge
 • (0018,1608) - Shutter Lower Horizontal Edge
 • (0018,1610) - Center of Circular Shutter (X)
 • (0018,1612) - Center of Circular Shutter (Y)
 • (0018,1614) - Radius of Circular Shutter
 • (0018,1620) - Vertices of Polygonal Shutter
 • (0018,1622) - Shutter Presentation Value
 
 Grayscale Transform Pipeline:
 1. Stored Pixel Value (from image file)
 2. → Modality LUT (rescale slope/intercept)
 3. → VOI LUT (window center/width or LUT)
 4. → Presentation LUT (calibration, gamma)
 5. → P-Values (display-ready values)
 
 Graphic Annotation Types:
 • POINT        - Single point marker
 • POLYLINE     - Connected line segments
 • INTERPOLATED - Smooth curve through points
 • CIRCLE       - Circle (center + point on circumference)
 • ELLIPSE      - Ellipse (4 control points)
 
 Graphic Data Format:
 • Point: x\y
 • Polyline: x1\y1\x2\y2\x3\y3\...
 • Circle: centerX\centerY\pointX\pointY
 • Ellipse: majorX1\majorY1\majorX2\majorY2\minorX1\minorY1\minorX2\minorY2
 
 Shutter Types:
 • RECTANGULAR - Define left, right, top, bottom edges
 • CIRCULAR    - Define center (x, y) and radius
 • POLYGONAL   - Define sequence of (x, y) vertices
 • BITMAP      - Use Overlay Planes (legacy)
 
 Shutter Application:
 • Area inside shutter: Normal display
 • Area outside shutter: Set to Shutter Presentation Value (usually black)
 • Multiple shutters: Intersection of all shutters
 
 Annotation Rendering:
 1. Parse Graphic Annotation Sequence
 2. Group by Graphic Layer
 3. Render each layer in order
 4. Apply layer visibility settings
 5. Use recommended display colors
 6. Support text annotations with positioning
 
 Multi-Layer Management:
 • Each layer has label and description
 • Layers can be shown/hidden independently
 • Rendering order: lower index layers first
 • Supports overlay of multiple annotation sets
 
 Spatial Transformations:
 • Rotation: 0°, 90°, 180°, 270° clockwise
 • Flip: Horizontal mirroring
 • Magnification: Zoom factor (1.0 = 100%)
 • Pan: Displayed area selection
 
 Transform Application Order:
 1. Flip (if enabled)
 2. Rotation
 3. Magnification (zoom)
 4. Pan (translation)
 
 Referenced Images:
 • GSPS references specific image instances
 • Use SOP Instance UID to match
 • Can reference multiple images/series
 • Check Referenced Frame Numbers for multi-frame
 
 VOI LUT Methods:
 • Window Center/Width: Linear transformation (most common)
 • VOI LUT Sequence: Arbitrary lookup table
 • Both can be specified; preference varies
 
 Presentation LUT Shape:
 • IDENTITY: Linear display (standard)
 • INVERSE: Inverted polarity (white → black)
 • Used for print vs. display calibration
 
 Use Cases:
 • Teaching Files - Annotations for education
 • Reporting - Mark findings for radiologist
 • CAD Integration - Display detection results
 • Consultation - Share annotated images
 • Quality Control - Mark artifacts or issues
 
 Best Practices:
 1. Always validate referenced images match
 2. Apply transformations in correct order
 3. Support layer visibility toggle
 4. Provide preset window/level options
 5. Use anti-aliasing for smooth annotations
 6. Handle missing optional fields gracefully
 7. Support export of annotated images
 8. Allow editing/creating new GSPS
 9. Respect shutter display requirements
 10. Test with various GSPS creators (PACS vendors)
 
 Common Implementation Tasks:
 • Load GSPS and apply to matching image
 • Render graphic overlays (lines, circles, text)
 • Apply shutters to mask image areas
 • Support rotation and flip transforms
 • Build UI for presentation state selection
 • Create new GSPS from user annotations
 • Export composite image (image + annotations)
 
 Tips:
 
 1. GSPS is a companion object to an image, not standalone
 2. Multiple GSPS can reference the same image
 3. Window/level in GSPS overrides image defaults
 4. Annotations are in image pixel coordinates
 5. Shutters hide areas permanently (not just annotations)
 6. Layer order affects rendering (first = bottom)
 7. Text rendering requires font management
 8. Support GSPS creation for clinical workflow
 9. Validate spatial transform values (rotation 0/90/180/270)
 10. Consider performance for large annotation sets
 */
