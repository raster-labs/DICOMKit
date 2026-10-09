import Testing
import Foundation
@testable import DICOMKit
import DICOMCore

/// PS3.3 2026a C.18.6.1.2: a 2D SCOORD POLYLINE whose first and last vertices are the same is a
/// closed polygon; there is no 2D POLYGON Graphic Type (D18).
@Suite("SpatialCoordinates closed POLYLINE")
struct SpatialCoordinatesClosedPolylineTests {

    @Test("A closed POLYLINE has an area and its perimeter counts the closing segment once")
    func closedPolylineGeometry() {
        let square = SpatialCoordinatesContentItem(
            graphicType: .polyline,
            graphicData: [0, 0, 10, 0, 10, 10, 0, 10, 0, 0]
        )
        let coords = SpatialCoordinates(contentItem: square)

        #expect(coords.isClosed)
        #expect(coords.area == 100)
        #expect(coords.perimeter == 40)
    }

    @Test("An open POLYLINE has no area")
    func openPolylineHasNoArea() {
        let open = SpatialCoordinatesContentItem(
            graphicType: .polyline,
            graphicData: [0, 0, 10, 0, 10, 10]
        )
        let coords = SpatialCoordinates(contentItem: open)

        #expect(!coords.isClosed)
        #expect(coords.area == nil)
    }
}
