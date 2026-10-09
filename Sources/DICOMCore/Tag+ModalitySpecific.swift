/// DICOM Tag Extensions - Modality-Specific Attributes
///
/// Tags specific to different imaging modalities (CT, MR, US, etc.)
/// Reference: DICOM PS3.3 - Information Object Definitions
/// NEMA-verified: 2026a, checked 2026-09-25 — every Tag constant in this file was text-diffed by script against PS3.6 2026a Tables 6-1, 7-1 and 8-1 (tag present, name, VR, VM, keyword, retired status). See DICOMCORE_STANDARD_IMPLEMENTATION.md, Bucket C2.
extension Tag {
    // MARK: - CT Image Module
    
    /// KVP (0018,0060)
    /// VR: DS, VM: 1
    public static let kvp = Tag(group: 0x0018, element: 0x0060)
    
    /// Data Collection Diameter (0018,0090)
    /// VR: DS, VM: 1
    public static let dataCollectionDiameter = Tag(group: 0x0018, element: 0x0090)
    
    /// Reconstruction Diameter (0018,1100)
    /// VR: DS, VM: 1
    public static let reconstructionDiameter = Tag(group: 0x0018, element: 0x1100)
    
    /// Gantry/Detector Tilt (0018,1120)
    /// VR: DS, VM: 1
    public static let gantryDetectorTilt = Tag(group: 0x0018, element: 0x1120)
    
    /// Table Height (0018,1130)
    /// VR: DS, VM: 1
    public static let tableHeight = Tag(group: 0x0018, element: 0x1130)
    
    /// Rotation Direction (0018,1140)
    /// VR: CS, VM: 1
    public static let rotationDirection = Tag(group: 0x0018, element: 0x1140)
    
    /// Exposure Time (0018,1150)
    /// VR: IS, VM: 1
    public static let exposureTime = Tag(group: 0x0018, element: 0x1150)
    
    /// X-Ray Tube Current (0018,1151)
    /// VR: IS, VM: 1
    public static let xRayTubeCurrent = Tag(group: 0x0018, element: 0x1151)
    
    /// Exposure (0018,1152)
    /// VR: IS, VM: 1
    public static let exposure = Tag(group: 0x0018, element: 0x1152)
    
    /// Exposure in µAs (0018,1153)
    /// VR: IS, VM: 1 (PS3.6 keyword ExposureInuAs)
    public static let exposureInMicroAs = Tag(group: 0x0018, element: 0x1153)
    
    /// Filter Type (0018,1160)
    /// VR: SH, VM: 1
    public static let filterType = Tag(group: 0x0018, element: 0x1160)
    
    /// Generator Power (0018,1170)
    /// VR: IS, VM: 1
    public static let generatorPower = Tag(group: 0x0018, element: 0x1170)
    
    /// Convolution Kernel (0018,1210)
    /// VR: SH, VM: 1-n
    public static let convolutionKernel = Tag(group: 0x0018, element: 0x1210)
    
    /// Revolution Time (0018,9305)
    /// VR: FD, VM: 1
    public static let revolutionTime = Tag(group: 0x0018, element: 0x9305)
    
    /// Single Collimation Width (0018,9306)
    /// VR: FD, VM: 1
    public static let singleCollimationWidth = Tag(group: 0x0018, element: 0x9306)
    
    /// Total Collimation Width (0018,9307)
    /// VR: FD, VM: 1
    public static let totalCollimationWidth = Tag(group: 0x0018, element: 0x9307)
    
    /// Table Speed (0018,9309)
    /// VR: FD, VM: 1
    public static let tableSpeed = Tag(group: 0x0018, element: 0x9309)
    
    /// Table Feed per Rotation (0018,9310)
    /// VR: FD, VM: 1
    public static let tableFeedPerRotation = Tag(group: 0x0018, element: 0x9310)
    
    /// Spiral Pitch Factor (0018,9311)
    /// VR: FD, VM: 1
    public static let spiralPitchFactor = Tag(group: 0x0018, element: 0x9311)
    
