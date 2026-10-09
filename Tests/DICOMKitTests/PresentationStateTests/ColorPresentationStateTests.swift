//
// ColorPresentationStateTests.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import XCTest
import DICOMCore
@testable import DICOMKit

final class ColorPresentationStateTests: XCTestCase {
    
    // MARK: - ICCProfile Tests
    
    func test_iccProfile_initialization() {
        let profileData = Data([0x00, 0x01, 0x02, 0x03])
        let profile = ICCProfile(
            profileData: profileData,
            colorSpace: .sRGB
        )
        
        XCTAssertEqual(profile.profileData, profileData)
        XCTAssertEqual(profile.colorSpace, .sRGB)
        XCTAssertNil(profile.description)
    }
    
    func test_iccProfile_withDescription() {
        let profileData = Data([0x00, 0x01, 0x02, 0x03])
        let profile = ICCProfile(
            profileData: profileData,
            colorSpace: .adobeRGB,
            description: "Adobe RGB 1998"
        )
        
        XCTAssertEqual(profile.colorSpace, .adobeRGB)
        XCTAssertEqual(profile.description, "Adobe RGB 1998")
    }
    
    func test_iccProfile_displayP3ColorSpace() {
        let profileData = Data([0x00, 0x01, 0x02, 0x03])
        let profile = ICCProfile(
            profileData: profileData,
            colorSpace: .displayP3
        )
        
        XCTAssertEqual(profile.colorSpace, .displayP3)
    }
    
    func test_iccProfile_proPhotoRGBColorSpace() {
        let profileData = Data([0x00, 0x01, 0x02, 0x03])
        let profile = ICCProfile(
            profileData: profileData,
            colorSpace: .proPhotoRGB
        )
        
        XCTAssertEqual(profile.colorSpace, .proPhotoRGB)
    }
    
    func test_iccProfile_customColorSpace() {
        let profileData = Data([0x00, 0x01, 0x02, 0x03])
        let profile = ICCProfile(
            profileData: profileData,
            colorSpace: .custom,
            description: "Custom ICC Profile"
        )
        
        XCTAssertEqual(profile.colorSpace, .custom)
        XCTAssertEqual(profile.description, "Custom ICC Profile")
    }
    
    func test_iccProfile_hashable() {
        let data1 = Data([0x00, 0x01])
        let data2 = Data([0x00, 0x01])
        let data3 = Data([0x02, 0x03])
        
        let profile1 = ICCProfile(profileData: data1, colorSpace: .sRGB)
        let profile2 = ICCProfile(profileData: data2, colorSpace: .sRGB)
        let profile3 = ICCProfile(profileData: data3, colorSpace: .sRGB)
        
        XCTAssertEqual(profile1, profile2)
        XCTAssertNotEqual(profile1, profile3)
        
        let set: Set = [profile1, profile2, profile3]
        XCTAssertEqual(set.count, 2)
    }
    
    func test_iccProfile_emptyProfileData() {
        let profileData = Data()
        let profile = ICCProfile(
            profileData: profileData,
            colorSpace: .sRGB
        )
        
        XCTAssertEqual(profile.profileData.count, 0)
    }
    
    func test_iccProfile_largeProfileData() {
        let profileData = Data(repeating: 0xFF, count: 10000)
        let profile = ICCProfile(
            profileData: profileData,
            colorSpace: .adobeRGB
        )
        
        XCTAssertEqual(profile.profileData.count, 10000)
    }
    
    // MARK: - ColorSpace Tests
    
    func test_colorSpace_sRGB() {
        XCTAssertEqual(ColorSpace.sRGB.rawValue, "sRGB")
    }
    
    func test_colorSpace_adobeRGB() {
        XCTAssertEqual(ColorSpace.adobeRGB.rawValue, "Adobe RGB")
    }
    
    func test_colorSpace_displayP3() {
        XCTAssertEqual(ColorSpace.displayP3.rawValue, "Display P3")
    }
    
    func test_colorSpace_proPhotoRGB() {
        XCTAssertEqual(ColorSpace.proPhotoRGB.rawValue, "ProPhoto RGB")
    }
    
    func test_colorSpace_genericRGB() {
        XCTAssertEqual(ColorSpace.genericRGB.rawValue, "Generic RGB")
    }
    
    func test_colorSpace_custom() {
        XCTAssertEqual(ColorSpace.custom.rawValue, "custom")
    }
    
