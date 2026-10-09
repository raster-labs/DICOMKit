import Testing
@testable import DICOMCore

@Suite("Extended Tag Tests")
struct ExtendedTagTests {
    
    // MARK: - File Meta Information Tags
    
    @Test("File Meta Information tags are correct")
    func testFileMetaInformationTags() {
        #expect(Tag.fileMetaInformationGroupLength.group == 0x0002)
        #expect(Tag.fileMetaInformationGroupLength.element == 0x0000)
        
        #expect(Tag.mediaStorageSOPClassUID.group == 0x0002)
        #expect(Tag.mediaStorageSOPClassUID.element == 0x0002)
        
        #expect(Tag.transferSyntaxUID.group == 0x0002)
        #expect(Tag.transferSyntaxUID.element == 0x0010)
    }
    
    // MARK: - Patient Information Tags
    
    @Test("Patient information tags are correct")
    func testPatientInformationTags() {
        #expect(Tag.patientName.group == 0x0010)
        #expect(Tag.patientName.element == 0x0010)
        
        #expect(Tag.patientID.group == 0x0010)
        #expect(Tag.patientID.element == 0x0020)
        
        #expect(Tag.patientBirthDate.group == 0x0010)
        #expect(Tag.patientBirthDate.element == 0x0030)
        
        #expect(Tag.patientSex.group == 0x0010)
        #expect(Tag.patientSex.element == 0x0040)
        
        // Extended patient tags
        #expect(Tag.patientSpeciesDescription.group == 0x0010)
        #expect(Tag.patientSpeciesDescription.element == 0x2201)
        
        #expect(Tag.pregnancyStatus.group == 0x0010)
        #expect(Tag.pregnancyStatus.element == 0x21C0)
    }
    
    // MARK: - Study Information Tags
    
    @Test("Study information tags are correct")
    func testStudyInformationTags() {
        #expect(Tag.studyInstanceUID.group == 0x0020)
        #expect(Tag.studyInstanceUID.element == 0x000D)
        
        #expect(Tag.studyID.group == 0x0020)
        #expect(Tag.studyID.element == 0x0010)
        
        #expect(Tag.studyDate.group == 0x0008)
        #expect(Tag.studyDate.element == 0x0020)
        
        #expect(Tag.accessionNumber.group == 0x0008)
        #expect(Tag.accessionNumber.element == 0x0050)
        
        #expect(Tag.studyDescription.group == 0x0008)
        #expect(Tag.studyDescription.element == 0x1030)
    }
    
    // MARK: - Series Information Tags
    
    @Test("Series information tags are correct")
    func testSeriesInformationTags() {
        #expect(Tag.seriesInstanceUID.group == 0x0020)
        #expect(Tag.seriesInstanceUID.element == 0x000E)
        
        #expect(Tag.seriesNumber.group == 0x0020)
        #expect(Tag.seriesNumber.element == 0x0011)
        
        #expect(Tag.modality.group == 0x0008)
        #expect(Tag.modality.element == 0x0060)
        
        #expect(Tag.seriesDescription.group == 0x0008)
        #expect(Tag.seriesDescription.element == 0x103E)
        
        #expect(Tag.bodyPartExamined.group == 0x0018)
        #expect(Tag.bodyPartExamined.element == 0x0015)
        
        #expect(Tag.protocolName.group == 0x0018)
        #expect(Tag.protocolName.element == 0x1030)
    }
    
    // MARK: - Image Information Tags
    
    @Test("Image information tags are correct")
    func testImageInformationTags() {
        #expect(Tag.instanceNumber.group == 0x0020)
        #expect(Tag.instanceNumber.element == 0x0013)
        
        #expect(Tag.sopInstanceUID.group == 0x0008)
        #expect(Tag.sopInstanceUID.element == 0x0018)
        
        #expect(Tag.sopClassUID.group == 0x0008)
        #expect(Tag.sopClassUID.element == 0x0016)
        
        // Image pixel tags
        #expect(Tag.rows.group == 0x0028)
        #expect(Tag.rows.element == 0x0010)
        
        #expect(Tag.columns.group == 0x0028)
        #expect(Tag.columns.element == 0x0011)
        
        #expect(Tag.bitsAllocated.group == 0x0028)
        #expect(Tag.bitsAllocated.element == 0x0100)
        
        #expect(Tag.photometricInterpretation.group == 0x0028)
        #expect(Tag.photometricInterpretation.element == 0x0004)
    }
    
    // MARK: - Pixel Data Tags
    
    @Test("Pixel data tags are correct")
    func testPixelDataTags() {
        #expect(Tag.pixelData.group == 0x7FE0)
        #expect(Tag.pixelData.element == 0x0010)
        
        #expect(Tag.floatPixelData.group == 0x7FE0)
        #expect(Tag.floatPixelData.element == 0x0008)
        
        #expect(Tag.windowCenter.group == 0x0028)
        #expect(Tag.windowCenter.element == 0x1050)
        
        #expect(Tag.windowWidth.group == 0x0028)
        #expect(Tag.windowWidth.element == 0x1051)
        
        #expect(Tag.rescaleIntercept.group == 0x0028)
        #expect(Tag.rescaleIntercept.element == 0x1052)
        
        #expect(Tag.rescaleSlope.group == 0x0028)
        #expect(Tag.rescaleSlope.element == 0x1053)
    }
    