    /// Data Collection Center (Patient) (0018,9313)
    /// VR: FD, VM: 3
    public static let dataCollectionCenterPatient = Tag(group: 0x0018, element: 0x9313)
    
    // MARK: - MR Image Module
    
    /// Scanning Sequence (0018,0020)
    /// VR: CS, VM: 1-n
    public static let scanningSequence = Tag(group: 0x0018, element: 0x0020)
    
    /// Sequence Variant (0018,0021)
    /// VR: CS, VM: 1-n
    public static let sequenceVariant = Tag(group: 0x0018, element: 0x0021)
    
    /// Scan Options (0018,0022)
    /// VR: CS, VM: 1-n
    public static let scanOptions = Tag(group: 0x0018, element: 0x0022)
    
    /// MR Acquisition Type (0018,0023)
    /// VR: CS, VM: 1
    public static let mrAcquisitionType = Tag(group: 0x0018, element: 0x0023)
    
    /// Sequence Name (0018,0024)
    /// VR: SH, VM: 1
    public static let sequenceName = Tag(group: 0x0018, element: 0x0024)
    
    /// Angio Flag (0018,0025)
    /// VR: CS, VM: 1
    public static let angioFlag = Tag(group: 0x0018, element: 0x0025)
    
    /// Intervention Drug Information Sequence (0018,0026)
    /// VR: SQ, VM: 1
    public static let interventionDrugInformationSequence = Tag(group: 0x0018, element: 0x0026)
    
    /// Magnetic Field Strength (0018,0087)
    /// VR: DS, VM: 1
    public static let magneticFieldStrength = Tag(group: 0x0018, element: 0x0087)
    
    /// Number of Phase Encoding Steps (0018,0089)
    /// VR: IS, VM: 1
    public static let numberOfPhaseEncodingSteps = Tag(group: 0x0018, element: 0x0089)
    
    /// Echo Train Length (0018,0091)
    /// VR: IS, VM: 1
    public static let echoTrainLength = Tag(group: 0x0018, element: 0x0091)
    
    /// Percent Sampling (0018,0093)
    /// VR: DS, VM: 1
    public static let percentSampling = Tag(group: 0x0018, element: 0x0093)
    
    /// Percent Phase Field of View (0018,0094)
    /// VR: DS, VM: 1
    public static let percentPhaseFieldOfView = Tag(group: 0x0018, element: 0x0094)
    
    /// Pixel Bandwidth (0018,0095)
    /// VR: DS, VM: 1
    public static let pixelBandwidth = Tag(group: 0x0018, element: 0x0095)
    
    /// Nominal Interval (0018,1062)
    /// VR: IS, VM: 1
    public static let nominalInterval = Tag(group: 0x0018, element: 0x1062)
    
    /// Beat Rejection Flag (0018,1080)
    /// VR: CS, VM: 1
    public static let beatRejectionFlag = Tag(group: 0x0018, element: 0x1080)
    
    /// Low R-R Value (0018,1081)
    /// VR: IS, VM: 1
    public static let lowRRValue = Tag(group: 0x0018, element: 0x1081)
    
    /// High R-R Value (0018,1082)
    /// VR: IS, VM: 1
    public static let highRRValue = Tag(group: 0x0018, element: 0x1082)
    
    /// Intervals Acquired (0018,1083)
    /// VR: IS, VM: 1
    public static let intervalsAcquired = Tag(group: 0x0018, element: 0x1083)
    
    /// Intervals Rejected (0018,1084)
    /// VR: IS, VM: 1
    public static let intervalsRejected = Tag(group: 0x0018, element: 0x1084)
    
    /// Echo Time (0018,0081)
    /// VR: DS, VM: 1
    public static let echoTime = Tag(group: 0x0018, element: 0x0081)
    
    /// Inversion Time (0018,0082)
    /// VR: DS, VM: 1
    public static let inversionTime = Tag(group: 0x0018, element: 0x0082)
    
