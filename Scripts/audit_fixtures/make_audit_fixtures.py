#!/usr/bin/env python3
"""Build foreign-toolkit (pydicom) fixtures that exercise every tag corrected by the
DICOM tag audit. Each file carries the attribute at its PS3.6 tag, so DICOMKit can only
read it back correctly if the constant is right.

Usage:  python3 Scripts/audit_fixtures/make_audit_fixtures.py [out_dir]
Needs:  pip install pydicom numpy
"""
import sys, os
import numpy as np
import pydicom
from pydicom.dataset import Dataset, FileDataset, FileMetaDataset
from pydicom.sequence import Sequence
from pydicom.uid import ExplicitVRLittleEndian, generate_uid

OUT = sys.argv[1] if len(sys.argv) > 1 else "audit_fixtures"
os.makedirs(OUT, exist_ok=True)

def new_file(name, sop_class, modality):
    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID = sop_class
    meta.MediaStorageSOPInstanceUID = generate_uid()
    meta.TransferSyntaxUID = ExplicitVRLittleEndian
    ds = FileDataset(name, {}, file_meta=meta, preamble=b"\0" * 128)
    ds.SOPClassUID = sop_class
    ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
    ds.StudyInstanceUID = generate_uid()
    ds.SeriesInstanceUID = generate_uid()
    ds.PatientName = "Audit^Fixture"; ds.PatientID = "AUDIT1"
    ds.Modality = modality; ds.InstanceNumber = 1; ds.SeriesNumber = 1
    return ds

def code(value, scheme, meaning):
    c = Dataset(); c.CodeValue = value; c.CodingSchemeDesignator = scheme; c.CodeMeaning = meaning
    return c

def save(ds, name):
    path = os.path.join(OUT, name)
    ds.save_as(path, write_like_original=False)
    print("wrote", path)

# ---------------------------------------------------------------- 1. Hanging Protocol
ds = new_file("hp.dcm", "1.2.840.10008.5.1.4.38.1", "PR")
ds.HangingProtocolName = "Audit CT Chest"
ds.HangingProtocolDescription = "Foreign-toolkit HP for tag audit"
ds.HangingProtocolLevel = "SITE"
ds.HangingProtocolCreator = "pydicom"
ds.HangingProtocolCreationDateTime = "20260919120000"
ds.HangingProtocolUserGroupName = "AuditRadiologists"          # (0072,0010)
ds.NumberOfPriorsReferenced = 2                                 # (0072,0014)
d = Dataset(); d.Modality = "CT"; d.Laterality = "L"
ds.HangingProtocolDefinitionSequence = Sequence([d])            # (0072,000C)
sel = Dataset()
sel.ImageSetSelectorUsageFlag = "MATCH"                         # (0072,0024)
sel.SelectorAttribute = 0x00080060                              # (0072,0026) Modality
sel.SelectorValueNumber = 1                                     # (0072,0028)
sel.SelectorAttributeVR = "CS"                                  # (0072,0050)
sel.SelectorCSValue = "CT"                                      # (0072,0062)
sel2 = Dataset()
sel2.ImageSetSelectorUsageFlag = "MATCH"
sel2.SelectorAttribute = 0x00280010                             # Rows
sel2.SelectorValueNumber = 1
sel2.SelectorAttributeVR = "US"
sel2.SelectorUSValue = 512                                      # (0072,007A)
ts = Dataset(); ts.ImageSetNumber = 1; ts.ImageSetLabel = "Current"
img = Dataset()
img.ImageSetSelectorSequence = Sequence([sel, sel2])            # (0072,0022)
img.TimeBasedImageSetsSequence = Sequence([ts])
ds.ImageSetsSequence = Sequence([img])
ds.NumberOfScreens = 1
scr = Dataset(); scr.NumberOfVerticalPixels = 1080; scr.NumberOfHorizontalPixels = 1920
scr.DisplayEnvironmentSpatialPosition = [0.0, 1.0, 1.0, 0.0]
ds.NominalScreenDefinitionSequence = Sequence([scr])
dsp = Dataset(); dsp.DisplaySetNumber = 1; dsp.ImageSetNumber = 1
dsp.DisplaySetPresentationGroup = 1
box = Dataset(); box.ImageBoxNumber = 1; box.DisplayEnvironmentSpatialPosition = [0.0, 1.0, 1.0, 0.0]
box.ImageBoxLayoutType = "TILED"; box.ImageBoxTileHorizontalDimension = 2; box.ImageBoxTileVerticalDimension = 2
dsp.ImageBoxesSequence = Sequence([box])
ds.DisplaySetsSequence = Sequence([dsp])
save(ds, "hp.dcm")

