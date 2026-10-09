//
// SpatialTransformationTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class SpatialTransformationTests: XCTestCase {
    
    // MARK: - SpatialTransformation Tests
    
    func test_spatialTransformation_noTransform() {
        let transform = SpatialTransformation()
        
        XCTAssertEqual(transform.rotation, 0)
        XCTAssertFalse(transform.horizontalFlip)
        XCTAssertFalse(transform.isRotated)
        XCTAssertFalse(transform.isFlipped)
        XCTAssertFalse(transform.hasTransformation)
    }
    
    func test_spatialTransformation_rotation0() {
        let transform = SpatialTransformation(rotation: 0)
        
        XCTAssertEqual(transform.rotation, 0)
        XCTAssertFalse(transform.isRotated)
    }
    
    func test_spatialTransformation_rotation90() {
        let transform = SpatialTransformation(rotation: 90)
        
        XCTAssertEqual(transform.rotation, 90)
        XCTAssertTrue(transform.isRotated)
        XCTAssertTrue(transform.hasTransformation)
    }
    
    func test_spatialTransformation_rotation180() {
        let transform = SpatialTransformation(rotation: 180)
        
        XCTAssertEqual(transform.rotation, 180)
        XCTAssertTrue(transform.isRotated)
    }
    
    func test_spatialTransformation_rotation270() {
        let transform = SpatialTransformation(rotation: 270)
        
        XCTAssertEqual(transform.rotation, 270)
        XCTAssertTrue(transform.isRotated)
    }
    
    func test_spatialTransformation_rotation360() {
        // 360 degrees should normalize to 0
        let transform = SpatialTransformation(rotation: 360)
        
        XCTAssertEqual(transform.rotation, 0)
        XCTAssertFalse(transform.isRotated)
    }
    
    func test_spatialTransformation_rotation450() {
        // 450 degrees = 360 + 90 = 90 degrees
        let transform = SpatialTransformation(rotation: 450)
        
        XCTAssertEqual(transform.rotation, 90)
        XCTAssertTrue(transform.isRotated)
    }
    
    func test_spatialTransformation_rotationNegative90() {
        // -90 degrees should normalize to 270
        let transform = SpatialTransformation(rotation: -90)
        
        XCTAssertEqual(transform.rotation, 270)
        XCTAssertTrue(transform.isRotated)
    }
    
    func test_spatialTransformation_rotationNegative180() {
        // -180 degrees should normalize to 180
        let transform = SpatialTransformation(rotation: -180)
        
        XCTAssertEqual(transform.rotation, 180)
        XCTAssertTrue(transform.isRotated)
    }
    
    func test_spatialTransformation_rotationNegative270() {
        // -270 degrees should normalize to 90
        let transform = SpatialTransformation(rotation: -270)
        
        XCTAssertEqual(transform.rotation, 90)
        XCTAssertTrue(transform.isRotated)
    }
    
    func test_spatialTransformation_rotationRounding() {
        // Image Rotation (0070,0042) has the Enumerated Values 0, 90, 180, 270
        // and no negative values (PS3.3 2026a Table C.10-6). Other angles round
        // to the nearest quarter turn, ties upward, and the result is always one
        // of the four Enumerated Values.
        let transform1 = SpatialTransformation(rotation: 45)
        XCTAssertEqual(transform1.rotation, 90)  // Rounds to nearest 90
        
        let transform2 = SpatialTransformation(rotation: 135)
        XCTAssertEqual(transform2.rotation, 180)  // Rounds to 180
        
        let transform3 = SpatialTransformation(rotation: 225)
        XCTAssertEqual(transform3.rotation, 270)  // Rounds to 270
        
        let transform4 = SpatialTransformation(rotation: 315)
        XCTAssertEqual(transform4.rotation, 0)  // Rounds to 0, not 360

        let transform5 = SpatialTransformation(rotation: -135)
        XCTAssertEqual(transform5.rotation, 270)  // -135 ≡ 225, not -90

        for angle in stride(from: -720, through: 720, by: 15) {
            XCTAssertTrue([0, 90, 180, 270].contains(SpatialTransformation(rotation: angle).rotation),
                          "rotation \(angle) gave \(SpatialTransformation(rotation: angle).rotation)")
        }
    }
    
    func test_spatialTransformation_horizontalFlip() {
        let transform = SpatialTransformation(horizontalFlip: true)
        
        XCTAssertTrue(transform.horizontalFlip)
        XCTAssertTrue(transform.isFlipped)
        XCTAssertTrue(transform.hasTransformation)
    }
    
    func test_spatialTransformation_rotationAndFlip() {
        let transform = SpatialTransformation(rotation: 90, horizontalFlip: true)
        
        XCTAssertEqual(transform.rotation, 90)
        XCTAssertTrue(transform.horizontalFlip)
        XCTAssertTrue(transform.isRotated)
        XCTAssertTrue(transform.isFlipped)
        XCTAssertTrue(transform.hasTransformation)
    }
    
    func test_spatialTransformation_equality() {
        let transform1 = SpatialTransformation(rotation: 90, horizontalFlip: true)
        let transform2 = SpatialTransformation(rotation: 90, horizontalFlip: true)
        let transform3 = SpatialTransformation(rotation: 180, horizontalFlip: true)
        
        XCTAssertEqual(transform1, transform2)
        XCTAssertNotEqual(transform1, transform3)
    }
    
    func test_spatialTransformation_hashable() {
        let transform1 = SpatialTransformation(rotation: 90, horizontalFlip: true)
        let transform2 = SpatialTransformation(rotation: 90, horizontalFlip: true)
        let transform3 = SpatialTransformation(rotation: 180, horizontalFlip: false)
        
        let set: Set = [transform1, transform2, transform3]
        XCTAssertEqual(set.count, 2)
    }
    
    // MARK: - DisplayedArea Tests
    
    func test_displayedArea_initialization() {
        let area = DisplayedArea(
            topLeft: (column: 0, row: 0),
            bottomRight: (column: 511, row: 511)
        )
        
        XCTAssertEqual(area.topLeft.column, 0)
        XCTAssertEqual(area.topLeft.row, 0)
        XCTAssertEqual(area.bottomRight.column, 511)
        XCTAssertEqual(area.bottomRight.row, 511)
        XCTAssertEqual(area.sizeMode, .scaleToFit)  // Default
    }
    
    func test_displayedArea_width() {
        let area = DisplayedArea(
            topLeft: (column: 100, row: 100),
            bottomRight: (column: 299, row: 299)
        )
        
        // Width = 299 - 100 + 1 = 200
        XCTAssertEqual(area.width, 200)
    }
    
    func test_displayedArea_height() {
        let area = DisplayedArea(
            topLeft: (column: 100, row: 100),
            bottomRight: (column: 299, row: 299)
        )
        
        // Height = 299 - 100 + 1 = 200
        XCTAssertEqual(area.height, 200)
    }
    
    func test_displayedArea_scaleToFit() {
        let area = DisplayedArea(
            topLeft: (column: 0, row: 0),
            bottomRight: (column: 511, row: 511),
            sizeMode: .scaleToFit
        )
        
        XCTAssertEqual(area.sizeMode, .scaleToFit)
    }
    
    func test_displayedArea_trueSize() {
        let area = DisplayedArea(
            topLeft: (column: 0, row: 0),
            bottomRight: (column: 511, row: 511),
            sizeMode: .trueSize
        )
        
        XCTAssertEqual(area.sizeMode, .trueSize)
    }
    
    func test_displayedArea_magnify() {
        let area = DisplayedArea(
            topLeft: (column: 0, row: 0),
            bottomRight: (column: 511, row: 511),
            sizeMode: .magnify
        )
        
        XCTAssertEqual(area.sizeMode, .magnify)
    }
    
    func test_displayedArea_equality() {
        let area1 = DisplayedArea(
            topLeft: (column: 0, row: 0),
            bottomRight: (column: 511, row: 511),
            sizeMode: .scaleToFit
        )
        let area2 = DisplayedArea(
            topLeft: (column: 0, row: 0),
            bottomRight: (column: 511, row: 511),
            sizeMode: .scaleToFit
        )
        let area3 = DisplayedArea(
            topLeft: (column: 0, row: 0),
            bottomRight: (column: 255, row: 255),
            sizeMode: .scaleToFit
        )
        
        XCTAssertEqual(area1, area2)
        XCTAssertNotEqual(area1, area3)
    }
    
    func test_displayedArea_hashable() {
        let area1 = DisplayedArea(
            topLeft: (column: 0, row: 0),
            bottomRight: (column: 511, row: 511),
            sizeMode: .scaleToFit
        )
        let area2 = DisplayedArea(
            topLeft: (column: 0, row: 0),
            bottomRight: (column: 511, row: 511),
            sizeMode: .scaleToFit
        )
        let area3 = DisplayedArea(
            topLeft: (column: 100, row: 100),
            bottomRight: (column: 299, row: 299),
            sizeMode: .trueSize
        )
        
        let set: Set = [area1, area2, area3]
        XCTAssertEqual(set.count, 2)
    }
    
    // MARK: - PresentationSizeMode Tests
    
    func test_presentationSizeMode_scaleToFit() {
        XCTAssertEqual(PresentationSizeMode.scaleToFit.rawValue, "SCALE TO FIT")
    }
    
    func test_presentationSizeMode_trueSize() {
        XCTAssertEqual(PresentationSizeMode.trueSize.rawValue, "TRUE SIZE")
    }
    
    func test_presentationSizeMode_magnify() {
        XCTAssertEqual(PresentationSizeMode.magnify.rawValue, "MAGNIFY")
    }
}