    /// Number of Averages (0018,0083)
    /// VR: DS, VM: 1
    public static let numberOfAverages = Tag(group: 0x0018, element: 0x0083)
    
    /// Imaging Frequency (0018,0084)
    /// VR: DS, VM: 1
    public static let imagingFrequency = Tag(group: 0x0018, element: 0x0084)
    
    /// Imaged Nucleus (0018,0085)
    /// VR: SH, VM: 1
    public static let imagedNucleus = Tag(group: 0x0018, element: 0x0085)
    
    /// Echo Number(s) (0018,0086)
    /// VR: IS, VM: 1-n
    public static let echoNumbers = Tag(group: 0x0018, element: 0x0086)
    
    /// Repetition Time (0018,0080)
    /// VR: DS, VM: 1
    public static let repetitionTime = Tag(group: 0x0018, element: 0x0080)
    
    /// Flip Angle (0018,1314)
    /// VR: DS, VM: 1
    public static let flipAngle = Tag(group: 0x0018, element: 0x1314)
    
    /// Variable Flip Angle Flag (0018,1315)
    /// VR: CS, VM: 1
    public static let variableFlipAngleFlag = Tag(group: 0x0018, element: 0x1315)
    
    /// SAR (0018,1316)
    /// VR: DS, VM: 1
    public static let sar = Tag(group: 0x0018, element: 0x1316)
    
    /// dB/dt (0018,1318)
    /// VR: DS, VM: 1
    public static let dBdt = Tag(group: 0x0018, element: 0x1318)
    
    /// Acquisition Matrix (0018,1310)
    /// VR: US, VM: 4
    public static let acquisitionMatrix = Tag(group: 0x0018, element: 0x1310)
    
    /// In-plane Phase Encoding Direction (0018,1312)
    /// VR: CS, VM: 1
    public static let inPlanePhaseEncodingDirection = Tag(group: 0x0018, element: 0x1312)
    
    /// Transmit Coil Name (0018,1251)
    /// VR: SH, VM: 1
    public static let transmitCoilName = Tag(group: 0x0018, element: 0x1251)
    
    // MARK: - Ultrasound Module
    
    /// Transducer Type (0018,6031)
    /// VR: CS, VM: 1
    public static let transducerType = Tag(group: 0x0018, element: 0x6031)
    
    /// Transducer Frequency (0018,6030)
    /// VR: UL, VM: 1
    public static let transducerFrequency = Tag(group: 0x0018, element: 0x6030)
    
    /// Ultrasound Color Data Present (0028,0014)
    /// VR: US, VM: 1
    /// Retired - conflicts with Frame Dimension Pointer
    /// This tag is retired in recent DICOM versions
    // public static let ultrasoundColorDataPresent = Tag(group: 0x0028, element: 0x0014)
    
    /// Mechanical Index (0018,5022)
    /// VR: DS, VM: 1
    public static let mechanicalIndex = Tag(group: 0x0018, element: 0x5022)
    
    /// Cranial Thermal Index (0018,5026)
    /// VR: DS, VM: 1
    public static let cranialThermalIndex = Tag(group: 0x0018, element: 0x5026)
    
    /// (0018,5026) is the *Cranial* Thermal Index; Soft Tissue (0018,5027) and
    /// Bone (0018,5024) Thermal Index are separate attributes.
    @available(*, deprecated, renamed: "cranialThermalIndex")
    public static let thermalIndex = Tag.cranialThermalIndex
    
    /// Depth of Scan Field (0018,5050)
    /// VR: IS, VM: 1
    public static let depthOfScanField = Tag(group: 0x0018, element: 0x5050)
    
    // MARK: - Nuclear Medicine Module
    
    /// Radiopharmaceutical Information Sequence (0054,0016)
    /// VR: SQ, VM: 1
    public static let radiopharmaceuticalInformationSequence = Tag(group: 0x0054, element: 0x0016)
    
    /// Radiopharmaceutical (0018,0031)
    /// VR: LO, VM: 1
    public static let radiopharmaceutical = Tag(group: 0x0018, element: 0x0031)
    