# ---------------------------------------------------------------- 2. RT Plan (brachy)
ds = new_file("rtplan.dcm", "1.2.840.10008.5.1.4.1.1.481.5", "RTPLAN")
ds.RTPlanLabel = "AuditBrachy"; ds.RTPlanDate = "20260919"; ds.RTPlanTime = "120000"
ds.RTPlanGeometry = "TREATMENT_DEVICE"
setup = Dataset()
setup.ApplicationSetupType = "FLETCHER_SUIT"                    # (300A,0232)
setup.ApplicationSetupNumber = 7                                # (300A,0234)
setup.ApplicationSetupName = "Tandem and ovoids"
setup.TotalReferenceAirKerma = 123.4
ds.ApplicationSetupSequence = Sequence([setup])                 # (300A,0230)
ds.BrachyTreatmentTechnique = "INTRACAVITARY"; ds.BrachyTreatmentType = "HDR"
save(ds, "rtplan.dcm")

# ---------------------------------------------------------------- 3. RT Structure Set (elemental composition)
ds = new_file("rtstruct.dcm", "1.2.840.10008.5.1.4.1.1.481.3", "RTSTRUCT")
ds.StructureSetLabel = "AuditSS"; ds.StructureSetDate = "20260919"; ds.StructureSetTime = "120000"
roi = Dataset(); roi.ROINumber = 1; roi.ROIName = "Water"; roi.ReferencedFrameOfReferenceUID = generate_uid()
roi.ROIGenerationAlgorithm = "MANUAL"
ds.StructureSetROISequence = Sequence([roi])
obs = Dataset(); obs.ObservationNumber = 1; obs.ReferencedROINumber = 1; obs.RTROIInterpretedType = "ORGAN"
obs.ROIInterpreter = ""
el = Dataset(); el.ROIElementalCompositionAtomicNumber = 8; el.ROIElementalCompositionAtomicMassFraction = 0.888
el2 = Dataset(); el2.ROIElementalCompositionAtomicNumber = 1; el2.ROIElementalCompositionAtomicMassFraction = 0.112
obs.ROIElementalCompositionSequence = Sequence([el, el2])       # (3006,00B6)
ds.RTROIObservationsSequence = Sequence([obs])
save(ds, "rtstruct.dcm")

# ---------------------------------------------------------------- 4. 12-lead ECG waveform with annotation
ds = new_file("ecg.dcm", "1.2.840.10008.5.1.4.1.1.9.1.1", "ECG")
ds.ContentDate = "20260919"; ds.ContentTime = "120000"
ds.AcquisitionDateTime = "20260919120000"
ds.AcquisitionTimeSynchronized = "N"                            # (0018,1800)
chan = Dataset()
chan.ChannelSourceSequence = Sequence([code("2:1", "MDC", "Lead I")])
chan.ChannelSensitivity = 1.0
chan.ChannelSensitivityUnitsSequence = Sequence([code("uV", "UCUM", "microvolt")])
chan.ChannelSensitivityCorrectionFactor = 1.0; chan.ChannelBaseline = 0.0
chan.ChannelTimeSkew = 0.0; chan.WaveformBitsStored = 16
mg = Dataset()
mg.WaveformOriginality = "ORIGINAL"; mg.NumberOfWaveformChannels = 1
mg.NumberOfWaveformSamples = 100; mg.SamplingFrequency = 500.0
mg.MultiplexGroupLabel = "Audit"
mg.ChannelDefinitionSequence = Sequence([chan])
mg.WaveformBitsAllocated = 16; mg.WaveformSampleInterpretation = "SS"
mg.WaveformData = (np.sin(np.linspace(0, 6.28, 100)) * 1000).astype(np.int16).tobytes()
mg.TriggerSamplePosition = 25                                   # (0018,106E)
mg.WaveformDataDisplayScale = 10.0                              # (003A,0230) FL
ds.WaveformSequence = Sequence([mg])
ann = Dataset()
ann.UnformattedTextValue = "Sinus rhythm, audit annotation"     # (0070,0006)
ann.AnnotationGroupNumber = 1                                   # (0040,A180)
ann.ReferencedWaveformChannels = [1, 1]                         # (0040,A0B0)
ann.TemporalRangeType = "POINT"; ann.ReferencedSamplePositions = [25]
ds.WaveformAnnotationSequence = Sequence([ann])                 # (0040,B020)
save(ds, "ecg.dcm")

# ---------------------------------------------------------------- 5. Enhanced MR: RWV LUT form + segmented k-space traversal
def enhanced(name, sop, modality, frames=2):
    ds = new_file(name, sop, modality)
    ds.Rows = ds.Columns = 8; ds.NumberOfFrames = frames
    ds.SamplesPerPixel = 1; ds.PhotometricInterpretation = "MONOCHROME2"
    ds.BitsAllocated = ds.BitsStored = 16; ds.HighBit = 15; ds.PixelRepresentation = 0
    ds.PixelData = np.tile(np.arange(64, dtype=np.uint16), frames).tobytes()
    ds.ImageType = ["ORIGINAL", "PRIMARY", "M", "NONE"]
    ds.FrameIncrementPointer = 0x00209111
    return ds
