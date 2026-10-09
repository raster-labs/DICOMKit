// NEMA-verified: 2026a, checked 2026-09-29 — shutter row/column order and (0018,1624) (Tables C.7-17a, C.11.12-1), CIELab encoding (C.10.7.1.1), Displayed Area 1C attributes (Table C.10-4), PIXEL/DISPLAY/MATRIX units (Table C.10-5), LUT VRs (C.11.1.1) per PS3.3 2026a; Compound Graphic Sequence, Text/Line/Fill Style Sequences and anchor-only text objects read per Table C.10-5 (D39, 2026-09-29)
//
// GrayscalePresentationStateParser.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-04.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Parser for Grayscale Softcopy Presentation State objects
///
/// Converts a DICOM DataSet into a `GrayscalePresentationState` structure.
///
/// Reference: PS3.3 Part 3 Section A.33 - Grayscale Softcopy Presentation State IOD
///
/// Example:
/// ```swift
/// let parser = GrayscalePresentationStateParser()
/// let presentationState = try parser.parse(dataSet: dataSet)
/// ```
public struct GrayscalePresentationStateParser: Sendable {
    
    /// Parser errors
    public enum ParseError: Error, Sendable {
        /// Missing required attribute
        case missingRequiredAttribute(tag: String, description: String)
        
        /// Invalid SOP Class UID (not a GSPS)
        case invalidSOPClassUID(String)
        
        /// Invalid SOP Instance UID
        case invalidSOPInstanceUID
        
        /// Invalid LUT descriptor format
        case invalidLUTDescriptor(String)
        
        /// Invalid graphic data
        case invalidGraphicData(String)
        
        /// Invalid shutter data
        case invalidShutterData(String)
    }
    
    /// Creates a new GSPS parser
    public init() {}
    
    // MARK: - Public Parsing API
    