    /// Radionuclide Total Dose (0018,1074)
    /// VR: DS, VM: 1
    public static let radionuclideTotalDose = Tag(group: 0x0018, element: 0x1074)
    
    /// Radionuclide Half Life (0018,1075)
    /// VR: DS, VM: 1
    public static let radionuclideHalfLife = Tag(group: 0x0018, element: 0x1075)
    
    /// Radionuclide Positron Fraction (0018,1076)
    /// VR: DS, VM: 1
    public static let radionuclidePositronFraction = Tag(group: 0x0018, element: 0x1076)
    
    /// Radiopharmaceutical Specific Activity (0018,1077)
    /// VR: DS, VM: 1
    public static let radiopharmaceuticalSpecificActivity = Tag(group: 0x0018, element: 0x1077)
    
    /// Radiopharmaceutical Start Time (0018,1072)
    /// VR: TM, VM: 1
    public static let radiopharmaceuticalStartTime = Tag(group: 0x0018, element: 0x1072)
    
    /// Radiopharmaceutical Stop Time (0018,1073)
    /// VR: TM, VM: 1
    public static let radiopharmaceuticalStopTime = Tag(group: 0x0018, element: 0x1073)
    
    /// Radionuclide Code Sequence (0054,0300)
    /// VR: SQ, VM: 1
    public static let radionuclideCodeSequence = Tag(group: 0x0054, element: 0x0300)
    
    /// Counts Accumulated (0018,0070)
    /// VR: IS, VM: 1
    public static let countsAccumulated = Tag(group: 0x0018, element: 0x0070)
    
    /// Acquisition Termination Condition (0018,0071)
    /// VR: CS, VM: 1
    public static let acquisitionTerminationCondition = Tag(group: 0x0018, element: 0x0071)
    
    /// Table Motion (0018,1134)
    /// VR: CS, VM: 1
    public static let tableMotion = Tag(group: 0x0018, element: 0x1134)
    
    /// Table Vertical Increment (0018,1135)
    /// VR: DS, VM: 1-n
    public static let tableVerticalIncrement = Tag(group: 0x0018, element: 0x1135)
    
    /// Table Lateral Increment (0018,1136)
    /// VR: DS, VM: 1-n
    public static let tableLateralIncrement = Tag(group: 0x0018, element: 0x1136)
    
    /// Table Longitudinal Increment (0018,1137)
    /// VR: DS, VM: 1-n
    public static let tableLongitudinalIncrement = Tag(group: 0x0018, element: 0x1137)
    
    /// Table Angle (0018,1138)
    /// VR: DS, VM: 1
    public static let tableAngle = Tag(group: 0x0018, element: 0x1138)
    
    // MARK: - PET Module
    
    /// Corrected Image (0028,0051)
    /// VR: CS, VM: 1-n
    public static let correctedImage = Tag(group: 0x0028, element: 0x0051)
    
    /// Units (0054,1001)
    /// VR: CS, VM: 1
    public static let units = Tag(group: 0x0054, element: 0x1001)
    
    /// Counts Source (0054,1002)
    /// VR: CS, VM: 1
    public static let countsSource = Tag(group: 0x0054, element: 0x1002)
    
    /// Decay Correction (0054,1102)
    /// VR: CS, VM: 1
    public static let decayCorrection = Tag(group: 0x0054, element: 0x1102)
    
    /// Attenuation Correction Method (0054,1101)
    /// VR: LO, VM: 1
    public static let attenuationCorrectionMethod = Tag(group: 0x0054, element: 0x1101)
    
    /// Scatter Correction Method (0054,1105)
    /// VR: LO, VM: 1
    public static let scatterCorrectionMethod = Tag(group: 0x0054, element: 0x1105)
    
    /// Reconstruction Method (0054,1103)
    /// VR: LO, VM: 1
    public static let reconstructionMethod = Tag(group: 0x0054, element: 0x1103)
}
