# Native SEG packing and calibration

Binary SEG frames form one continuous least-significant-bit-first stream. Do not
pad individual frames to byte boundaries. Only the complete Pixel Data value is
padded to an even byte length. For example, two 3×3 all-one frames encode as
`ff ff 03 00`. The extractor rejects overflowing or unavailable frame ranges.

`SegmentationBuilder.setPixelMeasures(PixelMeasures(pixelSpacing: [row, column],
sliceThickness: thickness, spacingBetweenSlices: distance))` stores shared
calibration in millimetres. `FunctionalGroup.pixelMeasures` also carries per-frame
calibration. The parser and writer preserve this macro, including when the writer
fills in missing dimension content. Supplied spacing must have two finite values;
zero spacing is permitted only for its corresponding singleton dimension.
Thickness must be positive and spacing between slices nonnegative when supplied.
Malformed DS values and Pixel Measures sequences with other than one item fail.

Absence remains absence: callers must supply required spatial attributes from
source geometry. Segmentation Storage with FrameOfReferenceUID requires Pixel
Spacing and Slice Thickness. This API does not infer those values or perform a
complete Segmentation IOD conformance assessment. Use validated `buildDataSet`
for export; the legacy `toDataSet` compatibility path remains unchecked.

References: [PS3.5 8.1.1](https://dicom.nema.org/medical/dicom/current/output/chtml/part05/chapter_8.html)
and [PS3.3 C.7.6.16.2.1](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.16.2.html).

Regression coverage uses independent byte fixtures, all eight frame bit offsets,
segment ordering, overflow/truncation checks and serialized shared/per-frame
calibration round trips. These checks do not establish application integration
or clinical acceptance.