    /// Parses a DICOM DataSet into a GrayscalePresentationState
    ///
    /// - Parameter dataSet: The DICOM data set to parse
    /// - Returns: A parsed grayscale presentation state
    /// - Throws: ParseError if the data set is not a valid GSPS
    public func parse(dataSet: DataSet) throws -> GrayscalePresentationState {
        // Parse SOP Class UID and verify it's a GSPS
        guard let sopClassUID = dataSet.string(for: .sopClassUID) else {
            throw ParseError.missingRequiredAttribute(
                tag: "0008,0016",
                description: "SOP Class UID"
            )
        }
        
        // Verify this is a presentation state this parser can read. Pseudo-Color
        // (PS3.3 A.33.3) is the grayscale IOD's shape plus a Palette Color LUT
        // module and minus the Presentation LUT — everything parsed here means
        // the same thing in both, and the model records which class it was via
        // `sopClassUID`. The palette itself is read separately, through the
        // data set's own `paletteColorLUT()`, by callers that want it.
        // Color Softcopy (A.33.2) is read too: it has no Modality, VOI or
        // Presentation LUT module — every LUT parse below returns nil for it
        // — and carries an ICC profile this model does not hold, but its
        // spatial transformation, displayed area, shutters and graphic
        // annotations are the same modules and mean the same thing. A CSPS
        // shipped with a colour ultrasound is how another viewer's
        // measurements on it arrive, and refusing the file loses them.
        guard sopClassUID == .grayscaleSoftcopyPresentationStateStorage
            || sopClassUID == .pseudoColorSoftcopyPresentationStateStorage
            || sopClassUID == .colorSoftcopyPresentationStateStorage else {
            throw ParseError.invalidSOPClassUID(sopClassUID)
        }
        
        // Parse SOP Instance UID
        guard let sopInstanceUID = dataSet.string(for: .sopInstanceUID) else {
            throw ParseError.invalidSOPInstanceUID
        }
        
        // Parse Presentation State Identification Module
        let instanceNumber = dataSet.integerString(for: .instanceNumber)?.value
        let presentationLabel = dataSet.string(for: .contentLabel)
        let presentationDescription = dataSet.string(for: .contentDescription)
        let presentationCreationDate = dataSet.date(for: .presentationCreationDate)
        let presentationCreationTime = dataSet.time(for: .presentationCreationTime)
        let presentationCreatorsName = dataSet.personName(for: .contentCreatorName)
        
        // Parse Presentation State Relationship Module
        let referencedSeries = try parseReferencedSeries(from: dataSet)
        
        // Parse Display Transformation Modules
        let modalityLUT = try parseModalityLUT(from: dataSet)
        let voiLUT = try parseVOILUT(from: dataSet)
        let presentationLUT = try parsePresentationLUT(from: dataSet)
        
        // Parse Spatial Transformation Module
        let spatialTransformation = parseSpatialTransformation(from: dataSet)
        
        // Parse Displayed Area Module
        let displayedArea = parseDisplayedArea(from: dataSet)
        
        // Parse Graphic Layer Module
        let graphicLayers = parseGraphicLayers(from: dataSet)
        
        // Parse Graphic Annotation Module
        let graphicAnnotations = try parseGraphicAnnotations(from: dataSet)
        
        // Parse Display Shutter Module
        let shutters = try parseDisplayShutters(from: dataSet)

        // Shutter Presentation Color CIELab Value (0018,1624), three US values
        // (Table C.11.12-1; encoding C.10.7.1.1). Read for every class: Type 3
        // in the macro, 1C in the colour classes.
        let shutterPresentationColor = dataSet[Tag(group: 0x0018, element: 0x1624)]?
            .integerValuesTolerant.flatMap(CIELabColor.init(encodedValues:))

        return GrayscalePresentationState(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            instanceNumber: instanceNumber,
            presentationLabel: presentationLabel,
            presentationDescription: presentationDescription,
            presentationCreationDate: presentationCreationDate,
            presentationCreationTime: presentationCreationTime,
            presentationCreatorsName: presentationCreatorsName,
            referencedSeries: referencedSeries,
            modalityLUT: modalityLUT,
            voiLUT: voiLUT,
            presentationLUT: presentationLUT,
            spatialTransformation: spatialTransformation,
            displayedArea: displayedArea,
            graphicLayers: graphicLayers,
            graphicAnnotations: graphicAnnotations,
            shutters: shutters,
            shutterPresentationColor: shutterPresentationColor
        )
    }
    
    // MARK: - Private Parsing Methods
    
    private func parseReferencedSeries(from dataSet: DataSet) throws -> [ReferencedSeries] {
        guard let seriesSequence = dataSet.sequence(for: .referencedSeriesSequence) else {
            throw ParseError.missingRequiredAttribute(
                tag: "0008,1115",
                description: "Referenced Series Sequence"
            )
        }
        
        var result: [ReferencedSeries] = []
        for item in seriesSequence {
            guard let seriesInstanceUID = item.string(for: .seriesInstanceUID) else {
                continue
            }
            
            let referencedImages: [ReferencedImage]
            if let imageSequence = item[.referencedImageSequence]?.sequenceItems {
                referencedImages = imageSequence.compactMap { imageItem in
                    guard let sopClassUID = imageItem.string(for: .referencedSOPClassUID),
                          let sopInstanceUID = imageItem.string(for: .referencedSOPInstanceUID) else {
                        return nil
                    }
                    
                    let frameNumbers = imageItem[.referencedFrameNumber]?.integerStringValues?.map { $0.value }
                    
                    return ReferencedImage(
                        sopClassUID: sopClassUID,
                        sopInstanceUID: sopInstanceUID,
                        referencedFrameNumbers: frameNumbers
                    )
                }
            } else {
                referencedImages = []
            }
            
            result.append(ReferencedSeries(
                seriesInstanceUID: seriesInstanceUID,
                referencedImages: referencedImages
            ))
        }
        
        return result
    }
    
