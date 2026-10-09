// NEMA-verified: 2026a, checked 2026-10-06 — lifted from Sources/dicom-pixedit/DerivedImage.swift (D270) so dicom-pixedit and the DICOMStudio CLI Workshop share one copy; re-checked against the DocBook: the stored sample range follows Bits Stored (0028,0101) and Pixel Representation (0028,0103) of the Image Pixel Module (PS3.3 2026a C.7.6.3.1, Table C.7-11c, Enumerated Values "0000H unsigned integer", "0001H 2's complement"), a --fill-value outside it is refused (P-PIXEDIT-RANGE); Window Width (0028,1051) below 1 is refused per PS3.3 2026a C.11.2.1.2 ("Window Width (0028,1051) shall always be greater than or equal to 1"); the Derived Image marking (C.7.6.1.1.2, Table C.12-10), the window in Modality LUT output units (C.11.2.1.2) and the crop geometry (C.7.6.2.1.1) are done by PixelEditor (D169-D174). Refusal texts unchanged.
//
// PixelEditInputChecks.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// The input checks `dicom-pixedit` (and the DICOMStudio CLI Workshop) apply before
/// the shared ``PixelEditor`` engine runs (P-PIXEDIT-RANGE refusals; the engine itself
/// clamps / throws). Lifted from the CLI (D270).
public enum PixelEditInputChecks {

    /// Range of a stored sample: Bits Stored (0028,0101) and Pixel Representation
    /// (0028,0103) of the Image Pixel Module (PS3.3 2026a C.7.6.3.1).
    public static func storedRange(bitsStored: Int, signed: Bool) -> ClosedRange<Int> {
        let bits = max(1, min(bitsStored, 32))
        return signed ? -(1 << (bits - 1)) ... (1 << (bits - 1)) - 1 : 0 ... (1 << bits) - 1
    }

    /// The stored range of a data set's Image Pixel Module; Bits Stored defaults to
    /// Bits Allocated (default 16) and Pixel Representation to 0 when absent.
    public static func storedRange(of dataSet: DataSet) -> ClosedRange<Int> {
        let allocated = Int(dataSet.uint16(for: .bitsAllocated) ?? 16)
        let stored = Int(dataSet.uint16(for: .bitsStored) ?? UInt16(allocated))
        let signed = (dataSet.uint16(for: .pixelRepresentation) ?? 0) == 1
        return storedRange(bitsStored: stored, signed: signed)
    }

    /// A refusal when `--fill-value` lies outside the stored range (P-PIXEDIT-RANGE,
    /// approved 2026-10-01: it was clamped with a warning); nil when it fits.
    public static func fillValueViolation(_ value: Int, range: ClosedRange<Int>) -> String? {
        guard !range.contains(value) else { return nil }
        return "--fill-value \(value) is outside the stored range \(range.lowerBound)...\(range.upperBound) "
            + "given by Bits Stored (0028,0101) and Pixel Representation (0028,0103) (PS3.3 C.7.6.3.1)"
    }

    /// A refusal when `--window-width` is below 1 (P-PIXEDIT-RANGE): PS3.3 2026a
    /// C.11.2.1.2 "Window Width (0028,1051) shall always be greater than or equal to 1"
    /// (it was raised to 1 with a warning, and a width <= 0 went to the engine).
    public static func windowWidthViolation(_ width: Double) -> String? {
        guard !(width >= 1) else { return nil }
        return "--window-width \(width) is below 1; Window Width (0028,1051) shall always be greater than "
            + "or equal to 1 (PS3.3 C.11.2.1.2)"
    }
}