ds = enhanced("enhanced_mr.dcm", "1.2.840.10008.5.1.4.1.1.4.1", "MR")
rwv = Dataset()
rwv.LUTLabel = "ADC Mapping"                                    # (0040,9210)
rwv.LUTExplanation = "Apparent Diffusion Coefficient"           # (0028,3003)
rwv.MeasurementUnitsCodeSequence = Sequence([code("mm2/s", "UCUM", "square millimeter per second")])
rwv.QuantityDefinitionSequence = Sequence([code("113041", "DCM", "Apparent Diffusion Coefficient")])
rwv.RealWorldValueFirstValueMapped = 0                          # (0040,9216) US
rwv.RealWorldValueLastValueMapped = 63                          # (0040,9211) US
rwv.RealWorldValueLUTData = [i * 0.001 for i in range(64)]      # (0040,9212) FD
mr = Dataset()
mr.SegmentedKSpaceTraversal = "SINGLE"                          # (0018,9033)
mr.EchoTrainLength = 1
sfg = Dataset()
sfg.RealWorldValueMappingSequence = Sequence([rwv])
sfg.MRModifierSequence = Sequence([mr])
ds.SharedFunctionalGroupsSequence = Sequence([sfg])
pf = []
for i in range(2):
    item = Dataset(); fc = Dataset(); fc.DimensionIndexValues = [1, i + 1]; fc.StackID = "1"; fc.InStackPositionNumber = i + 1
    item.FrameContentSequence = Sequence([fc]); pf.append(item)
ds.PerFrameFunctionalGroupsSequence = Sequence(pf)
save(ds, "enhanced_mr.dcm")

# ---------------------------------------------------------------- 6. Enhanced PET: RWV with FD first/last (float pixel style)
ds = enhanced("enhanced_pet_fd.dcm", "1.2.840.10008.5.1.4.1.1.130", "PT")
rwv = Dataset()
rwv.LUTLabel = "SUVbw"; rwv.LUTExplanation = "Standardized Uptake Value body weight"
rwv.MeasurementUnitsCodeSequence = Sequence([code("g/ml", "UCUM", "g/ml")])
rwv.DoubleFloatRealWorldValueFirstValueMapped = 0.0             # (0040,9214)
rwv.DoubleFloatRealWorldValueLastValueMapped = 63.0             # (0040,9213)
rwv.RealWorldValueLUTData = [i * 0.5 for i in range(64)]
sfg = Dataset(); sfg.RealWorldValueMappingSequence = Sequence([rwv])
ds.SharedFunctionalGroupsSequence = Sequence([sfg])
save(ds, "enhanced_pet_fd.dcm")

# ---------------------------------------------------------------- 7. Parametric Map: linear RWV (FD slope/intercept)
ds = enhanced("pmap.dcm", "1.2.840.10008.5.1.4.1.1.30", "MR", frames=1)
ds.ContentLabel = "T1MAP"; ds.ContentDescription = "Audit parametric map"
ds.ContentQualification = "RESEARCH"
rwv = Dataset()
rwv.LUTLabel = "T1"; rwv.LUTExplanation = "T1 relaxation time"
rwv.MeasurementUnitsCodeSequence = Sequence([code("ms", "UCUM", "millisecond")])
rwv.QuantityDefinitionSequence = Sequence([code("113063", "DCM", "T1")])
rwv.RealWorldValueIntercept = 0.0                               # (0040,9224) FD
rwv.RealWorldValueSlope = 2.5                                   # (0040,9225) FD
sfg = Dataset(); sfg.RealWorldValueMappingSequence = Sequence([rwv])
ds.SharedFunctionalGroupsSequence = Sequence([sfg])
save(ds, "pmap.dcm")

# ---------------------------------------------------------------- 8. Multi-frame with Frame Dimension Pointer (0028,000A)
ds = enhanced("frame_dim_pointer.dcm", "1.2.840.10008.5.1.4.1.1.4.1", "MR")
ds.FrameDimensionPointer = [0x00209157]                         # (0028,000A) AT
save(ds, "frame_dim_pointer.dcm")

# ---------------------------------------------------------------- 9. Comprehensive SR with Mapping Resource UID/Name
ds = new_file("sr_mapping_resource.dcm", "1.2.840.10008.5.1.4.1.1.88.33", "SR")
ds.ContentDate = "20260919"; ds.ContentTime = "120000"; ds.CompletionFlag = "COMPLETE"; ds.VerificationFlag = "UNVERIFIED"
ds.ValueType = "CONTAINER"; ds.ContinuityOfContent = "SEPARATE"
name = code("126000", "DCM", "Imaging Measurement Report")
ds.ConceptNameCodeSequence = Sequence([name])
tmpl = Dataset(); tmpl.MappingResource = "DCMR"; tmpl.TemplateIdentifier = "1500"
tmpl.MappingResourceUID = "1.2.840.10008.8.1.1"                # (0008,0118)
tmpl.MappingResourceName = "DICOM Content Mapping Resource"    # (0008,0122)
ds.ContentTemplateSequence = Sequence([tmpl])
txt = Dataset(); txt.RelationshipType = "CONTAINS"; txt.ValueType = "TEXT"
txt.ConceptNameCodeSequence = Sequence([code("121106", "DCM", "Comment")]); txt.TextValue = "audit"
ds.ContentSequence = Sequence([txt])
save(ds, "sr_mapping_resource.dcm")
print("done")