    private func parseModalityLUT(from dataSet: DataSet) throws -> ModalityLUT? {
        // Check for LUT Sequence first
        if let lutSequence = dataSet.sequence(for: .modalityLUTSequence),
           let firstItem = lutSequence.first {
            let lutData = try parseLUTData(from: firstItem)
            return .lut(lutData)
        }
        
        // Check for Rescale Slope/Intercept
        if let slope = dataSet.decimalString(for: .rescaleSlope)?.value,
           let intercept = dataSet.decimalString(for: .rescaleIntercept)?.value {
            let type = dataSet.string(for: .rescaleType)
            return .rescale(slope: slope, intercept: intercept, type: type)
        }
        
        return nil
    }
    
    private func parseVOILUT(from dataSet: DataSet) throws -> VOILUT? {
        // The Softcopy VOI LUT Sequence (C.11.8) is where a presentation
        // state's window actually lives — read it first. The top-level
        // spelling below stays as the fallback that keeps files written by
        // older builds (which wrote only top-level) restoring their window.
        if let softcopySequence = dataSet.sequence(for: .softcopyVOILUTSequence),
           let item = softcopySequence.first {
            if let center = item.strings(for: .windowCenter)?.first.flatMap(Self.decimal),
               let width = item.strings(for: .windowWidth)?.first.flatMap(Self.decimal) {
                let explanation = item.string(for: .windowCenterWidthExplanation)
                let function = VOILUTFunction.parse(item.string(for: .voiLUTFunction))
                return .window(
                    center: center, width: width,
                    explanation: explanation, function: function)
            }
            if let lutItem = item[.voiLUTSequence]?.sequenceItems?.first {
                return .lut(try parseLUTData(from: lutItem))
            }
        }

        // Check for LUT Sequence first
        if let lutSequence = dataSet.sequence(for: .voiLUTSequence),
           let firstItem = lutSequence.first {
            let lutData = try parseLUTData(from: firstItem)
            return .lut(lutData)
        }
        
        // Check for Window Center/Width
        if let centers = dataSet.decimalStrings(for: .windowCenter)?.map({ $0.value }),
           let widths = dataSet.decimalStrings(for: .windowWidth)?.map({ $0.value }),
           let center = centers.first,
           let width = widths.first {
            let explanation = dataSet.string(for: .windowCenterWidthExplanation)
            let functionString = dataSet.string(for: .voiLUTFunction)
            let function = VOILUTFunction.parse(functionString)
            
            return .window(center: center, width: width, explanation: explanation, function: function)
        }
        
        return nil
    }
    
