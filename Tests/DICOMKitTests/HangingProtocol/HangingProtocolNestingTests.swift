//
// HangingProtocolNestingTests.swift
// DICOMKit
//
// Pins where every Hanging Protocol attribute sits (D32): which sequence item
// holds it, per PS3.3 2026a Tables C.23.1-1, C.23.2-1 and C.23.3-1.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class HangingProtocolNestingTests: XCTestCase {

    /// (parent sequence, attribute, Type) for every attribute of PS3.3 2026a
    /// Tables C.23.1-1, C.23.2-1 and C.23.3-1, with the macros C.23.4-1,
    /// C.23.4-2 and C.23.2-2 expanded. "top" is the top level of the dataset.
    /// Generated from the 2026a DocBook with Scripts/nema_docbook.py (table
    /// dump, ">" nesting); Code Sequence Macro (8.8-1) and SOP Instance
    /// Reference Macro (10-11) contents are not listed.
    static let standardNesting: [(parent: String, tag: String, type: String)] = [
        ("top", "00720002", "1"),  // Hanging Protocol Name
        ("top", "00720004", "1"),  // Hanging Protocol Description
        ("top", "00720006", "1"),  // Hanging Protocol Level
        ("top", "00720008", "1"),  // Hanging Protocol Creator
        ("top", "0072000A", "1"),  // Hanging Protocol Creation DateTime
        ("top", "0072000C", "1"),  // Hanging Protocol Definition Sequence
        ("0072000C", "00080060", "1C"),  // Modality
        ("0072000C", "00082218", "1C"),  // Anatomic Region Sequence
        ("0072000C", "00200060", "2C"),  // Laterality
        ("0072000C", "00081032", "2"),  // Procedure Code Sequence
        ("0072000C", "0040100A", "2"),  // Reason for Requested Procedure Code Sequence
        ("top", "00720014", "1"),  // Number of Priors Referenced
        ("top", "00720020", "1"),  // Image Sets Sequence
        ("00720020", "00720022", "1"),  // Image Set Selector Sequence
        ("00720022", "00720024", "1"),  // Image Set Selector Usage Flag
        ("00720022", "00720026", "1"),  // Selector Attribute
        ("00720022", "00720050", "1"),  // Selector Attribute VR
        ("00720022", "00720052", "1C"),  // Selector Sequence Pointer
        ("00720022", "00209167", "1C"),  // Functional Group Pointer
        ("00720022", "00720054", "1C"),  // Selector Sequence Pointer Private Creator
        ("00720022", "00209238", "1C"),  // Functional Group Private Creator
        ("00720022", "00720056", "1C"),  // Selector Attribute Private Creator
        ("00720022", "00720060", "1C"),  // Selector AT Value
        ("00720022", "00720062", "1C"),  // Selector CS Value
        ("00720022", "00720064", "1C"),  // Selector IS Value
        ("00720022", "00720066", "1C"),  // Selector LO Value
        ("00720022", "00720068", "1C"),  // Selector LT Value
        ("00720022", "0072006A", "1C"),  // Selector PN Value
        ("00720022", "0072006C", "1C"),  // Selector SH Value
        ("00720022", "0072006E", "1C"),  // Selector ST Value
        ("00720022", "00720070", "1C"),  // Selector UT Value
        ("00720022", "00720072", "1C"),  // Selector DS Value
        ("00720022", "00720074", "1C"),  // Selector FD Value
        ("00720022", "00720076", "1C"),  // Selector FL Value
        ("00720022", "00720078", "1C"),  // Selector UL Value
        ("00720022", "0072007A", "1C"),  // Selector US Value
        ("00720022", "0072007C", "1C"),  // Selector SL Value
        ("00720022", "0072007E", "1C"),  // Selector SS Value
        ("00720022", "00720080", "1C"),  // Selector Code Sequence Value
        ("00720022", "0072007F", "1C"),  // Selector UI Value
        ("00720022", "00720028", "1"),  // Selector Value Number
        ("00720020", "00720030", "1"),  // Time Based Image Sets Sequence
        ("00720030", "00720032", "1"),  // Image Set Number
        ("00720030", "00720034", "1"),  // Image Set Selector Category
        ("00720030", "00720038", "1C"),  // Relative Time
        ("00720030", "0072003A", "1C"),  // Relative Time Units
        ("00720030", "0072003C", "1C"),  // Abstract Prior Value
        ("00720030", "0072003E", "1C"),  // Abstract Prior Code Sequence
        ("00720030", "00720040", "3"),  // Image Set Label
        ("top", "0072000E", "2"),  // Hanging Protocol User Identification Code Sequence
        ("top", "00720010", "3"),  // Hanging Protocol User Group Name
        ("top", "00720012", "3"),  // Source Hanging Protocol Sequence
        ("top", "00720100", "2"),  // Number of Screens
        ("top", "00720102", "2"),  // Nominal Screen Definition Sequence
        ("00720102", "00720104", "1"),  // Number of Vertical Pixels
        ("00720102", "00720106", "1"),  // Number of Horizontal Pixels
        ("00720102", "00720108", "1"),  // Display Environment Spatial Position
        ("00720102", "0072010A", "1C"),  // Screen Minimum Grayscale Bit Depth
        ("00720102", "0072010C", "1C"),  // Screen Minimum Color Bit Depth
        ("00720102", "0072010E", "3"),  // Application Maximum Repaint Time
        ("top", "00720200", "1"),  // Display Sets Sequence
        ("00720200", "00720202", "1"),  // Display Set Number
        ("00720200", "00720203", "3"),  // Display Set Label
        ("00720200", "00720204", "1"),  // Display Set Presentation Group
        ("00720200", "00720032", "1"),  // Image Set Number
        ("00720200", "00720300", "1"),  // Image Boxes Sequence
        ("00720300", "00720302", "1"),  // Image Box Number
        ("00720300", "00720108", "1"),  // Display Environment Spatial Position
        ("00720300", "00720304", "1"),  // Image Box Layout Type
        ("00720300", "00720306", "1C"),  // Image Box Tile Horizontal Dimension
        ("00720300", "00720308", "1C"),  // Image Box Tile Vertical Dimension
        ("00720300", "00720310", "1C"),  // Image Box Scroll Direction
        ("00720300", "00720312", "2C"),  // Image Box Small Scroll Type
        ("00720300", "00720314", "1C"),  // Image Box Small Scroll Amount
        ("00720300", "00720316", "2C"),  // Image Box Large Scroll Type
        ("00720300", "00720318", "1C"),  // Image Box Large Scroll Amount
        ("00720300", "00720320", "3"),  // Image Box Overlap Priority
        ("00720300", "00181244", "1C"),  // Preferred Playback Sequencing
        ("00720300", "00082144", "1C"),  // Recommended Display Frame Rate
        ("00720300", "00720330", "1C"),  // Cine Relative to Real-Time
        ("00720200", "00720400", "2"),  // Filter Operations Sequence
        ("00720400", "00720402", "1C"),  // Filter-by Category
        ("00720400", "00720404", "1C"),  // Filter-by Attribute Presence
        ("00720400", "00720026", "1C"),  // Selector Attribute
        ("00720400", "00720050", "1C"),  // Selector Attribute VR
        ("00720400", "00720052", "1C"),  // Selector Sequence Pointer
        ("00720400", "00209167", "1C"),  // Functional Group Pointer
        ("00720400", "00720054", "1C"),  // Selector Sequence Pointer Private Creator
        ("00720400", "00209238", "1C"),  // Functional Group Private Creator
        ("00720400", "00720056", "1C"),  // Selector Attribute Private Creator
        ("00720400", "00720060", "1C"),  // Selector AT Value
        ("00720400", "00720062", "1C"),  // Selector CS Value
        ("00720400", "00720064", "1C"),  // Selector IS Value
        ("00720400", "00720066", "1C"),  // Selector LO Value
        ("00720400", "00720068", "1C"),  // Selector LT Value
        ("00720400", "0072006A", "1C"),  // Selector PN Value
        ("00720400", "0072006C", "1C"),  // Selector SH Value
        ("00720400", "0072006E", "1C"),  // Selector ST Value
        ("00720400", "00720070", "1C"),  // Selector UT Value
        ("00720400", "00720072", "1C"),  // Selector DS Value
        ("00720400", "00720074", "1C"),  // Selector FD Value
        ("00720400", "00720076", "1C"),  // Selector FL Value
        ("00720400", "00720078", "1C"),  // Selector UL Value
        ("00720400", "0072007A", "1C"),  // Selector US Value
        ("00720400", "0072007C", "1C"),  // Selector SL Value
        ("00720400", "0072007E", "1C"),  // Selector SS Value
        ("00720400", "00720080", "1C"),  // Selector Code Sequence Value
        ("00720400", "0072007F", "1C"),  // Selector UI Value
        ("00720400", "00720028", "1C"),  // Selector Value Number
        ("00720400", "00720406", "1C"),  // Filter-by Operator
        ("00720400", "00720024", "3"),  // Image Set Selector Usage Flag
        ("00720200", "00720600", "2"),  // Sorting Operations Sequence
        ("00720600", "00720026", "1C"),  // Selector Attribute
        ("00720600", "00720052", "1C"),  // Selector Sequence Pointer
        ("00720600", "00209167", "1C"),  // Functional Group Pointer
        ("00720600", "00720054", "1C"),  // Selector Sequence Pointer Private Creator
        ("00720600", "00209238", "1C"),  // Functional Group Private Creator
        ("00720600", "00720056", "1C"),  // Selector Attribute Private Creator
        ("00720600", "00720028", "1C"),  // Selector Value Number
        ("00720600", "00720602", "1C"),  // Sort-by Category
        ("00720600", "00720604", "1"),  // Sorting Direction
        ("00720200", "00720500", "3"),  // Blending Operation Type
        ("00720200", "00720510", "3"),  // Reformatting Operation Type
        ("00720200", "00720512", "1C"),  // Reformatting Thickness
        ("00720200", "00720514", "1C"),  // Reformatting Interval
        ("00720200", "00720516", "1C"),  // Reformatting Operation Initial View Direction
        ("00720200", "00720520", "1C"),  // 3D Rendering Type
        ("00720200", "00720700", "3"),  // Display Set Patient Orientation
        ("00720200", "00720717", "3"),  // Display Set Horizontal Justification
        ("00720200", "00720718", "3"),  // Display Set Vertical Justification
        ("00720200", "00720702", "3"),  // VOI Type
        ("00720200", "00720704", "3"),  // Pseudo-Color Type
        ("00720200", "00720705", "1C"),  // Pseudo-Color Palette Instance Reference Sequence
        ("00720200", "00720706", "3"),  // Show Grayscale Inverted
        ("00720200", "00720710", "3"),  // Show Image True Size Flag
        ("00720200", "00720712", "3"),  // Show Graphic Annotation Flag
        ("00720200", "00720714", "3"),  // Show Patient Demographics Flag
        ("00720200", "00720716", "3"),  // Show Acquisition Techniques Flag
        ("00720200", "00720206", "3"),  // Display Set Presentation Group Description
        ("top", "00720208", "2"),  // Partial Data Display Handling
        ("top", "00720210", "3"),  // Synchronized Scrolling Sequence
        ("00720210", "00720212", "1"),  // Display Set Scrolling Group
        ("top", "00720214", "3"),  // Navigation Indicator Sequence
        ("00720214", "00720216", "1C"),  // Navigation Display Set
        ("00720214", "00720218", "1"),  // Reference Display Sets
    ]

    private static func hex(_ tag: Tag) -> String {
        String(format: "%04X%04X", tag.group, tag.element)
    }

    /// Sequences whose items are Code Sequence Macro / SOP reference items,
    /// outside these tables.
    private static let opaqueSequences: Set<String> = [
        "00082218", "00081032", "0040100A", "0072000E", "00720012", "0072003E", "00720080",
    ]

    /// Every (parent, attribute) pair in the serialized dataset.
    private static func placements(_ dataSet: DataSet) -> [(parent: String, tag: String)] {
        var result: [(String, String)] = []
        func walk(_ elements: [DataElement], parent: String) {
            for element in elements {
                let key = hex(element.tag)
                result.append((parent, key))
                if element.vr == .SQ, !opaqueSequences.contains(key) {
                    for item in element.sequenceItems ?? [] {
                        walk(Array(item.elements.values), parent: key)
                    }
                }
            }
        }
        walk(dataSet.allElements, parent: "top")
        return result
    }

    /// A protocol that uses every modelled attribute of the three tables.
    static func fullProtocol() -> HangingProtocol {
        let priorCode = CodedConcept(codeValue: "PRIOR1", codingSchemeDesignator: "99DICOMKIT", codeMeaning: "Test prior")
        return HangingProtocol(
            name: "Nesting",
            description: "Every modelled attribute",
            level: .site,
            creator: "DICOMKit",
            creationDateTime: DICOMDateTime(year: 2026, month: 9, day: 29),
            numberOfPriorsReferenced: 2,
            environments: [HangingProtocolEnvironment(modality: "CT", laterality: "L")],
            userGroups: ["Radiology"],
            imageSets: [ImageSetDefinition(
                selectors: [ImageSetSelector(attribute: .modality, valueNumber: 1, values: ["CT"], usageFlag: .noMatch)],
                timeBasedImageSets: [
                    TimeBasedImageSet(number: 1, category: .relativeTime,
                                      timeSelection: TimeBasedSelection(relativeTimeRange: [0, 0], relativeTimeUnits: .days),
                                      label: "Current"),
                    TimeBasedImageSet(number: 2, category: .abstractPrior,
                                      timeSelection: TimeBasedSelection(abstractPriorRange: [1, 1]), label: "Prior"),
                    TimeBasedImageSet(number: 3, category: .abstractPrior, abstractPriorCode: priorCode),
                ]
            )],
            numberOfScreens: 1,
            screenDefinitions: [ScreenDefinition(verticalPixels: 1080, horizontalPixels: 1920, spatialPosition: [0, 1, 1, 0],
                                                 minimumGrayscaleBitDepth: 8, minimumColorBitDepth: 8, maximumRepaintTime: 100)],
            displaySets: [
                DisplaySet(
                    number: 1, label: "Axial", presentationGroup: 1, presentationGroupDescription: "Initial",
                    imageSetNumber: 1,
                    imageBoxes: [ImageBox(number: 1, layoutType: .cine, displayEnvironmentSpatialPosition: [0, 1, 0.5, 0],
                                          overlapPriority: 1, preferredPlaybackSequencing: .sweeping,
                                          recommendedDisplayFrameRate: 30, cineRelativeToRealTime: 1.0)],
                    filterOperations: [
                        FilterOperation(attribute: .sliceLocation, valueNumber: 1, operator: .greaterThan, values: ["0"], usageFlag: .noMatch),
                        FilterOperation(filterByCategory: .imagePlane, operator: .memberOf, values: ["TRANSVERSE"]),
                        FilterOperation(attribute: .sliceThickness, attributePresence: .present),
                    ],
                    sortingOperations: [
                        SortOperation(sortByCategory: .alongAxis, direction: .ascending),
                        SortOperation(attribute: .instanceNumber, valueNumber: 1, direction: .descending),
                    ],
                    blendingOperationType: .color,
                    reformattingOperation: ReformattingOperation(type: .threeDRendering, thickness: 2, interval: 1, initialViewPlane: .transverse),
                    threeDRenderingType: .mip,
                    threeDRenderingSubtypes: ["SHADED"],
                    displayOptions: DisplayOptions(patientOrientation: "L\\P", voiType: "LUNG", pseudoColorType: "HOT_IRON",
                                                   showGrayscaleInverted: true, showImageTrueSize: true,
                                                   horizontalJustification: .left, verticalJustification: .top)
                ),
                DisplaySet(
                    number: 2, presentationGroup: 1, imageSetNumber: 2,
                    imageBoxes: [ImageBox(number: 1, layoutType: .tiled, displayEnvironmentSpatialPosition: [0.5, 1, 1, 0],
                                          tileHorizontalDimension: 2, tileVerticalDimension: 2, scrollDirection: .vertical,
                                          smallScrollType: .image, smallScrollAmount: 1, largeScrollType: .page, largeScrollAmount: 1)]
                ),
            ],
            partialDataDisplayHandling: .maintainLayout,
            synchronizedScrolling: [SynchronizedScrollingGroup(displaySetNumbers: [1, 2])],
            navigationIndicators: [NavigationIndicator(navigationDisplaySet: 1, referenceDisplaySets: [2])]
        )
    }

    // MARK: - Serialize: every element sits in its PS3.3 sequence item

    func test_standardNesting_isTheTwentySixA_tables() {
        // Spot checks that the generated table carries the D32 placements.
        let pairs = Set(Self.standardNesting.map { "\($0.parent)/\($0.tag)" })
        for expected in ["00720030/00720032", "00720030/00720034", "00720030/00720038", "00720030/0072003C",
                         "00720030/0072003E", "00720030/00720040", "00720200/00720032", "00720200/00720400",
                         "00720200/00720600", "00720200/00720500", "00720200/00720510", "00720200/00720520",
                         "00720210/00720212", "top/00720210", "top/00720214", "00720214/00720216",
                         "00720214/00720218", "00720300/00181244", "00720300/00082144", "00720300/00720108",
                         "00720400/00720402", "00720400/00720404", "00720400/00720406", "00720600/00720602"] {
            XCTAssertTrue(pairs.contains(expected), expected)
        }
        for absent in ["00720020/00720032", "00720022/00720406", "00720022/00720402", "00720022/00720404",
                       "00720020/00720600", "00720300/00720510", "00720300/00720520", "00720200/00720212"] {
            XCTAssertFalse(pairs.contains(absent), absent)
        }
    }

    func test_serialize_everyElementIsInItsTableSequence() throws {
        let dataSet = try HangingProtocolSerializer().serialize(protocol: Self.fullProtocol())
        let allowed = Set(Self.standardNesting.map { "\($0.parent)/\($0.tag)" })
        let placed = Self.placements(dataSet)
        XCTAssertGreaterThan(placed.count, 80)
        for (parent, tag) in placed {
            XCTAssertTrue(allowed.contains("\(parent)/\(tag)"),
                          "(\(tag)) written in \(parent == "top" ? "the top level" : "a (\(parent)) item"), which PS3.3 2026a does not allow")
        }
    }

    func test_serialize_everyModelledAttributeIsWritten() throws {
        let placed = Set(Self.placements(try HangingProtocolSerializer().serialize(protocol: Self.fullProtocol()))
            .map { "\($0.parent)/\($0.tag)" })
        let expected = [
            // Time Based Image Sets Sequence items (Table C.23.1-1)
            "00720020/00720022", "00720020/00720030",
            "00720030/00720032", "00720030/00720034", "00720030/00720038", "00720030/0072003A",
            "00720030/0072003C", "00720030/0072003E", "00720030/00720040",
            // Image Set Selector Sequence items
            "00720022/00720024", "00720022/00720026", "00720022/00720050", "00720022/00720028", "00720022/00720062",
            // Environment module (Table C.23.2-1 / C.23.2-2)
            "top/00720100", "top/00720102", "00720102/00720104", "00720102/00720106", "00720102/00720108",
            // Display Sets Sequence items (Table C.23.3-1)
            "00720200/00720202", "00720200/00720203", "00720200/00720204", "00720200/00720206", "00720200/00720032",
            "00720200/00720300", "00720200/00720400", "00720200/00720600", "00720200/00720500", "00720200/00720510",
            "00720200/00720512", "00720200/00720514", "00720200/00720516", "00720200/00720520",
            "00720200/00720700", "00720200/00720702", "00720200/00720704", "00720200/00720706", "00720200/00720710",
            "00720200/00720712", "00720200/00720714", "00720200/00720716", "00720200/00720717", "00720200/00720718",
            // Image Boxes Sequence items
            "00720300/00720302", "00720300/00720108", "00720300/00720304", "00720300/00720306", "00720300/00720308",
            "00720300/00720310", "00720300/00720312", "00720300/00720314", "00720300/00720316", "00720300/00720318",
            "00720300/00720320", "00720300/00181244", "00720300/00082144", "00720300/00720330",
            // Filter Operations Sequence items
            "00720400/00720402", "00720400/00720404", "00720400/00720026", "00720400/00720050", "00720400/00720028",
            "00720400/00720406", "00720400/00720024", "00720400/00720072", "00720400/00720062",
            // Sorting Operations Sequence items
            "00720600/00720026", "00720600/00720028", "00720600/00720602", "00720600/00720604",
            // Top level of the Display module
            "top/00720208", "top/00720210", "00720210/00720212", "top/00720214", "00720214/00720216", "00720214/00720218",
        ]
        for pair in expected {
            XCTAssertTrue(placed.contains(pair), "\(pair) not written")
        }
    }

    func test_serialize_valuesInTheirItems() throws {
        let dataSet = try HangingProtocolSerializer().serialize(protocol: Self.fullProtocol())

        let imageSet = try XCTUnwrap(dataSet.sequence(for: .imageSetsSequence)?.first)
        let timeItems = try XCTUnwrap(imageSet[.timeBasedImageSetsSequence]?.sequenceItems)
        XCTAssertEqual(timeItems.map { $0[.imageSetNumber]?.uint16Value }, [1, 2, 3])
        XCTAssertEqual(timeItems.map { $0.string(for: .imageSetSelectorCategory) }, ["RELATIVE_TIME", "ABSTRACT_PRIOR", "ABSTRACT_PRIOR"])
        XCTAssertEqual(timeItems[0][.relativeTime]?.uint16Values, [0, 0])
        XCTAssertEqual(timeItems[1][.abstractPriorValue]?.int16Values, [1, 1])
        XCTAssertEqual(timeItems[2][.abstractPriorCodeSequence]?.sequenceItems?.count, 1, "a single item")
        XCTAssertEqual(timeItems[2][.abstractPriorCodeSequence]?.sequenceItems?.first?.string(for: .codeValue), "PRIOR1")

        let displaySets = try XCTUnwrap(dataSet.sequence(for: .displaySetsSequence))
        XCTAssertEqual(displaySets.map { $0[.imageSetNumber]?.uint16Value }, [1, 2])
        XCTAssertEqual(displaySets[0][.filterOperationsSequence]?.sequenceItems?.count, 3)
        XCTAssertEqual(displaySets[0][.sortingOperationsSequence]?.sequenceItems?.count, 2)
        XCTAssertEqual(displaySets[0].string(for: .blendingOperationType), "COLOR")
        XCTAssertEqual(displaySets[0][.threeDRenderingType]?.stringValues, ["MIP", "SHADED"])
        // Type 2: present and empty when the display set has none
        XCTAssertNotNil(displaySets[1][.filterOperationsSequence])
        XCTAssertEqual(displaySets[1][.filterOperationsSequence]?.sequenceItems?.count ?? 0, 0)
        XCTAssertNotNil(displaySets[1][.sortingOperationsSequence])
        XCTAssertEqual(displaySets[1][.sortingOperationsSequence]?.sequenceItems?.count ?? 0, 0)

        let box = try XCTUnwrap(displaySets[0][.imageBoxesSequence]?.sequenceItems?.first)
        XCTAssertEqual(box[.preferredPlaybackSequencing]?.uint16Value, 1, "Sweeping")
        XCTAssertEqual(box[.recommendedDisplayFrameRate]?.stringValue?.trimmingCharacters(in: .whitespaces), "30")
        XCTAssertEqual(box[.displayEnvironmentSpatialPosition]?.float64Values, [0, 1, 0.5, 0])

        let scrolling = try XCTUnwrap(dataSet.sequence(for: .synchronizedScrollingSequence))
        XCTAssertEqual(scrolling.count, 1)
        XCTAssertEqual(scrolling[0][.displaySetScrollingGroup]?.vr, .US)
        XCTAssertEqual(scrolling[0][.displaySetScrollingGroup]?.uint16Values, [1, 2], "US VM 2-n")

        let navigation = try XCTUnwrap(dataSet.sequence(for: .navigationIndicatorSequence)?.first)
        XCTAssertEqual(navigation[.navigationDisplaySet]?.uint16Value, 1)
        XCTAssertEqual(navigation[.referenceDisplaySets]?.uint16Values, [2])
    }

    /// Nominal Screen Definition Sequence (0072,0102) and Hanging Protocol User
    /// Identification Code Sequence (0072,000E) are Type 2: present, empty.
    func test_serialize_typeTwoSequencesWrittenEmpty() throws {
        let dataSet = try HangingProtocolSerializer().serialize(protocol: HangingProtocol(name: "T"))
        XCTAssertNotNil(dataSet[.nominalScreenDefinitionSequence])
        XCTAssertEqual(dataSet.sequence(for: .nominalScreenDefinitionSequence)?.count ?? 0, 0)
        XCTAssertNotNil(dataSet[.hangingProtocolUserIdentificationCodeSequence])
        XCTAssertEqual(dataSet.sequence(for: .hangingProtocolUserIdentificationCodeSequence)?.count ?? 0, 0)
    }

    // MARK: - Parse back

    func test_roundTrip_fullProtocol() throws {
        let original = Self.fullProtocol()
        let parsed = try HangingProtocolParser().parse(from: try HangingProtocolSerializer().serialize(protocol: original))

        let timeBased = try XCTUnwrap(parsed.imageSets.first?.timeBasedImageSets)
        XCTAssertEqual(timeBased.map(\.number), [1, 2, 3])
        XCTAssertEqual(timeBased.map(\.category), [.relativeTime, .abstractPrior, .abstractPrior])
        XCTAssertEqual(timeBased.map(\.label), ["Current", "Prior", nil])
        XCTAssertEqual(timeBased[0].timeSelection?.relativeTimeUnits, .days)
        XCTAssertEqual(timeBased[1].timeSelection?.abstractPriorRange, [1, 1])
        XCTAssertEqual(timeBased[2].abstractPriorCode?.codeValue, "PRIOR1")
        XCTAssertEqual(parsed.imageSetNumbers, [1, 2, 3])

        XCTAssertEqual(parsed.displaySets.map(\.imageSetNumber), [1, 2])
        let first = parsed.displaySets[0]
        XCTAssertEqual(first.filterOperations.count, 3)
        XCTAssertEqual(first.filterOperations[0].attribute, .sliceLocation)
        XCTAssertEqual(first.filterOperations[0].operator, .greaterThan)
        XCTAssertEqual(first.filterOperations[0].usageFlag, .noMatch)
        XCTAssertEqual(first.filterOperations[1].filterByCategory, .imagePlane)
        XCTAssertEqual(first.filterOperations[1].values, ["TRANSVERSE"])
        XCTAssertEqual(first.filterOperations[2].attributePresence, .present)
        XCTAssertEqual(first.sortingOperations.map(\.sortByCategory), [.alongAxis, nil])
        XCTAssertEqual(first.sortingOperations[1].attribute, .instanceNumber)
        XCTAssertEqual(first.blendingOperationType, .color)
        XCTAssertEqual(first.reformattingOperation?.type, .threeDRendering)
        XCTAssertEqual(first.reformattingOperation?.thickness, 2)
        XCTAssertEqual(first.threeDRenderingType, .mip)
        XCTAssertEqual(first.threeDRenderingSubtypes, ["SHADED"])
        let box = try XCTUnwrap(first.imageBoxes.first)
        XCTAssertEqual(box.preferredPlaybackSequencing, .sweeping)
        XCTAssertEqual(box.recommendedDisplayFrameRate, 30)
        XCTAssertEqual(box.displayEnvironmentSpatialPosition, [0, 1, 0.5, 0])
        XCTAssertTrue(parsed.displaySets[1].filterOperations.isEmpty)

        XCTAssertEqual(parsed.synchronizedScrolling, [SynchronizedScrollingGroup(displaySetNumbers: [1, 2])])
        XCTAssertEqual(parsed.navigationIndicators, [NavigationIndicator(navigationDisplaySet: 1, referenceDisplaySets: [2])])
        XCTAssertEqual(parsed.partialDataDisplayHandling, .maintainLayout)
    }

    /// The filters of a display set apply after the image set selectors
    func test_matcher_appliesDisplaySetFilters() throws {
        let hp = Self.fullProtocol()
        let matcher = ImageSetMatcher(imageSet: hp.imageSets[0])
        let axial = InstanceInfo(sopInstanceUID: "1.2.3", seriesInstanceUID: "1.2", attributes: [
            .modality: "CT", .sliceLocation: "12.5", .sliceThickness: "1",
            .imageOrientationPatient: "1\\0\\0\\0\\1\\0",
        ])
        let belowZero = InstanceInfo(sopInstanceUID: "1.2.3", seriesInstanceUID: "1.2", attributes: [
            .modality: "CT", .sliceLocation: "-3", .sliceThickness: "1",
            .imageOrientationPatient: "1\\0\\0\\0\\1\\0",
        ])
        XCTAssertTrue(matcher.matches(instance: axial, filteredBy: hp.displaySets[0]))
        XCTAssertFalse(matcher.matches(instance: belowZero, filteredBy: hp.displaySets[0]))
        XCTAssertTrue(matcher.matches(instance: belowZero, filteredBy: hp.displaySets[1]), "display set 2 has no filters")
    }

    // MARK: - Old DICOMKit layout

    /// A dataset in the layout earlier DICOMKit versions wrote: Image Set
    /// Number / Category / Label and Sorting Operations in the Image Sets
    /// Sequence item, Filter-by Operator in the selector item, a single
    /// Display Set Scrolling Group value per Display Sets Sequence item, and
    /// reformatting in the Image Boxes Sequence item.
    private func oldLayoutDataSet() -> DataSet {
        let writer = DICOMWriter()
        func at(_ tag: Tag, _ value: Tag) -> DataElement {
            DataElement(tag: tag, vr: .AT, length: 4, valueData: writer.serializeTag(value))
        }
        func item(_ elements: [DataElement]) -> SequenceItem { SequenceItem(elements: elements) }
        func sq(_ tag: Tag, _ items: [SequenceItem]) -> DataElement {
            var ds = DataSet(); ds.setSequence(items, for: tag); return ds[tag]!
        }

        var dataSet = DataSet()
        dataSet[.hangingProtocolName] = DataElement.string(tag: .hangingProtocolName, vr: .SH, value: "Old")
        dataSet[.hangingProtocolLevel] = DataElement.string(tag: .hangingProtocolLevel, vr: .CS, value: "SITE")

        let selector = item([
            at(.selectorAttribute, .sliceLocation),
            DataElement.string(tag: .selectorAttributeVR, vr: .CS, value: "DS"),
            DataElement.string(tag: .selectorDSValue, vr: .DS, value: "0"),
            DataElement.string(tag: .filterByOperator, vr: .CS, value: "GREATER_THAN"),
            DataElement.string(tag: .imageSetSelectorUsageFlag, vr: .CS, value: "MATCH"),
        ])
        let sort = item([
            DataElement.string(tag: .sortByCategory, vr: .CS, value: "ALONG_AXIS"),
            DataElement.string(tag: .sortingDirection, vr: .CS, value: "INCREASING"),
        ])
        let imageSet = item([
            DataElement.uint16(tag: .imageSetNumber, value: 1),
            DataElement.string(tag: .imageSetSelectorCategory, vr: .CS, value: "RELATIVE_TIME"),
            DataElement.string(tag: .imageSetLabel, vr: .LO, value: "Current"),
            sq(.imageSetSelectorSequence, [selector]),
            sq(.sortingOperationsSequence, [sort]),
        ])
        dataSet.setSequence([imageSet], for: .imageSetsSequence)

        func displaySet(_ number: UInt16) -> SequenceItem {
            let box = item([
                DataElement.uint16(tag: .imageBoxNumber, value: 1),
                DataElement.string(tag: .imageBoxLayoutType, vr: .CS, value: "STACK"),
                DataElement.string(tag: .reformattingOperationType, vr: .CS, value: "MPR"),
                DataElement.string(tag: .reformattingOperationInitialViewDirection, vr: .CS, value: "CORONAL"),
            ])
            return item([
                DataElement.uint16(tag: .displaySetNumber, value: number),
                DataElement.uint16(tag: .displaySetScrollingGroup, value: 7),
                sq(.imageBoxesSequence, [box]),
            ])
        }
        dataSet.setSequence([displaySet(1), displaySet(2)], for: .displaySetsSequence)
        return dataSet
    }

    @available(*, deprecated)
    func test_parse_oldLayout() throws {
        let parsed = try HangingProtocolParser().parse(from: oldLayoutDataSet())

        let imageSet = try XCTUnwrap(parsed.imageSets.first)
        XCTAssertEqual(imageSet.timeBasedImageSets.map(\.number), [1])
        XCTAssertEqual(imageSet.timeBasedImageSets.first?.label, "Current")
        XCTAssertEqual(imageSet.timeBasedImageSets.first?.category, .relativeTime)
        XCTAssertEqual(imageSet.sortOperations.first?.sortByCategory, .alongAxis, "kept on the deprecated API")

        // Promoted to the display sets that show the (only) image set
        for displaySet in parsed.displaySets {
            XCTAssertEqual(displaySet.filterOperations.first?.attribute, .sliceLocation)
            XCTAssertEqual(displaySet.filterOperations.first?.operator, .greaterThan)
            XCTAssertEqual(displaySet.sortingOperations.first?.sortByCategory, .alongAxis)
            XCTAssertEqual(displaySet.reformattingOperation?.type, .mpr)
            XCTAssertEqual(displaySet.reformattingOperation?.initialViewPlane, .coronal)
            XCTAssertEqual(displaySet.scrollingGroup, 7)
        }
        XCTAssertEqual(parsed.synchronizedScrolling, [SynchronizedScrollingGroup(displaySetNumbers: [1, 2])])
    }

    /// Re-serializing an old-layout file writes the 2026a nesting
    func test_oldLayout_reserializesInTheTwentySixANesting() throws {
        let parsed = try HangingProtocolParser().parse(from: oldLayoutDataSet())
        let dataSet = try HangingProtocolSerializer().serialize(protocol: parsed)

        let allowed = Set(Self.standardNesting.map { "\($0.parent)/\($0.tag)" })
        for (parent, tag) in Self.placements(dataSet) {
            XCTAssertTrue(allowed.contains("\(parent)/\(tag)"), "(\(tag)) in \(parent)")
        }

        let imageSet = try XCTUnwrap(dataSet.sequence(for: .imageSetsSequence)?.first)
        XCTAssertNil(imageSet[.imageSetNumber])
        XCTAssertNil(imageSet[.sortingOperationsSequence])
        XCTAssertEqual(imageSet[.timeBasedImageSetsSequence]?.sequenceItems?.first?[.imageSetNumber]?.uint16Value, 1)
        XCTAssertNil(imageSet[.imageSetSelectorSequence]?.sequenceItems?.first?[.filterByOperator])

        let displaySets = try XCTUnwrap(dataSet.sequence(for: .displaySetsSequence))
        for item in displaySets {
            XCTAssertEqual(item[.imageSetNumber]?.uint16Value, 1)
            XCTAssertNil(item[.displaySetScrollingGroup])
            XCTAssertEqual(item[.filterOperationsSequence]?.sequenceItems?.first?.string(for: .filterByOperator), "GREATER_THAN")
            XCTAssertEqual(item[.sortingOperationsSequence]?.sequenceItems?.first?.string(for: .sortByCategory), "ALONG_AXIS")
            XCTAssertEqual(item.string(for: .reformattingOperationType), "MPR")
            XCTAssertNil(item[.imageBoxesSequence]?.sequenceItems?.first?[.reformattingOperationType])
        }
        XCTAssertEqual(dataSet.sequence(for: .synchronizedScrollingSequence)?.first?[.displaySetScrollingGroup]?.uint16Values, [1, 2])
    }

    /// The deprecated model API still serializes into the 2026a nesting
    @available(*, deprecated)
    func test_deprecatedAPI_serializesInTheTwentySixANesting() throws {
        let hp = HangingProtocol(
            name: "Deprecated",
            imageSets: [ImageSetDefinition(
                number: 4, label: "Current",
                selectors: [ImageSetSelector(attribute: .sliceLocation, operator: .lessThan, values: ["100"])],
                sortOperations: [SortOperation(attribute: .instanceNumber)],
                category: .relativeTime)],
            displaySets: [
                DisplaySet(number: 1, scrollingGroup: 1, imageBoxes: [ImageBox(
                    number: 1, imageSetNumbers: [4],
                    reformattingOperation: ReformattingOperation(type: .threeDRendering, initialViewPlane: .sagittal),
                    threeDRenderingType: .volumeRendering)]),
                DisplaySet(number: 2, scrollingGroup: 1, imageBoxes: [ImageBox(number: 1, imageSetNumbers: [4])]),
            ]
        )
        let dataSet = try HangingProtocolSerializer().serialize(protocol: hp)
        let allowed = Set(Self.standardNesting.map { "\($0.parent)/\($0.tag)" })
        for (parent, tag) in Self.placements(dataSet) {
            XCTAssertTrue(allowed.contains("\(parent)/\(tag)"), "(\(tag)) in \(parent)")
        }
        let displaySets = try XCTUnwrap(dataSet.sequence(for: .displaySetsSequence))
        XCTAssertEqual(displaySets.map { $0[.imageSetNumber]?.uint16Value }, [4, 4])
        XCTAssertEqual(displaySets[0][.filterOperationsSequence]?.sequenceItems?.first?.string(for: .filterByOperator), "LESS_THAN")
        XCTAssertEqual(displaySets[0][.sortingOperationsSequence]?.sequenceItems?.first?[.selectorAttribute]?.attributeTagValue, .instanceNumber)
        XCTAssertEqual(displaySets[0].string(for: .reformattingOperationType), "3D_RENDERING")
        XCTAssertEqual(displaySets[0][.threeDRenderingType]?.stringValues, ["VOLUME"])
        XCTAssertEqual(dataSet.sequence(for: .synchronizedScrollingSequence)?.first?[.displaySetScrollingGroup]?.uint16Values, [1, 2])
    }
}
