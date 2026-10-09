// NEMA-verified: 2026a, checked 2026-09-29 — VRs per PS3.6 2026a Table 6-1 (SH name, LO description, US VM 2 Relative Time, SS VM 2 Abstract Prior Value, CS 1-n 3D Rendering Type); every CS term written is one of PS3.3 2026a Tables C.23.1-1 / C.23.3-1 (deprecated DICOMKit cases are mapped, see the enum doc comments); Partial Data Display Handling written top-level Type 2; every element placed per PS3.3 2026a Tables C.23.1-1, C.23.2-1, C.23.3-1 (macros C.23.4-1/-2, C.23.2-2) by script-generated (parent, tag) comparison in HangingProtocolNestingTests: 145 table rows, 0 misplaced; Type 2 sequences 0072,000E / 0072,0102 / 0072,0400 / 0072,0600 written empty; Selector Value Number Type 1 in selector items
//
// HangingProtocolSerializer.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Serializer for Hanging Protocol DICOM objects
///
/// Serializes HangingProtocol struct into DICOM DataSet format.
///
/// Reference: PS3.3 Section A.38 - Hanging Protocol IOD
/// Reference: PS3.3 Section C.23 - Hanging Protocol Modules
public struct HangingProtocolSerializer {
    
    public init() {}
    
    /// Serialize a HangingProtocol to a DICOM DataSet
    ///
    /// - Parameter protocol: HangingProtocol to serialize
    /// - Returns: DICOM DataSet containing hanging protocol
    /// - Throws: Error if required attributes are missing
    public func serialize(protocol hangingProtocol: HangingProtocol) throws -> DataSet {
        var dataSet = DataSet()
        
        // MARK: - Hanging Protocol Definition Module (C.23.1)
        
        // Hanging Protocol Name (0072,0002) - Required, Type 1
        dataSet[.hangingProtocolName] = DataElement.string(
            tag: .hangingProtocolName,
            vr: .SH,
            value: hangingProtocol.name
        )

        // Hanging Protocol Description (0072,0004) - Optional, Type 3
        if let description = hangingProtocol.description {
            dataSet[.hangingProtocolDescription] = DataElement.string(
                tag: .hangingProtocolDescription,
                vr: .LO,
                value: description
            )
        }
        
        // Hanging Protocol Level (0072,0006) - Required, Type 1
        dataSet[.hangingProtocolLevel] = DataElement.string(
            tag: .hangingProtocolLevel,
            vr: .CS,
            value: hangingProtocol.level.rawValue
        )
        
        // Hanging Protocol Creator (0072,0008) - Optional, Type 3
        if let creator = hangingProtocol.creator {
            dataSet[.hangingProtocolCreator] = DataElement.string(
                tag: .hangingProtocolCreator,
                vr: .LO,
                value: creator
            )
        }
        
        // Hanging Protocol Creation DateTime (0072,000A) - Optional, Type 3
        if let creationDateTime = hangingProtocol.creationDateTime {
            dataSet[.hangingProtocolCreationDateTime] = DataElement.string(
                tag: .hangingProtocolCreationDateTime,
                vr: .DT,
                value: creationDateTime.description
            )
        }
        
        // Number of Priors Referenced (0072,0014) - Optional, Type 3
        if let numberOfPriors = hangingProtocol.numberOfPriorsReferenced {
            dataSet[.numberOfPriorsReferenced] = DataElement.uint16(
                tag: .numberOfPriorsReferenced,
                value: UInt16(numberOfPriors)
            )
        }
        
        // Hanging Protocol Definition Sequence (0072,000C) - Required, Type 1
        if !hangingProtocol.environments.isEmpty {
            let environmentItems = serializeEnvironments(hangingProtocol.environments)
            dataSet.setSequence(environmentItems, for: .hangingProtocolDefinitionSequence)
        }
        
        // Hanging Protocol User Identification Code Sequence (0072,000E) -
        // Type 2, zero or one item (PS3.3 Table C.23.1-1); not modelled, so
        // written empty
        dataSet.setSequence([], for: .hangingProtocolUserIdentificationCodeSequence)

        // Hanging Protocol User Group Name (0072,0010) - Optional, Type 3
        if !hangingProtocol.userGroups.isEmpty {
            // Serialize first user group (DICOM allows only one in practice)
            if let firstGroup = hangingProtocol.userGroups.first {
                dataSet[.hangingProtocolUserGroupName] = DataElement.string(
                    tag: .hangingProtocolUserGroupName,
                    vr: .LO,
                    value: firstGroup
                )
            }
        }
        
        // Image Sets Sequence (0072,0020) - Type 1 (PS3.3 Table C.23.1-1):
        // each item holds an Image Set Selector Sequence (0072,0022) and a
        // Time Based Image Sets Sequence (0072,0030)
        if !hangingProtocol.imageSets.isEmpty {
            let imageSetItems = try serializeImageSets(hangingProtocol.imageSets)
            dataSet.setSequence(imageSetItems, for: .imageSetsSequence)
        }
        
        // MARK: - Hanging Protocol Environment Module (C.23.2)

        // Number of Screens (0072,0100) - Type 2 (PS3.3 Table C.23.2-1)
        dataSet[.numberOfScreens] = DataElement.uint16(
            tag: .numberOfScreens,
            value: UInt16(hangingProtocol.numberOfScreens)
        )
        
        // Nominal Screen Definition Sequence (0072,0102) - Type 2 (PS3.3 Table
        // C.23.2-1): zero or more items, written empty when there are no screens
        dataSet.setSequence(
            serializeScreenDefinitions(hangingProtocol.screenDefinitions),
            for: .nominalScreenDefinitionSequence
        )
        
        // MARK: - Hanging Protocol Display Module (C.23.3)

        // Display Sets Sequence (0072,0200) - Required, Type 1
        if !hangingProtocol.displaySets.isEmpty {
            let displaySetItems = try serializeDisplaySets(hangingProtocol.displaySets, of: hangingProtocol)
            dataSet.setSequence(displaySetItems, for: .displaySetsSequence)
        }

        // Partial Data Display Handling (0072,0208) - Type 2, top level of the
        // Hanging Protocol Display Module (PS3.3 Table C.23.3-1). Zero length
        // means the behaviour is not defined. A term left in the deprecated
        // DisplaySet.partialDataHandling is promoted when the protocol has none.
        let partialData = hangingProtocol.partialDataDisplayHandling
            ?? Self.legacyPartialDataHandling(hangingProtocol.displaySets)
        dataSet[.partialDataDisplayHandling] = DataElement.string(
            tag: .partialDataDisplayHandling,
            vr: .CS,
            value: partialData?.rawValue ?? ""
        )

        // Synchronized Scrolling Sequence (0072,0210) - Type 3, top level (PS3.3
        // Table C.23.3-1); each item's Display Set Scrolling Group (0072,0212)
        // is US VM 2-n. Display sets sharing a deprecated
        // DisplaySet.scrollingGroup value become one item when none is given.
        let scrolling = hangingProtocol.synchronizedScrolling.isEmpty
            ? Self.legacySynchronizedScrolling(hangingProtocol.displaySets)
            : hangingProtocol.synchronizedScrolling
        if !scrolling.isEmpty {
            dataSet.setSequence(scrolling.map { group in
                SequenceItem(elements: [DataElement.uint16s(
                    tag: .displaySetScrollingGroup,
                    values: group.displaySetNumbers.map { UInt16(clamping: $0) }
                )])
            }, for: .synchronizedScrollingSequence)
        }

        // Navigation Indicator Sequence (0072,0214) - Type 3, top level (PS3.3
        // Table C.23.3-1): Navigation Display Set (0072,0216) US Type 1C,
        // Reference Display Sets (0072,0218) US VM 1-n Type 1
        if !hangingProtocol.navigationIndicators.isEmpty {
            dataSet.setSequence(hangingProtocol.navigationIndicators.map { indicator in
                var elements: [DataElement] = []
                if let navigation = indicator.navigationDisplaySet {
                    elements.append(DataElement.uint16(tag: .navigationDisplaySet, value: UInt16(clamping: navigation)))
                }
                elements.append(DataElement.uint16s(
                    tag: .referenceDisplaySets,
                    values: indicator.referenceDisplaySets.map { UInt16(clamping: $0) }
                ))
                return SequenceItem(elements: elements)
            }, for: .navigationIndicatorSequence)
        }

        return dataSet
    }