    func test_colorSpace_allCases() {
        // ColorSpace is a display model, not the (0028,2002) Defined Terms of
        // PS3.3 C.11.15.1.2; rec2020 and the three YBR cases were added after
        // this suite was written.
        let allCases = ColorSpace.allCases
        XCTAssertEqual(allCases.count, 10)
        XCTAssertTrue(allCases.contains(.sRGB))
        XCTAssertTrue(allCases.contains(.adobeRGB))
        XCTAssertTrue(allCases.contains(.displayP3))
        XCTAssertTrue(allCases.contains(.proPhotoRGB))
        XCTAssertTrue(allCases.contains(.rec2020))
        XCTAssertTrue(allCases.contains(.genericRGB))
        XCTAssertTrue(allCases.contains(.ybrFull))
        XCTAssertTrue(allCases.contains(.ybrFull422))
        XCTAssertTrue(allCases.contains(.ybrPartial420))
        XCTAssertTrue(allCases.contains(.custom))
    }
    
    // MARK: - ColorPresentationState Tests
    
    func test_colorPresentationState_minimal() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series]
        )
        
        XCTAssertEqual(ps.sopInstanceUID, "1.2.3.4.5.6")
        XCTAssertEqual(ps.sopClassUID, "1.2.840.10008.5.1.4.1.1.11.2")
        XCTAssertEqual(ps.referencedSeries.count, 1)
        XCTAssertNil(ps.iccProfile)
        XCTAssertNil(ps.spatialTransformation)
        XCTAssertNil(ps.displayedArea)
        XCTAssertTrue(ps.graphicLayers.isEmpty)
        XCTAssertTrue(ps.graphicAnnotations.isEmpty)
        XCTAssertTrue(ps.shutters.isEmpty)
    }
    
    func test_colorPresentationState_withICCProfile() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        let iccProfile = ICCProfile(
            profileData: Data([0x00, 0x01]),
            colorSpace: .sRGB
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series],
            iccProfile: iccProfile
        )
        
        XCTAssertNotNil(ps.iccProfile)
        XCTAssertEqual(ps.iccProfile?.colorSpace, .sRGB)
    }
    
    func test_colorPresentationState_withIdentificationInfo() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            instanceNumber: 1,
            presentationLabel: "Color Presentation",
            presentationDescription: "A color presentation state",
            referencedSeries: [series]
        )
        
        XCTAssertEqual(ps.instanceNumber, 1)
        XCTAssertEqual(ps.presentationLabel, "Color Presentation")
        XCTAssertEqual(ps.presentationDescription, "A color presentation state")
    }
    
    func test_colorPresentationState_withSpatialTransformation() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        let transform = SpatialTransformation(rotation: 90)
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series],
            spatialTransformation: transform
        )
        
        XCTAssertNotNil(ps.spatialTransformation)
        XCTAssertEqual(ps.spatialTransformation?.rotation, 90)
    }
    
    func test_colorPresentationState_withGraphicLayers() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        let layer = GraphicLayer(
            name: "Annotations",
            order: 1,
            description: "Graphic annotations"
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series],
            graphicLayers: [layer]
        )
        
        XCTAssertEqual(ps.graphicLayers.count, 1)
        XCTAssertEqual(ps.graphicLayers[0].name, "Annotations")
        XCTAssertEqual(ps.graphicLayers[0].order, 1)
    }
    
    func test_colorPresentationState_withGraphicAnnotations() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        let annotation = GraphicAnnotation(
            layer: "Annotations",
            referencedImages: [image]
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series],
            graphicAnnotations: [annotation]
        )
        
        XCTAssertEqual(ps.graphicAnnotations.count, 1)
        XCTAssertEqual(ps.graphicAnnotations[0].layer, "Annotations")
    }
    
    func test_colorPresentationState_withShutters() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        let shutter = DisplayShutter.rectangular(
            left: 0, right: 100, top: 0, bottom: 100,
            presentationValue: 0
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series],
            shutters: [shutter]
        )
        
        XCTAssertEqual(ps.shutters.count, 1)
        XCTAssertEqual(ps.shutters[0].presentationValue, 0)
    }
    
    func test_colorPresentationState_withAllComponents() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        let iccProfile = ICCProfile(
            profileData: Data([0x00, 0x01]),
            colorSpace: .adobeRGB
        )
        let transform = SpatialTransformation(rotation: 180)
        let layer = GraphicLayer(name: "Annotations", order: 1)
        let annotation = GraphicAnnotation(layer: "Annotations", referencedImages: [image])
        let shutter = DisplayShutter.circular(
            centerColumn: 256, centerRow: 256, radius: 200,
            presentationValue: 0
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            instanceNumber: 1,
            presentationLabel: "Full Color State",
            presentationDescription: "Color with all components",
            referencedSeries: [series],
            iccProfile: iccProfile,
            spatialTransformation: transform,
            graphicLayers: [layer],
            graphicAnnotations: [annotation],
            shutters: [shutter]
        )
        
        XCTAssertNotNil(ps.iccProfile)
        XCTAssertNotNil(ps.spatialTransformation)
        XCTAssertEqual(ps.graphicLayers.count, 1)
        XCTAssertEqual(ps.graphicAnnotations.count, 1)
        XCTAssertEqual(ps.shutters.count, 1)
        XCTAssertEqual(ps.instanceNumber, 1)
        XCTAssertEqual(ps.presentationLabel, "Full Color State")
    }
    
    func test_colorPresentationState_multipleReferencedSeries() {
        let image1 = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let image2 = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.6"
        )
        let series1 = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image1]
        )
        let series2 = ReferencedSeries(
            seriesInstanceUID: "1.2.3.5",
            referencedImages: [image2]
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series1, series2]
        )
        
        XCTAssertEqual(ps.referencedSeries.count, 2)
        XCTAssertEqual(ps.referencedSeries[0].seriesInstanceUID, "1.2.3.4")
        XCTAssertEqual(ps.referencedSeries[1].seriesInstanceUID, "1.2.3.5")
    }
    
    func test_colorPresentationState_multipleLayers() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        let layer1 = GraphicLayer(name: "Annotations", order: 1)
        let layer2 = GraphicLayer(name: "Measurements", order: 2)
        let layer3 = GraphicLayer(name: "Comments", order: 3)
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series],
            graphicLayers: [layer1, layer2, layer3]
        )
        
        XCTAssertEqual(ps.graphicLayers.count, 3)
        XCTAssertEqual(ps.graphicLayers[1].order, 2)
        XCTAssertEqual(ps.graphicLayers[2].name, "Comments")
    }
    
    func test_colorPresentationState_multipleShutters() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        let shutter1 = DisplayShutter.rectangular(
            left: 0, right: 100, top: 0, bottom: 100,
            presentationValue: 0
        )
        let shutter2 = DisplayShutter.circular(
            centerColumn: 256, centerRow: 256, radius: 100,
            presentationValue: 50
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series],
            shutters: [shutter1, shutter2]
        )
        
        XCTAssertEqual(ps.shutters.count, 2)
        XCTAssertEqual(ps.shutters[1].presentationValue, 50)
    }
    
    func test_colorPresentationState_sRGBICCProfile() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        let iccProfile = ICCProfile(
            profileData: Data([0x00, 0x01, 0x02]),
            colorSpace: .sRGB,
            description: "Standard RGB"
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series],
            iccProfile: iccProfile
        )
        
        XCTAssertEqual(ps.iccProfile?.colorSpace, .sRGB)
        XCTAssertEqual(ps.iccProfile?.description, "Standard RGB")
    }
    
    func test_colorPresentationState_customICCProfile() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        let iccProfile = ICCProfile(
            profileData: Data(repeating: 0xFF, count: 1000),
            colorSpace: .custom,
            description: "Custom Medical Device Profile"
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series],
            iccProfile: iccProfile
        )
        
        XCTAssertEqual(ps.iccProfile?.colorSpace, .custom)
        XCTAssertTrue(ps.iccProfile?.profileData.count ?? 0 > 0)
    }
    
    func test_colorPresentationState_sendable() {
        let image = ReferencedImage(
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5"
        )
        let series = ReferencedSeries(
            seriesInstanceUID: "1.2.3.4",
            referencedImages: [image]
        )
        
        let ps = ColorPresentationState(
            sopInstanceUID: "1.2.3.4.5.6",
            referencedSeries: [series]
        )
        
        // Verify that it's Sendable by using it in a concurrent context
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        queue.async {
            _ = ps.sopInstanceUID
            _ = ps.sopClassUID
        }
        
        queue.sync { }
    }
}