    // MARK: - Modality Specific Tags
    
    @Test("CT modality tags are correct")
    func testCTModalityTags() {
        #expect(Tag.kvp.group == 0x0018)
        #expect(Tag.kvp.element == 0x0060)
        
        #expect(Tag.convolutionKernel.group == 0x0018)
        #expect(Tag.convolutionKernel.element == 0x1210)
        
        #expect(Tag.exposureTime.group == 0x0018)
        #expect(Tag.exposureTime.element == 0x1150)
    }
    
    @Test("MR modality tags are correct")
    func testMRModalityTags() {
        #expect(Tag.scanningSequence.group == 0x0018)
        #expect(Tag.scanningSequence.element == 0x0020)
        
        #expect(Tag.magneticFieldStrength.group == 0x0018)
        #expect(Tag.magneticFieldStrength.element == 0x0087)
        
        #expect(Tag.echoTime.group == 0x0018)
        #expect(Tag.echoTime.element == 0x0081)
        
        #expect(Tag.repetitionTime.group == 0x0018)
        #expect(Tag.repetitionTime.element == 0x0080)
        
        #expect(Tag.flipAngle.group == 0x0018)
        #expect(Tag.flipAngle.element == 0x1314)
    }
    
    // MARK: - Overlay Tags
    
    @Test("Overlay tags are correct")
    func testOverlayTags() {
        #expect(Tag.overlayRows.group == 0x6000)
        #expect(Tag.overlayRows.element == 0x0010)
        
        #expect(Tag.overlayColumns.group == 0x6000)
        #expect(Tag.overlayColumns.element == 0x0011)
        
        #expect(Tag.overlayData.group == 0x6000)
        #expect(Tag.overlayData.element == 0x3000)
    }
    
    // MARK: - Structured Reporting Tags
    
    @Test("Structured reporting tags are correct")
    func testStructuredReportingTags() {
        #expect(Tag.valueType.group == 0x0040)
        #expect(Tag.valueType.element == 0xA040)
        
        #expect(Tag.conceptNameCodeSequence.group == 0x0040)
        #expect(Tag.conceptNameCodeSequence.element == 0xA043)
        
        #expect(Tag.contentSequence.group == 0x0040)
        #expect(Tag.contentSequence.element == 0xA730)
        
        #expect(Tag.verificationFlag.group == 0x0040)
        #expect(Tag.verificationFlag.element == 0xA493)
    }
    
    // MARK: - Waveform Tags
    
    @Test("Waveform tags are correct")
    func testWaveformTags() {
        // Waveform Sequence lives in group 0x5400 (correct per PS3.6).
        #expect(Tag.waveformSequence.group == 0x5400)
        #expect(Tag.waveformSequence.element == 0x0100)

        // Acquisition + channel-definition attributes live in group 0x003A per
        // PS3.6 (not 0x5400 — that earlier value was a bug that made
        // WaveformParser reject standards-compliant waveforms).
        #expect(Tag.numberOfWaveformChannels.group == 0x003A)
        #expect(Tag.numberOfWaveformChannels.element == 0x0005)

        #expect(Tag.numberOfWaveformSamples.group == 0x003A)
        #expect(Tag.numberOfWaveformSamples.element == 0x0010)

        #expect(Tag.samplingFrequency.group == 0x003A)
        #expect(Tag.samplingFrequency.element == 0x001A)
    }
    
    // MARK: - Tag Uniqueness
    
    @Test("All tags have unique group-element combinations")
    func testTagUniqueness() {
        // Create a sample of tags to check for duplicates
        let tags: [DICOMCore.Tag] = [
            .patientName, .patientID, .patientBirthDate, .patientSex,
            .studyInstanceUID, .studyID, .studyDate,
            .seriesInstanceUID, .seriesNumber, .modality,
            .instanceNumber, .sopInstanceUID, .sopClassUID,
            .pixelData, .rows, .columns, .bitsAllocated,
            .transferSyntaxUID, .fileMetaInformationGroupLength
        ]
        
        // Convert to set - if count differs, there are duplicates
        let uniqueTags = Set(tags)
        #expect(tags.count == uniqueTags.count)
    }
    
    // MARK: - Tag Formatting
    
    @Test("Extended tags format correctly")
    func testExtendedTagFormatting() {
        #expect(Tag.overlayRows.description == "(6000,0010)")
        #expect(Tag.waveformSequence.description == "(5400,0100)")
        #expect(Tag.clinicalTrialProtocolID.description == "(0012,0020)")
    }

    // MARK: - D35: RT tags the parsers used as literals (PS3.6 2026a Table 6-1)

    @Test("DVH Volume Units, High-Dose Technique Type and Treatment Delivery Type match PS3.6 2026a")
    func testD35RadiationTherapyTags() {
        #expect(Tag.dvhVolumeUnits == Tag(group: 0x3004, element: 0x0054))
        #expect(Tag.highDoseTechniqueType == Tag(group: 0x300A, element: 0x00C7))
        #expect(Tag.treatmentDeliveryType == Tag(group: 0x300A, element: 0x00CE))
    }
}