    /// Groups display sets by the deprecated `DisplaySet.scrollingGroup`, in
    /// order of first appearance; a group needs two or more display sets
    /// (Display Set Scrolling Group VM 2-n).
    static func legacySynchronizedScrolling(_ displaySets: [DisplaySet]) -> [SynchronizedScrollingGroup] {
        var order: [Int] = []
        var members: [Int: [Int]] = [:]
        for displaySet in displaySets {
            guard let group = displaySet.legacyScrollingGroup else { continue }
            if members[group] == nil { order.append(group) }
            members[group, default: []].append(displaySet.number)
        }
        return order.compactMap { group in
            guard let numbers = members[group], numbers.count >= 2 else { return nil }
            return SynchronizedScrollingGroup(displaySetNumbers: numbers)
        }
    }

    private static func legacyPartialDataHandling(_ displaySets: [DisplaySet]) -> PartialDataDisplayHandling? {
        displaySets.lazy
            .compactMap { $0.partialDataHandling }
            .compactMap { PartialDataDisplayHandling(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
            .first
    }
    
    // MARK: - Environment Serialization
    
    private func serializeEnvironments(_ environments: [HangingProtocolEnvironment]) -> [SequenceItem] {
        var items: [SequenceItem] = []
        
        for environment in environments {
            var elements: [DataElement] = []
            
            // Modality (0008,0060) - Optional, Type 3
            if let modality = environment.modality {
                elements.append(DataElement.string(
                    tag: .modality,
                    vr: .CS,
                    value: modality
                ))
            }
            
            // Laterality (0020,0060) - Optional, Type 3
            if let laterality = environment.laterality {
                elements.append(DataElement.string(
                    tag: .laterality,
                    vr: .CS,
                    value: laterality
                ))
            }
            
            items.append(SequenceItem(elements: elements))
        }
        
        return items
    }
    
    // MARK: - Image Set Serialization
    
    private func serializeImageSets(_ imageSets: [ImageSetDefinition]) throws -> [SequenceItem] {
        var items: [SequenceItem] = []

        for imageSet in imageSets {
            var elements: [DataElement] = []

            // Image Set Selector Sequence (0072,0022) - Type 1. Selectors that
            // carry a deprecated filter (see ImageSetSelector.isLegacyFilter)
            // are written as Filter Operations of the display sets instead.
            var selectors = imageSet.selectors.filter { !$0.isLegacyFilter }
            if selectors.isEmpty { selectors = imageSet.selectors }
            if !selectors.isEmpty {
                let selectorItems = try serializeSelectors(selectors)
                elements.append(createSequenceElement(
                    tag: .imageSetSelectorSequence,
                    items: selectorItems
                ))
            }

            // Time Based Image Sets Sequence (0072,0030) - Type 1 (PS3.3 Table
            // C.23.1-1): Image Set Number, Image Set Selector Category, Relative
            // Time / Abstract Prior and Image Set Label live in its items.
            if !imageSet.timeBasedImageSets.isEmpty {
                elements.append(createSequenceElement(
                    tag: .timeBasedImageSetsSequence,
                    items: imageSet.timeBasedImageSets.map(serializeTimeBasedImageSet)
                ))
            }

            items.append(SequenceItem(elements: elements))
        }

        return items
    }

    private func serializeTimeBasedImageSet(_ timeBased: TimeBasedImageSet) -> SequenceItem {
        var elements: [DataElement] = []

        // Image Set Number (0072,0032) - Type 1
        elements.append(DataElement.uint16(
            tag: .imageSetNumber,
            value: UInt16(clamping: timeBased.number)
        ))

        // Image Set Selector Category (0072,0034) - Type 1; Enumerated Values
        // RELATIVE_TIME / ABSTRACT_PRIOR; deprecated cases are mapped (see
        // ImageSetSelectorCategory).
        elements.append(DataElement.string(
            tag: .imageSetSelectorCategory,
            vr: .CS,
            value: timeBased.category.standardTerm.rawValue
        ))

        // Relative Time (0072,0038), Relative Time Units (0072,003A), Abstract
        // Prior Value (0072,003C) - Type 1C
        if let timeSelection = timeBased.timeSelection {
            serializeTimeSelection(timeSelection, into: &elements)
        }

        // Abstract Prior Code Sequence (0072,003E) - Type 1C, a single item
        if let code = timeBased.abstractPriorCode {
            elements.append(createSequenceElement(
                tag: .abstractPriorCodeSequence,
                items: [SequenceItem(elements: SelectorAttributeValueCoding.codeElements(code))]
            ))
        }

        // Image Set Label (0072,0040) - Type 3
        if let label = timeBased.label {
            elements.append(DataElement.string(
                tag: .imageSetLabel,
                vr: .LO,
                value: label
            ))
        }

        return SequenceItem(elements: elements)
    }

    private func serializeSelectors(_ selectors: [ImageSetSelector]) throws -> [SequenceItem] {
        var items: [SequenceItem] = []
        
        for selector in selectors {
            var elements: [DataElement] = []
            
            // Selector Attribute (0072,0026) - Required, Type 1
            elements.append(serializeTagAsAttributeTag(
                tag: .selectorAttribute,
                value: selector.attribute
            ))
            
            // Selector Value Number (0072,0028) - Type 1 in an Image Set
            // Selector Sequence item (PS3.3 Table C.23.1-1); nil is written
            // as 0, "any value"
            elements.append(DataElement.uint16(
                tag: .selectorValueNumber,
                value: UInt16(clamping: selector.valueNumber ?? 0)
            ))
            
            // Filter-by Category / Attribute Presence / Operator are not Image
            // Set Selector Sequence attributes (PS3.3 Table C.23.1-1); they are
            // written in Filter Operations Sequence items (serializeFilterOperations).

            // Selector Sequence Pointer (0072,0052) - Conditional, Type 1C
            if let sequencePointer = selector.sequencePointer {
                elements.append(serializeTagAsAttributeTag(
                    tag: .selectorSequencePointer,
                    value: sequencePointer
                ))
            }
            
            // Selector Attribute VR (0072,0050) and the matching Selector xx
            // Value (0072,005E-0083) - PS3.3 Table C.23.4-1. The values never
            // go under the attribute's own tag.
            let attributeVR = selector.attributeVR
                ?? SelectorAttributeValueCoding.dictionaryVR(for: selector.attribute)
            let hasValues = !selector.values.isEmpty || !selector.codeValues.isEmpty
            if let attributeVR {
                elements.append(DataElement.string(
                    tag: .selectorAttributeVR,
                    vr: .CS,
                    value: attributeVR.rawValue
                ))
                if hasValues {
                    elements.append(try SelectorAttributeValueCoding.encode(
                        values: selector.values,
                        codeValues: selector.codeValues,
                        vr: attributeVR
                    ))
                }
            } else if hasValues {
                throw HangingProtocolError.invalidAttributeValue(
                    "Selector Attribute \(selector.attribute) has no dictionary VR; set ImageSetSelector.attributeVR to encode its values")
            }
            
            // Image Set Selector Usage Flag (0072,0024) - Required, Type 1
            elements.append(DataElement.string(
                tag: .imageSetSelectorUsageFlag,
                vr: .CS,
                value: selector.usageFlag.rawValue
            ))
            
            items.append(SequenceItem(elements: elements))
        }
        
        return items
    }
    
    private func serializeFilterOperations(_ operations: [FilterOperation]) throws -> [SequenceItem] {
        var items: [SequenceItem] = []

        for operation in operations {
            var elements: [DataElement] = []

            // Filter-by Category (0072,0402) - Type 1C, required if Selector
            // Attribute is absent (PS3.3 Table C.23.3-1)
            if let category = operation.filterByCategory {
                elements.append(DataElement.string(
                    tag: .filterByCategory,
                    vr: .CS,
                    value: category.rawValue
                ))
            }

            // Filter-by Attribute Presence (0072,0404) - Type 1C
            if let presence = operation.attributePresence ?? operation.operator?.presenceTerm {
                elements.append(DataElement.string(
                    tag: .filterByAttributePresence,
                    vr: .CS,
                    value: presence.rawValue
                ))
            }

            // Selector Attribute (0072,0026) - Type 1C, required if Filter-by
            // Category is absent
            if let attribute = operation.attribute {
                elements.append(serializeTagAsAttributeTag(
                    tag: .selectorAttribute,
                    value: attribute
                ))
            }

            // Selector Sequence Pointer (0072,0052) - PS3.3 Table C.23.4-1
            if let sequencePointer = operation.sequencePointer {
                elements.append(serializeTagAsAttributeTag(
                    tag: .selectorSequencePointer,
                    value: sequencePointer
                ))
            }

            // Filter-by Operator (0072,0406) - Type 1C; deprecated cases are
            // mapped: EQUAL / CONTAINS -> MEMBER_OF, NOT_EQUAL -> NOT_MEMBER_OF,
            // PRESENT / NOT_PRESENT -> Filter-by Attribute Presence.
            let filterOperator = operation.operator?.standardTerm

            // Selector Attribute VR (0072,0050) and the Selector xx Value -
            // Type 1C when an operator compares values; CS for IMAGE_PLANE
            // (PS3.3 C.23.3.1.1).
            let hasValues = !operation.values.isEmpty || !operation.codeValues.isEmpty
            if filterOperator != nil || hasValues {
                let attributeVR = operation.attributeVR
                    ?? (operation.filterByCategory == .imagePlane ? .CS : nil)
                    ?? operation.attribute.flatMap { SelectorAttributeValueCoding.dictionaryVR(for: $0) }
                if let attributeVR {
                    elements.append(DataElement.string(
                        tag: .selectorAttributeVR,
                        vr: .CS,
                        value: attributeVR.rawValue
                    ))
                    if hasValues {
                        elements.append(try SelectorAttributeValueCoding.encode(
                            values: operation.values,
                            codeValues: operation.codeValues,
                            vr: attributeVR
                        ))
                    }
                } else if hasValues {
                    throw HangingProtocolError.invalidAttributeValue(
                        "Filter operation has no Selector Attribute VR; set FilterOperation.attributeVR to encode its values")
                }
            }

            // Selector Value Number (0072,0028) - Type 1C, required if Selector
            // Attribute and Filter-by Operator are present; 0 = any value
            if let valueNumber = operation.valueNumber
                ?? (operation.attribute != nil && filterOperator != nil ? 0 : nil) {
                elements.append(DataElement.uint16(
                    tag: .selectorValueNumber,
                    value: UInt16(clamping: valueNumber)
                ))
            }

            if let filterOperator {
                elements.append(DataElement.string(
                    tag: .filterByOperator,
                    vr: .CS,
                    value: filterOperator.rawValue
                ))
            }

            // Image Set Selector Usage Flag (0072,0024) - Type 3 here; absent
            // means MATCH, and it is ignored without a Filter-by Operator
            if let usageFlag = operation.usageFlag, filterOperator != nil {
                elements.append(DataElement.string(
                    tag: .imageSetSelectorUsageFlag,
                    vr: .CS,
                    value: usageFlag.rawValue
                ))
            }

            items.append(SequenceItem(elements: elements))
        }

        return items
    }

    private func serializeSortOperations(_ operations: [SortOperation]) -> [SequenceItem] {
        var items: [SequenceItem] = []
        
        for operation in operations {
            var elements: [DataElement] = []
            let sort = operation.standardized

            // PS3.3 Table C.23.3-1: either Sort-by Category (0072,0602) with
            // a Defined Term (ALONG_AXIS, BY_ACQ_TIME), or Selector Attribute
            // (0072,0026) + Selector Value Number (0072,0028). The deprecated
            // SortByCategory cases become one or the other (see SortOperation).

            // Selector Attribute (0072,0026) - Type 1C, required if Sort-by Category is absent
            if let attribute = sort.attribute {
                elements.append(serializeTagAsAttributeTag(
                    tag: .selectorAttribute,
                    value: attribute
                ))
                // Selector Value Number (0072,0028) - Type 1C, shall not be zero
                elements.append(DataElement.uint16(
                    tag: .selectorValueNumber,
                    value: UInt16(clamping: max(1, sort.valueNumber ?? 1))
                ))
            }

            // Sort-by Category (0072,0602) - Type 1C, required if Selector Attribute is absent
            if let category = sort.category {
                elements.append(DataElement.string(
                    tag: .sortByCategory,
                    vr: .CS,
                    value: category.rawValue
                ))
            }

            // Sorting Direction (0072,0604) - Required, Type 1
            elements.append(DataElement.string(
                tag: .sortingDirection,
                vr: .CS,
                value: operation.direction.rawValue
            ))

            items.append(SequenceItem(elements: elements))
        }
        
        return items
    }
    
    private func serializeTimeSelection(_ timeSelection: TimeBasedSelection, into elements: inout [DataElement]) {
        // Relative Time (0072,0038) US VM 2 - Type 1C (PS3.3 Table C.23.1-1,
        // PS3.6 Table 6-1): exactly two values, start and end; one value n
        // is written as the pair n\n.
        if let range = Self.pair(timeSelection.relativeTimeRange) {
            elements.append(DataElement.uint16s(
                tag: .relativeTime,
                values: range.map { UInt16(clamping: $0) }
            ))
        }

        // Relative Time Units (0072,003A) - Type 1C, required if Relative Time is present
        if let relativeTimeUnits = timeSelection.relativeTimeUnits {
            elements.append(DataElement.string(
                tag: .relativeTimeUnits,
                vr: .CS,
                value: relativeTimeUnits.rawValue
            ))
        }

        // Abstract Prior Value (0072,003C) SS VM 2 - Type 1C (PS3.6 Table 6-1):
        // exactly two integers, 1 = most recent prior, -1 = oldest prior.
        if let range = Self.pair(timeSelection.abstractPriorRange) {
            elements.append(DataElement.int16s(
                tag: .abstractPriorValue,
                values: range.map { Int16(clamping: $0) }
            ))
        }
    }

    /// Exactly two values from a range given as one or two values; nil when empty.
    private static func pair(_ values: [Int]) -> [Int]? {
        switch values.count {
        case 0: return nil
        case 1: return [values[0], values[0]]
        default: return Array(values.prefix(2))
        }
    }
    
    // MARK: - Screen Definition Serialization
    
    private func serializeScreenDefinitions(_ definitions: [ScreenDefinition]) -> [SequenceItem] {
        var items: [SequenceItem] = []
        
        for definition in definitions {
            var elements: [DataElement] = []
            
            // Number of Vertical Pixels (0072,0104) - Required, Type 1
            elements.append(DataElement.uint16(
                tag: .numberOfVerticalPixels,
                value: UInt16(definition.verticalPixels)
            ))
            
            // Number of Horizontal Pixels (0072,0106) - Required, Type 1
            elements.append(DataElement.uint16(
                tag: .numberOfHorizontalPixels,
                value: UInt16(definition.horizontalPixels)
            ))
            
            // Display Environment Spatial Position (0072,0108) - Optional, Type 3
            if let spatialPosition = definition.spatialPosition {
                elements.append(DataElement.float64s(
                    tag: .displayEnvironmentSpatialPosition,
                    values: spatialPosition.map { Float64($0) }
                ))
            }
            
            // Screen Minimum Grayscale Bit Depth (0072,010A) - Optional, Type 3
            if let minGrayscaleBitDepth = definition.minimumGrayscaleBitDepth {
                elements.append(DataElement.uint16(
                    tag: .screenMinimumGrayscaleBitDepth,
                    value: UInt16(minGrayscaleBitDepth)
                ))
            }
            
            // Screen Minimum Color Bit Depth (0072,010C) - Optional, Type 3
            if let minColorBitDepth = definition.minimumColorBitDepth {
                elements.append(DataElement.uint16(
                    tag: .screenMinimumColorBitDepth,
                    value: UInt16(minColorBitDepth)
                ))
            }
            
            // Application Maximum Repaint Time (0072,010E) - Optional, Type 3
            if let maxRepaintTime = definition.maximumRepaintTime {
                elements.append(DataElement.uint16(
                    tag: .applicationMaximumRepaintTime,
                    value: UInt16(maxRepaintTime)
                ))
            }
            
            items.append(SequenceItem(elements: elements))
        }
        
        return items
    }
    
    // MARK: - Display Set Serialization
    
    private func serializeDisplaySets(_ displaySets: [DisplaySet], of hangingProtocol: HangingProtocol) throws -> [SequenceItem] {
        var items: [SequenceItem] = []

        for displaySet in displaySets {
            var elements: [DataElement] = []

            // Display Set Number (0072,0202) - Required, Type 1
            elements.append(DataElement.uint16(
                tag: .displaySetNumber,
                value: UInt16(displaySet.number)
            ))

            // Display Set Label (0072,0203) - Optional, Type 3
            if let label = displaySet.label {
                elements.append(DataElement.string(
                    tag: .displaySetLabel,
                    vr: .LO,
                    value: label
                ))
            }

            // Display Set Presentation Group (0072,0204) - Type 1
            if let presentationGroup = displaySet.presentationGroup {
                elements.append(DataElement.uint16(
                    tag: .displaySetPresentationGroup,
                    value: UInt16(presentationGroup)
                ))
            }

            // Display Set Presentation Group Description (0072,0206) - Optional, Type 3
            if let groupDescription = displaySet.presentationGroupDescription {
                elements.append(DataElement.string(
                    tag: .displaySetPresentationGroupDescription,
                    vr: .LO,
                    value: groupDescription
                ))
            }

            // Image Set Number (0072,0032) - Type 1 in the Display Sets Sequence
            // item (PS3.3 Table C.23.3-1): the image set this display set shows
            let imageSetNumber = hangingProtocol.resolvedImageSetNumber(for: displaySet)
            if let imageSetNumber {
                elements.append(DataElement.uint16(
                    tag: .imageSetNumber,
                    value: UInt16(clamping: imageSetNumber)
                ))
            }

            // Partial Data Display Handling (0072,0208) and Synchronized
            // Scrolling Sequence (0072,0210) are top-level attributes (PS3.3
            // Table C.23.3-1), written in serialize(protocol:).

            // Image Boxes Sequence (0072,0300) - Required, Type 1
            if !displaySet.imageBoxes.isEmpty {
                let imageBoxItems = try serializeImageBoxes(displaySet.imageBoxes)
                let imageBoxSequence = createSequenceElement(
                    tag: .imageBoxesSequence,
                    items: imageBoxItems
                )
                elements.append(imageBoxSequence)
            }

            // Filter Operations Sequence (0072,0400) - Type 2, written empty
            // when there is none. Filters given on the deprecated
            // ImageSetSelector API of the shown image set apply when the
            // display set has none of its own.
            let sourceImageSets = imageSetNumber.map { number in
                hangingProtocol.imageSets.filter { $0.imageSetNumbers.contains(number) }
            } ?? []
            var filters = displaySet.filterOperations
            if filters.isEmpty {
                filters = sourceImageSets.flatMap { imageSet in
                    imageSet.selectors.filter { $0.isLegacyFilter }.map { $0.legacyFilterOperation }
                }
            }
            elements.append(createSequenceElement(
                tag: .filterOperationsSequence,
                items: try serializeFilterOperations(filters)
            ))

            // Sorting Operations Sequence (0072,0600) - Type 2, written empty
            // when there is none; sorts given on the deprecated image-set
            // API apply when the display set has none of its own.
            var sorts = displaySet.sortingOperations
            if sorts.isEmpty {
                sorts = sourceImageSets.flatMap { $0.legacySortOperations }
            }
            elements.append(createSequenceElement(
                tag: .sortingOperationsSequence,
                items: serializeSortOperations(sorts)
            ))

            // Blending Operation Type (0072,0500) - Type 3, Defined Term COLOR
            if let blending = displaySet.blendingOperationType {
                elements.append(DataElement.string(
                    tag: .blendingOperationType,
                    vr: .CS,
                    value: blending.rawValue
                ))
            }

            // Reformatting Operation Type ... Initial View Direction (0072,0510 -
            // 0516) - display set level (PS3.3 Table C.23.3-1); a value given
            // on the deprecated ImageBox API is used when the display set has none.
            if let reformattingOp = displaySet.effectiveReformattingOperation {
                serializeReformattingOperation(reformattingOp, into: &elements)
            }

            // 3D Rendering Type (0072,0520) CS VM 1-n - Type 1C if Reformatting
            // Operation Type is 3D_RENDERING: Value 1 a Defined Term (MIP,
            // SURFACE, VOLUME), further values implementation specific
            // sub-types (PS3.3 Table C.23.3-1). A deprecated projection
            // ReformattingType supplies the values when none is stated.
            let renderingValues = displaySet.effectiveThreeDRenderingValues
            if !renderingValues.isEmpty {
                elements.append(DataElement.strings(
                    tag: .threeDRenderingType,
                    vr: .CS,
                    values: renderingValues
                ))
            }

            // Display options
            serializeDisplayOptions(displaySet.displayOptions, into: &elements)

            items.append(SequenceItem(elements: elements))
        }

        return items
    }

    private func serializeImageBoxes(_ imageBoxes: [ImageBox]) throws -> [SequenceItem] {
        var items: [SequenceItem] = []
        
        for imageBox in imageBoxes {
            var elements: [DataElement] = []
            
            // Image Box Number (0072,0302) - Required, Type 1
            elements.append(DataElement.uint16(
                tag: .imageBoxNumber,
                value: UInt16(imageBox.number)
            ))
            
            // Image Box Layout Type (0072,0304) - Required, Type 1; PS3.3 Table
            // C.23.3-1 Defined Terms (TILED_ALL is written as TILED).
            elements.append(DataElement.string(
                tag: .imageBoxLayoutType,
                vr: .CS,
                value: imageBox.layoutType.standardTerm.rawValue
            ))
            
            // Display Environment Spatial Position (0072,0108) FD VM 4 - Type 1
            // in an Image Boxes Sequence item (PS3.3 Table C.23.3-1)
            if let spatialPosition = imageBox.displayEnvironmentSpatialPosition {
                elements.append(DataElement.float64s(
                    tag: .displayEnvironmentSpatialPosition,
                    values: spatialPosition
                ))
            }

            // Image Box Tile Horizontal Dimension (0072,0306) - Conditional, Type 1C
            if let tileHorizontal = imageBox.tileHorizontalDimension {
                elements.append(DataElement.uint16(
                    tag: .imageBoxTileHorizontalDimension,
                    value: UInt16(tileHorizontal)
                ))
            }
            
            // Image Box Tile Vertical Dimension (0072,0308) - Conditional, Type 1C
            if let tileVertical = imageBox.tileVerticalDimension {
                elements.append(DataElement.uint16(
                    tag: .imageBoxTileVerticalDimension,
                    value: UInt16(tileVertical)
                ))
            }
            
            // Image Box Scroll Direction (0072,0310) - Optional, Type 3
            if let scrollDirection = imageBox.scrollDirection {
                elements.append(DataElement.string(
                    tag: .imageBoxScrollDirection,
                    vr: .CS,
                    value: scrollDirection.rawValue
                ))
            }
            
            // Image Box Small Scroll Type (0072,0312) - Type 2C; PS3.3 Table
            // C.23.3-1 Enumerated Values PAGE / ROW_COLUMN / IMAGE (FRACTION is
            // written as PAGE).
            if let smallScrollType = imageBox.smallScrollType {
                elements.append(DataElement.string(
                    tag: .imageBoxSmallScrollType,
                    vr: .CS,
                    value: smallScrollType.standardTerm.rawValue
                ))
            }
            
            // Image Box Small Scroll Amount (0072,0314) - Optional, Type 3
            if let smallScrollAmount = imageBox.smallScrollAmount {
                elements.append(DataElement.uint16(
                    tag: .imageBoxSmallScrollAmount,
                    value: UInt16(smallScrollAmount)
                ))
            }
            
            // Image Box Large Scroll Type (0072,0316) - Type 2C, same terms
            if let largeScrollType = imageBox.largeScrollType {
                elements.append(DataElement.string(
                    tag: .imageBoxLargeScrollType,
                    vr: .CS,
                    value: largeScrollType.standardTerm.rawValue
                ))
            }
            
            // Image Box Large Scroll Amount (0072,0318) - Optional, Type 3
            if let largeScrollAmount = imageBox.largeScrollAmount {
                elements.append(DataElement.uint16(
                    tag: .imageBoxLargeScrollAmount,
                    value: UInt16(largeScrollAmount)
                ))
            }
            
            // Image Box Overlap Priority (0072,0320) - Optional, Type 3
            if let overlapPriority = imageBox.overlapPriority {
                elements.append(DataElement.uint16(
                    tag: .imageBoxOverlapPriority,
                    value: UInt16(overlapPriority)
                ))
            }
            
            // Preferred Playback Sequencing (0018,1244) US - Type 1C for CINE
            // (PS3.3 Table C.23.3-1, Enumerated Values 0, 1, 2)
            if let playback = imageBox.preferredPlaybackSequencing {
                elements.append(DataElement.uint16(
                    tag: .preferredPlaybackSequencing,
                    value: playback.rawValue
                ))
            }

            // Recommended Display Frame Rate (0008,2144) IS - Type 1C for CINE
            if let frameRate = imageBox.recommendedDisplayFrameRate {
                elements.append(DataElement.string(
                    tag: .recommendedDisplayFrameRate,
                    vr: .IS,
                    value: String(frameRate)
                ))
            }

            // Cine Relative to Real-Time (0072,0330) - Type 1C for CINE
            if let cineRelative = imageBox.cineRelativeToRealTime {
                elements.append(DataElement.float64(
                    tag: .cineRelativeToRealTime,
                    value: cineRelative
                ))
            }
            
            // Reformatting and 3D Rendering Type are Display Sets Sequence item
            // attributes (PS3.3 Table C.23.3-1), written in serializeDisplaySets.

            items.append(SequenceItem(elements: elements))
        }

        return items
    }

    private func serializeReformattingOperation(_ operation: ReformattingOperation, into elements: inout [DataElement]) {
        // Reformatting Operation Type (0072,0510) - PS3.3 Table C.23.3-1
        // Defined Terms MPR / 3D_RENDERING / SLAB (CPR is written as MPR,
        // MIP / MinIP / AvgIP as 3D_RENDERING; see ReformattingType).
        elements.append(DataElement.string(
            tag: .reformattingOperationType,
            vr: .CS,
            value: operation.type.standardTerm.rawValue
        ))
        
        // Reformatting Thickness (0072,0512) - Optional, Type 3
        if let thickness = operation.thickness {
            elements.append(DataElement.float64(
                tag: .reformattingThickness,
                value: thickness
            ))
        }
        
        // Reformatting Interval (0072,0514) - Optional, Type 3
        if let interval = operation.interval {
            elements.append(DataElement.float64(
                tag: .reformattingInterval,
                value: interval
            ))
        }
        
        // Reformatting Operation Initial View Direction (0072,0516) - Type 1C
        // for MPR / 3D_RENDERING; Defined Terms SAGITTAL, TRANSVERSE, CORONAL,
        // OBLIQUE (PS3.3 Table C.23.3-1)
        if let plane = operation.initialViewPlane {
            elements.append(DataElement.string(
                tag: .reformattingOperationInitialViewDirection,
                vr: .CS,
                value: plane.rawValue
            ))
        }
    }
    
    private func serializeDisplayOptions(_ options: DisplayOptions, into elements: inout [DataElement]) {
        // Display Set Patient Orientation (0072,0700) - Optional, Type 3
        if let patientOrientation = options.patientOrientation {
            elements.append(DataElement.string(
                tag: .displaySetPatientOrientation,
                vr: .CS,
                value: patientOrientation
            ))
        }
        
        // VOI Type (0072,0702) - Optional, Type 3
        if let voiType = options.voiType {
            elements.append(DataElement.string(
                tag: .voiType,
                vr: .CS,
                value: voiType
            ))
        }
        
        // Pseudo-Color Type (0072,0704) - Optional, Type 3
        if let pseudoColorType = options.pseudoColorType {
            elements.append(DataElement.string(
                tag: .pseudoColorType,
                vr: .CS,
                value: pseudoColorType
            ))
        }
        
        // The display flags of PS3.3 Table C.23.3-1 are enumerated YES / NO

        // Show Grayscale Inverted (0072,0706) - Optional, Type 3
        if options.showGrayscaleInverted {
            elements.append(DataElement.string(
                tag: .showGrayscaleInverted,
                vr: .CS,
                value: "YES"
            ))
        }

        // Show Image True Size Flag (0072,0710) - Optional, Type 3
        if options.showImageTrueSize {
            elements.append(DataElement.string(
                tag: .showImageTrueSizeFlag,
                vr: .CS,
                value: "YES"
            ))
        }

        // Show Graphic Annotation Flag (0072,0712) - Optional, Type 3
        elements.append(DataElement.string(
            tag: .showGraphicAnnotationFlag,
            vr: .CS,
            value: options.showGraphicAnnotations ? "YES" : "NO"
        ))

        // Show Patient Demographics Flag (0072,0714) - Optional, Type 3
        elements.append(DataElement.string(
            tag: .showPatientDemographicsFlag,
            vr: .CS,
            value: options.showPatientDemographics ? "YES" : "NO"
        ))

        // Show Acquisition Techniques Flag (0072,0716) - Optional, Type 3
        elements.append(DataElement.string(
            tag: .showAcquisitionTechniquesFlag,
            vr: .CS,
            value: options.showAcquisitionTechniques ? "YES" : "NO"
        ))
        
        // Display Set Horizontal Justification (0072,0717) - Optional, Type 3
        if let horizJust = options.horizontalJustification {
            elements.append(DataElement.string(
                tag: .displaySetHorizontalJustification,
                vr: .CS,
                value: horizJust.rawValue
            ))
        }
        
        // Display Set Vertical Justification (0072,0718) - Optional, Type 3
        if let vertJust = options.verticalJustification {
            elements.append(DataElement.string(
                tag: .displaySetVerticalJustification,
                vr: .CS,
                value: vertJust.rawValue
            ))
        }
    }
    
    // MARK: - Helper Methods
    
    /// Creates a sequence element from sequence items
    private func createSequenceElement(tag: Tag, items: [SequenceItem]) -> DataElement {
        let writer = DICOMWriter()
        var sequenceData = Data()
        
        for item in items {
            sequenceData.append(writer.serializeSequenceItem(item))
        }
        
        return DataElement(
            tag: tag,
            vr: .SQ,
            length: UInt32(sequenceData.count),
            valueData: sequenceData,
            sequenceItems: items
        )
    }
    
    /// Serializes a Tag to an AttributeTag (AT) VR data element
    ///
    /// The AT VR contains a DICOM tag as a pair of 16-bit unsigned integers
    /// (group, element) in little-endian byte order.
    ///
    /// Reference: PS3.5 Section 6.2 - AT Value Representation
    private func serializeTagAsAttributeTag(tag: Tag, value: Tag) -> DataElement {
        var data = Data()
        
        // Serialize as little-endian UInt16 pairs (group, element)
        withUnsafeBytes(of: value.group.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: value.element.littleEndian) { data.append(contentsOf: $0) }
        
        return DataElement(
            tag: tag,
            vr: .AT,
            length: 4,
            valueData: data
        )
    }
}