    /// A DS value as the parser needs it: trimmed and numeric, or nil.
    private static func decimal(_ raw: String) -> Double? {
        Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parsePresentationLUT(from dataSet: DataSet) throws -> PresentationLUT? {
        // Check for Presentation LUT Sequence
        if let lutSequence = dataSet.sequence(for: .presentationLUTSequence),
           let firstItem = lutSequence.first {
            let lutData = try parseLUTData(from: firstItem)
            return .lut(lutData)
        }
        
        // Check for Presentation LUT Shape
        if let shape = dataSet.string(for: .presentationLUTShape) {
            switch shape {
            case "IDENTITY":
                return .identity
            case "INVERSE":
                return .inverse
            default:
                return .identity
            }
        }
        
        return nil
    }
    
    private func parseLUTData(from item: SequenceItem) throws -> LUTData {
        // LUT Descriptor (0028,3002) is US or SS; LUT Data (0028,3006) is US or OW
        // (C.11.1.1). Files that carried them as IS are still read.
        func integers(_ element: DataElement?) -> [Int]? {
            guard let element else { return nil }
            if element.vr == .OW || element.vr == .OB {
                return element.uint16Values?.map(Int.init)
            }
            return element.integerValuesTolerant
        }
        guard var descriptorInts = integers(item[.lutDescriptor]), descriptorInts.count == 3 else {
            throw ParseError.invalidLUTDescriptor("Missing LUT Descriptor")
        }
        // The first mapped value of a descriptor read as US may be a two's-complement SS
        if item[.lutDescriptor]?.vr == .US, descriptorInts[1] > 32767, descriptorInts[0] != 0,
           descriptorInts[1] + descriptorInts[0] > 65536 {
            descriptorInts[1] -= 65536
        }

        guard let data = integers(item[.lutData]) else {
            throw ParseError.invalidLUTDescriptor("Missing LUT Data")
        }
        
        let explanation = item.string(for: .lutExplanation)
        
        guard let lutData = LUTData.parse(descriptor: descriptorInts, data: data, explanation: explanation) else {
            throw ParseError.invalidLUTDescriptor("Invalid LUT Descriptor format")
        }
        
        return lutData
    }
    
    private func parseSpatialTransformation(from dataSet: DataSet) -> SpatialTransformation? {
        let rotation = dataSet[.imageRotation]?.integerValueTolerant ?? 0
        let flipString = dataSet.string(for: .imageHorizontalFlip)
        let horizontalFlip = flipString == "Y"
        
        if rotation != 0 || horizontalFlip {
            return SpatialTransformation(rotation: rotation, horizontalFlip: horizontalFlip)
        }
        
        return nil
    }
    
    private func parseDisplayedArea(from dataSet: DataSet) -> DisplayedArea? {
        guard let displayedAreaSequence = dataSet.sequence(for: .displayedAreaSelectionSequence),
              let firstItem = displayedAreaSequence.first else {
            return nil
        }
        
        guard let topLeftValues = firstItem[.displayedAreaTopLeftHandCorner]?.integerValuesTolerant,
              topLeftValues.count == 2,
              let bottomRightValues = firstItem[.displayedAreaBottomRightHandCorner]?.integerValuesTolerant,
              bottomRightValues.count == 2 else {
            return nil
        }
        
        let topLeft = (column: topLeftValues[0], row: topLeftValues[1])
        let bottomRight = (column: bottomRightValues[0], row: bottomRightValues[1])
        
        let sizeModeString = firstItem.string(for: .presentationSizeMode)?
            .trimmingCharacters(in: .whitespaces) ?? "SCALE TO FIT"
        let sizeMode = PresentationSizeMode(rawValue: sizeModeString) ?? .scaleToFit

        // Table C.10-4 Type 1C attributes. Presentation Pixel Spacing (0070,0101)
        // is DS, row spacing then column spacing (10.7.1.3); Presentation Pixel
        // Aspect Ratio (0070,0102) is IS, vertical then horizontal; Presentation
        // Pixel Magnification Ratio (0070,0103) is FL.
        var pixelSpacing: (row: Double, column: Double)? = nil
        if let spacing = firstItem[.presentationPixelSpacing]?.realValuesTolerant,
           spacing.count == 2 {
            pixelSpacing = (row: spacing[0], column: spacing[1])
        }
        var pixelAspectRatio: (vertical: Int, horizontal: Int)? = nil
        if let ratio = firstItem[.presentationPixelAspectRatio]?.integerValuesTolerant,
           ratio.count == 2 {
            pixelAspectRatio = (vertical: ratio[0], horizontal: ratio[1])
        }
        let magnificationRatio = firstItem[.presentationPixelMagnificationRatio]?
            .realValuesTolerant?.first

        return DisplayedArea(
            topLeft: topLeft,
            bottomRight: bottomRight,
            sizeMode: sizeMode,
            pixelSpacing: pixelSpacing,
            pixelAspectRatio: pixelAspectRatio,
            magnificationRatio: magnificationRatio)
    }
    
    private func parseGraphicLayers(from dataSet: DataSet) -> [GraphicLayer] {
        guard let layerSequence = dataSet.sequence(for: .graphicLayerSequence) else {
            return []
        }
        
        return layerSequence.compactMap { item in
            guard let name = item.string(for: .graphicLayer),
                  let order = item[.graphicLayerOrder]?.integerStringValue?.value else {
                return nil
            }
            
            let description = item.string(for: .graphicLayerDescription)
            let grayscaleValue = item[.graphicLayerRecommendedDisplayGrayscaleValue]?.integerValueTolerant
            
            // Graphic Layer Recommended Display CIELab Value (0070,0401) is the current
            // attribute (C.10.7); the retired RGB value (0070,0067) is read for older files.
            var rgbValue: (red: Int, green: Int, blue: Int)? = nil
            if let lab = item[Tag(group: 0x0070, element: 0x0401)]?.integerValuesTolerant,
               let rgb = GrayscalePresentationStateBuilder.rgb(fromCIELabEncoded: lab) {
                rgbValue = rgb
            } else if let rgbValues = item[.graphicLayerRecommendedDisplayRGBValue]?.integerValuesTolerant,
                      rgbValues.count == 3 {
                rgbValue = (red: rgbValues[0], green: rgbValues[1], blue: rgbValues[2])
            }
            
            return GraphicLayer(
                name: name,
                order: order,
                description: description,
                recommendedGrayscaleValue: grayscaleValue,
                recommendedRGBValue: rgbValue
            )
        }
    }
    
    private func parseGraphicAnnotations(from dataSet: DataSet) throws -> [GraphicAnnotation] {
        guard let annotationSequence = dataSet.sequence(for: .graphicAnnotationSequence) else {
            return []
        }
        
        var result: [GraphicAnnotation] = []
        for item in annotationSequence {
            guard let layer = item.string(for: .graphicLayer) else {
                continue
            }
            
            // Parse referenced images
            var referencedImages: [ReferencedImage] = []
            if let refImageSeq = item[.referencedImageSequence]?.sequenceItems {
                referencedImages = refImageSeq.compactMap { refItem in
                    guard let sopClassUID = refItem.string(for: .referencedSOPClassUID),
                          let sopInstanceUID = refItem.string(for: .referencedSOPInstanceUID) else {
                        return nil
                    }
                    
                    let frameNumbers = refItem[.referencedFrameNumber]?.integerStringValues?.map { $0.value }
                    
                    return ReferencedImage(
                        sopClassUID: sopClassUID,
                        sopInstanceUID: sopInstanceUID,
                        referencedFrameNumbers: frameNumbers
                    )
                }
            }
            
            // Parse graphic objects
            var graphicObjects: [GraphicObject] = []
            if let graphicSeq = item[.graphicObjectSequence]?.sequenceItems {
                graphicObjects = try graphicSeq.compactMap { graphicItem in
                    try parseGraphicObject(from: graphicItem)
                }
            }
            
            // Parse text objects
            var textObjects: [TextObject] = []
            if let textSeq = item[.textObjectSequence]?.sequenceItems {
                textObjects = textSeq.compactMap { textItem in
                    parseTextObject(from: textItem)
                }
            }
            
            // Compound Graphic Sequence (Table C.10-5); an item this parser
            // cannot read is skipped — its alternate rendering above still is.
            let compoundGraphics = (item[.compoundGraphicSequence]?.sequenceItems ?? [])
                .compactMap(Self.parseCompoundGraphic)

            result.append(GraphicAnnotation(
                layer: layer,
                referencedImages: referencedImages,
                graphicObjects: graphicObjects,
                textObjects: textObjects,
                compoundGraphics: compoundGraphics
            ))
        }
        
        return result
    }
    
    private func parseGraphicObject(from item: SequenceItem) throws -> GraphicObject? {
        guard let typeString = item.string(for: .graphicType),
              let type = PresentationGraphicType(rawValue: typeString),
              let data = item[.graphicData]?.realValuesTolerant else {
            return nil
        }
        
        let filledString = item.string(for: .graphicFilled)
        let filled = filledString == "Y"

        // Graphic Annotation Units (0070,0005) is the graphic object's own units
        // attribute; the bounding-box tag is kept as a fallback for files this
        // parser accepted before the distinction was made. PIXEL, DISPLAY and
        // MATRIX (Table C.10-5) are all carried; a value outside the enumeration
        // skips the object rather than misplace it.
        let unitsString = item.string(for: .graphicAnnotationUnits)
            ?? item.string(for: .boundingBoxAnnotationUnits) ?? "PIXEL"
        guard let units = AnnotationUnits(rawValue: unitsString.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        return GraphicObject(
            type: type, data: data, filled: filled, units: units,
            lineStyle: item[.lineStyleSequence]?.sequenceItems?.first.flatMap(Self.parseLineStyle),
            fillStyle: item[.fillStyleSequence]?.sequenceItems?.first.flatMap(Self.parseFillStyle),
            compoundGraphicInstanceID: item[.compoundGraphicInstanceID]?.integerValueTolerant,
            graphicGroupID: item[.graphicGroupID]?.integerValueTolerant)
    }

    // MARK: Compound graphics and styles (Tables C.10-5, C.10-5a/5b/5c; D39)

    private static func trimmed(_ item: SequenceItem, _ tag: Tag) -> String? {
        item.string(for: tag)?.trimmingCharacters(in: .whitespaces)
    }

    private static func cieLab(_ item: SequenceItem, _ tag: Tag) -> CIELabColor? {
        guard let values = item[tag]?.integerValuesTolerant, values.count == 3 else { return nil }
        return CIELabColor(l: values[0], a: values[1], b: values[2])
    }

    private static func real(_ item: SequenceItem, _ tag: Tag) -> Double? {
        item[tag]?.realValuesTolerant?.first
    }

    private static func parseShadow(_ item: SequenceItem) -> GraphicShadow {
        guard let style = trimmed(item, .shadowStyle).flatMap(GraphicShadowStyle.init(rawValue:)) else {
            return .off
        }
        return GraphicShadow(
            style: style,
            offsetX: real(item, .shadowOffsetX) ?? 0,
            offsetY: real(item, .shadowOffsetY) ?? 0,
            color: cieLab(item, .shadowColorCIELabValue) ?? GraphicShadow.black,
            opacity: real(item, .shadowOpacity) ?? 1)
    }

    static func parseTextStyle(_ item: SequenceItem) -> TextStyle? {
        guard let color = cieLab(item, .textColorCIELabValue) else { return nil }
        return TextStyle(
            fontName: item.string(for: .fontName),
            fontNameType: trimmed(item, .fontNameType),
            cssFontName: item.string(for: .cssFontName) ?? "sans-serif",
            color: color,
            horizontalAlignment: trimmed(item, .horizontalAlignment).flatMap(TextHorizontalAlignment.init(rawValue:)),
            verticalAlignment: trimmed(item, .verticalAlignment).flatMap(TextVerticalAlignment.init(rawValue:)),
            shadow: parseShadow(item),
            underlined: trimmed(item, .underlined) == "Y",
            bold: trimmed(item, .bold) == "Y",
            italic: trimmed(item, .italic) == "Y")
    }

    static func parseLineStyle(_ item: SequenceItem) -> LineStyle? {
        guard let color = cieLab(item, .patternOnColorCIELabValue) else { return nil }
        return LineStyle(
            onColor: color,
            offColor: cieLab(item, .patternOffColorCIELabValue),
            onOpacity: real(item, .patternOnOpacity) ?? 1,
            offOpacity: real(item, .patternOffOpacity),
            thickness: real(item, .lineThickness) ?? 1,
            dashing: trimmed(item, .lineDashingStyle).flatMap(LineDashingStyle.init(rawValue:)) ?? .solid,
            pattern: item[.linePattern]?.integerValueTolerant.map { UInt32(truncatingIfNeeded: $0) },
            shadow: parseShadow(item))
    }

    static func parseFillStyle(_ item: SequenceItem) -> FillStyle? {
        guard let color = cieLab(item, .patternOnColorCIELabValue) else { return nil }
        return FillStyle(
            onColor: color,
            offColor: cieLab(item, .patternOffColorCIELabValue),
            onOpacity: real(item, .patternOnOpacity) ?? 1,
            offOpacity: real(item, .patternOffOpacity) ?? 0,
            mode: trimmed(item, .fillMode).flatMap(GraphicFillMode.init(rawValue:)) ?? .solid,
            pattern: item[.fillPattern]?.valueData)
    }

    static func parseCompoundGraphic(_ item: SequenceItem) -> CompoundGraphic? {
        guard let id = item[.compoundGraphicInstanceID]?.integerValueTolerant,
              let type = trimmed(item, .compoundGraphicType).flatMap(CompoundGraphicType.init(rawValue:)),
              let units = trimmed(item, .compoundGraphicUnits).flatMap(CompoundGraphicUnits.init(rawValue:)),
              let data = item[.graphicData]?.realValuesTolerant else { return nil }
        let rotationPoint = item[.rotationPoint]?.realValuesTolerant.flatMap { values in
            values.count == 2 ? GraphicPoint(column: values[0], row: values[1]) : nil
        }
        let ticks = (item[.majorTicksSequence]?.sequenceItems ?? []).compactMap { tick -> MajorTick? in
            guard let position = real(tick, .tickPosition) else { return nil }
            return MajorTick(position: position, label: tick.string(for: .tickLabel) ?? "")
        }
        return CompoundGraphic(
            instanceID: id, type: type, units: units, data: data,
            textStyle: item[.textStyleSequence]?.sequenceItems?.first.flatMap(parseTextStyle),
            lineStyle: item[.lineStyleSequence]?.sequenceItems?.first.flatMap(parseLineStyle),
            rotationAngle: real(item, .rotationAngle),
            rotationPoint: rotationPoint,
            gapLength: real(item, .gapLength),
            diameterOfVisibility: real(item, .diameterOfVisibility),
            majorTicks: ticks,
            tickAlignment: trimmed(item, .tickAlignment).flatMap(TickAlignment.init(rawValue:)),
            tickLabelAlignment: trimmed(item, .tickLabelAlignment).flatMap(TickLabelAlignment.init(rawValue:)),
            showTickLabel: trimmed(item, .showTickLabel).map { $0 == "Y" },
            filled: trimmed(item, .graphicFilled) == "Y",
            fillStyle: item[.fillStyleSequence]?.sequenceItems?.first.flatMap(parseFillStyle),
            graphicGroupID: item[.graphicGroupID]?.integerValueTolerant)
    }
    
    private func parseTextObject(from item: SequenceItem) -> TextObject? {
        // (0070,0006) is the Text Object's own Unformatted Text Value; (0040,A160)
        // is SR's Text Value, read as a fallback for files written when this
        // parser used the wrong tag.
        guard let text = item.string(for: .unformattedTextValue)
                ?? item.string(for: .textValue) else {
            return nil
        }

        var anchorPoint: (column: Double, row: Double)? = nil
        if let anchorValues = item[.anchorPoint]?.realValuesTolerant,
           anchorValues.count == 2 {
            anchorPoint = (column: anchorValues[0], row: anchorValues[1])
        }

        // The bounding box is Type 1C: "Required if Anchor Point is not
        // present" (Table C.10-5), so an anchor-only text object is legal. The
        // model needs a box; it is the anchor itself, which renderers of this
        // model read as "the words start here".
        let topLeftValues = item[.boundingBoxTopLeftHandCorner]?.realValuesTolerant
        let bottomRightValues = item[.boundingBoxBottomRightHandCorner]?.realValuesTolerant
        let topLeft: (column: Double, row: Double)
        let bottomRight: (column: Double, row: Double)
        if let tl = topLeftValues, tl.count == 2, let br = bottomRightValues, br.count == 2 {
            topLeft = (column: tl[0], row: tl[1])
            bottomRight = (column: br[0], row: br[1])
        } else if let anchor = anchorPoint {
            topLeft = anchor
            bottomRight = anchor
        } else {
            return nil
        }
        
        let anchorVisibleString = item.string(for: .anchorPointVisibility)
        let anchorVisible = anchorVisibleString == "Y"
        
        // A units value outside Table C.10-5's enumeration skips the object rather than misplace it
        let boundingBoxUnitsString = item.string(for: .boundingBoxAnnotationUnits)
            ?? item.string(for: .anchorPointAnnotationUnits) ?? "PIXEL"
        guard let boundingBoxUnits = AnnotationUnits(rawValue: boundingBoxUnitsString.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        let anchorPointUnitsString = item.string(for: .anchorPointAnnotationUnits) ?? "PIXEL"
        guard let anchorPointUnits = AnnotationUnits(rawValue: anchorPointUnitsString.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        
        return TextObject(
            text: text,
            boundingBoxTopLeft: topLeft,
            boundingBoxBottomRight: bottomRight,
            anchorPoint: anchorPoint,
            anchorPointVisible: anchorVisible,
            boundingBoxUnits: boundingBoxUnits,
            anchorPointUnits: anchorPointUnits,
            textStyle: item[.textStyleSequence]?.sequenceItems?.first.flatMap(Self.parseTextStyle),
            compoundGraphicInstanceID: item[.compoundGraphicInstanceID]?.integerValueTolerant,
            graphicGroupID: item[.graphicGroupID]?.integerValueTolerant
        )
    }
    
    private func parseDisplayShutters(from dataSet: DataSet) throws -> [DisplayShutter] {
        guard let shapesString = dataSet.string(for: .shutterShape) else {
            return []
        }
        
        let shapes = shapesString.split(separator: "\\").map { String($0) }
        var shutters: [DisplayShutter] = []
        
        let presentationValue = dataSet.uint16(for: .shutterPresentationValue).map { Int($0) }
        
        for shape in shapes {
            switch shape {
            case "RECTANGULAR":
                if let left = dataSet.integerString(for: .shutterLeftVerticalEdge)?.value,
                   let right = dataSet.integerString(for: .shutterRightVerticalEdge)?.value,
                   let top = dataSet.integerString(for: .shutterUpperHorizontalEdge)?.value,
                   let bottom = dataSet.integerString(for: .shutterLowerHorizontalEdge)?.value {
                    shutters.append(.rectangular(
                        left: left,
                        right: right,
                        top: top,
                        bottom: bottom,
                        presentationValue: presentationValue
                    ))
                }
                
            case "CIRCULAR":
                if let centerValues = dataSet.integerStrings(for: .centerOfCircularShutter)?.map({ $0.value }),
                   centerValues.count == 2,
                   let radius = dataSet.integerString(for: .radiusOfCircularShutter)?.value {
                    // (0018,1610) is "row and column" (C.7.6.11)
                    shutters.append(.circular(
                        centerColumn: centerValues[1],
                        centerRow: centerValues[0],
                        radius: radius,
                        presentationValue: presentationValue
                    ))
                }
                
            case "POLYGONAL":
                if let vertexData = dataSet.integerStrings(for: .verticesOfThePolygonalShutter)?.map({ $0.value }),
                   vertexData.count >= 6, vertexData.count % 2 == 0 {
                    // (0018,1620) is row\column pairs (C.7.6.11)
                    var vertices: [(column: Int, row: Int)] = []
                    for i in stride(from: 0, to: vertexData.count, by: 2) {
                        vertices.append((column: vertexData[i+1], row: vertexData[i]))
                    }
                    shutters.append(.polygonal(vertices: vertices, presentationValue: presentationValue))
                }
                
            case "BITMAP":
                if let overlayGroup = dataSet.uint16(for: .shutterOverlayGroup).map({ Int($0) }) {
                    shutters.append(.bitmap(overlayGroup: overlayGroup, presentationValue: presentationValue))
                }
                
            default:
                break
            }
        }
        
        return shutters
    }
}
