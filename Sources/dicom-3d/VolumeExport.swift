// NEMA-verified: 2026a, checked 2026-10-01 — DICOM side of the NIfTI / MetaImage export: the voxel-to-patient affine is PS3.3 2026a C.7.6.2.1.1 Equation C.7.6.2.1-1 with the LPS axes of that section (NIfTI sform converted to RAS by negating x and y; MetaImage keeps LPS), Pixel Spacing order of Table C.7-10, voxels already in Modality LUT output units (C.11.1.1.2) so no second rescale; NIfTI-1 / MetaIO header layouts are not DICOM and were not compared with the standard
import Foundation

// MARK: - Volume Export Extensions

extension VolumeData {
    /// Voxel-index → patient (LPS, mm) affine: columns are X·Δi, Y·Δj, N·Δk and the
    /// origin S (PS3.3 C.7.6.2.1.1 Equation C.7.6.2.1-1, extended along the normal).
    var lpsAffine: [[Double]] {
        let x = axisDirection(0).scaled(spacing.x)
        let y = axisDirection(1).scaled(spacing.y)
        let z = axisDirection(2).scaled(spacing.z)
        return [[x.x, y.x, z.x, origin.x],
                [x.y, y.y, z.y, origin.y],
                [x.z, y.z, z.z, origin.z]]
    }

    /// NIfTI sform rows: NIfTI's scanner space is RAS, DICOM's patient space LPS,
    /// so the first two rows change sign.
    var niftiSform: [[Float]] {
        let a = lpsAffine
        return [a[0].map { Float(-$0) }, a[1].map { Float(-$0) }, a[2].map { Float($0) }]
    }

    /// MetaImage TransformMatrix: the direction cosines of the three index axes, axis by axis.
    var metaImageTransformMatrix: [Double] {
        (0..<3).flatMap { axis -> [Double] in
            let d = axisDirection(axis)
            return [d.x, d.y, d.z]
        }
    }

    /// MetaImage AnatomicalOrientation: for each index axis, the patient side it
    /// runs *from* (ITK convention; "RAI" is the LPS identity).
    var metaImageAnatomicalOrientation: String {
        (0..<3).map { axis -> String in
            let d = axisDirection(axis)
            let components = [(abs(d.x), d.x >= 0 ? "R" : "L"),
                              (abs(d.y), d.y >= 0 ? "A" : "P"),
                              (abs(d.z), d.z >= 0 ? "I" : "S")]
            return components.max { $0.0 < $1.0 }!.1
        }.joined()
    }

    /// Export volume as NIfTI format (.nii)
    func exportNIfTI(to url: URL) throws {
        // NIfTI-1 header (348 bytes)
        var data = Data()
        
        // Header size (must be 348)
        var headerSize: Int32 = 348
        data.append(Data(bytes: &headerSize, count: 4))
        
        // data_type (unused, 10 bytes)
        data.append(Data(repeating: 0, count: 10))
        
        // db_name (unused, 18 bytes)
        data.append(Data(repeating: 0, count: 18))
        
        // extents (unused, 4 bytes)
        var extents: Int32 = 0
        data.append(Data(bytes: &extents, count: 4))
        
        // session_error (unused, 2 bytes)
        var sessionError: Int16 = 0
        data.append(Data(bytes: &sessionError, count: 2))
        
        // regular (unused, 1 byte)
        var regular: UInt8 = 0
        data.append(Data(bytes: &regular, count: 1))
        
        // dim_info (1 byte)
        var dimInfo: UInt8 = 0
        data.append(Data(bytes: &dimInfo, count: 1))
        
        // dim[8] - dimensions (16 bytes)
        let dims: [Int16] = [3, Int16(dimensions.width), Int16(dimensions.height), Int16(dimensions.depth), 1, 0, 0, 0]
        for i in 0..<8 {
            var d = dims[i]
            data.append(Data(bytes: &d, count: 2))
        }
        
        // intent_p1, intent_p2, intent_p3 (12 bytes)
        var intentP1: Float = 0
        var intentP2: Float = 0
        var intentP3: Float = 0
        data.append(Data(bytes: &intentP1, count: 4))
        data.append(Data(bytes: &intentP2, count: 4))
        data.append(Data(bytes: &intentP3, count: 4))
        
        // intent_code (2 bytes)
        var intentCode: Int16 = 0
        data.append(Data(bytes: &intentCode, count: 2))
        
        // datatype (2 bytes) - 16 = float32, 64 = float64
        var datatype: Int16 = 16 // float32
        data.append(Data(bytes: &datatype, count: 2))
        
        // bitpix (2 bytes)
        var bitpix: Int16 = 32
        data.append(Data(bytes: &bitpix, count: 2))
        
        // slice_start (2 bytes)
        var sliceStart: Int16 = 0
        data.append(Data(bytes: &sliceStart, count: 2))
        
        // pixdim[8] - pixel dimensions (32 bytes)
        let pixdims: [Float] = [-1.0, Float(spacing.x), Float(spacing.y), Float(spacing.z), 0, 0, 0, 0]
        for i in 0..<8 {
            var p = pixdims[i]
            data.append(Data(bytes: &p, count: 4))
        }
        
        // vox_offset (4 bytes) - offset to data (352 for .nii)
        var voxOffset: Float = 352.0
        data.append(Data(bytes: &voxOffset, count: 4))
        
        // scl_slope, scl_inter (8 bytes): the voxels already hold Rescale Slope /
        // Intercept output values (PS3.3 C.11.1.1.2), so the identity is written.
        var sclSlope: Float = 1
        var sclInter: Float = 0
        data.append(Data(bytes: &sclSlope, count: 4))
        data.append(Data(bytes: &sclInter, count: 4))
        
        // slice_end, slice_code, xyzt_units (4 bytes)
        var sliceEnd: Int16 = 0
        var sliceCode: UInt8 = 0
        var xyztUnits: UInt8 = 2 // mm for spatial
        data.append(Data(bytes: &sliceEnd, count: 2))
        data.append(Data(bytes: &sliceCode, count: 1))
        data.append(Data(bytes: &xyztUnits, count: 1))
        
        // cal_max, cal_min (8 bytes)
        var calMax: Float = Float(voxels.max() ?? 0)
        var calMin: Float = Float(voxels.min() ?? 0)
        data.append(Data(bytes: &calMax, count: 4))
        data.append(Data(bytes: &calMin, count: 4))
        
        // slice_duration, toffset (8 bytes)
        var sliceDuration: Float = 0
        var toffset: Float = 0
        data.append(Data(bytes: &sliceDuration, count: 4))
        data.append(Data(bytes: &toffset, count: 4))
        
        // glmax, glmin (unused, 8 bytes)
        var glmax: Int32 = 0
        var glmin: Int32 = 0
        data.append(Data(bytes: &glmax, count: 4))
        data.append(Data(bytes: &glmin, count: 4))
        
        // descrip (80 bytes)
        var descrip = "DICOMKit 3D Export".data(using: .utf8) ?? Data()
        descrip.append(Data(repeating: 0, count: 80 - descrip.count))
        data.append(descrip.prefix(80))
        
        // aux_file (24 bytes)
        data.append(Data(repeating: 0, count: 24))
        
        // qform_code, sform_code (2 bytes)
        var qformCode: Int16 = 0
        var sformCode: Int16 = 1 // scanner anatomical
        data.append(Data(bytes: &qformCode, count: 2))
        data.append(Data(bytes: &sformCode, count: 2))
        
        // quatern_b, quatern_c, quatern_d (12 bytes)
        var quaternB: Float = 0
        var quaternC: Float = 0
        var quaternD: Float = 0
        data.append(Data(bytes: &quaternB, count: 4))
        data.append(Data(bytes: &quaternC, count: 4))
        data.append(Data(bytes: &quaternD, count: 4))
        
        // qoffset_x, qoffset_y, qoffset_z (12 bytes)
        var qoffsetX: Float = Float(-origin.x)  // RAS
        var qoffsetY: Float = Float(-origin.y)  // RAS
        var qoffsetZ: Float = Float(origin.z)
        data.append(Data(bytes: &qoffsetX, count: 4))
        data.append(Data(bytes: &qoffsetY, count: 4))
        data.append(Data(bytes: &qoffsetZ, count: 4))
        
        // srow_x, srow_y, srow_z (48 bytes) - affine transform (RAS)
        let sform = niftiSform
        let srowX: [Float] = sform[0]
        let srowY: [Float] = sform[1]
        let srowZ: [Float] = sform[2]
        
        for i in 0..<4 {
            var x = srowX[i]
            data.append(Data(bytes: &x, count: 4))
        }
        for i in 0..<4 {
            var y = srowY[i]
            data.append(Data(bytes: &y, count: 4))
        }
        for i in 0..<4 {
            var z = srowZ[i]
            data.append(Data(bytes: &z, count: 4))
        }
        
        // intent_name (16 bytes)
        data.append(Data(repeating: 0, count: 16))
        
        // magic (4 bytes) - "n+1\0" for .nii
        let magic = "n+1\0".data(using: .utf8)!
        data.append(magic)
        
        // Pad to 352 bytes
        while data.count < 352 {
            data.append(0)
        }
        
        // Write voxel data as float32
        for voxel in voxels {
            var f = Float(voxel)
            data.append(Data(bytes: &f, count: 4))
        }
        
        try data.write(to: url)
    }
    
    /// Export volume as MetaImage format (.mhd + .raw)
    func exportMetaImage(to url: URL) throws {
        // Write .mhd header file
        var header = ""
        header += "ObjectType = Image\n"
        header += "NDims = 3\n"
        header += "BinaryData = True\n"
        header += "BinaryDataByteOrderMSB = False\n"
        header += "CompressedData = False\n"
        header += "TransformMatrix = \(metaImageTransformMatrix.map { String($0) }.joined(separator: " "))\n"
        header += "Offset = \(origin.x) \(origin.y) \(origin.z)\n"
        header += "CenterOfRotation = 0 0 0\n"
        header += "AnatomicalOrientation = \(metaImageAnatomicalOrientation)\n"
        header += "ElementSpacing = \(spacing.x) \(spacing.y) \(spacing.z)\n"
        header += "DimSize = \(dimensions.width) \(dimensions.height) \(dimensions.depth)\n"
        header += "ElementType = MET_DOUBLE\n"
        
        // Determine .raw filename
        let mhdURL = url
        let rawFilename = mhdURL.deletingPathExtension().appendingPathExtension("raw").lastPathComponent
        let rawURL = mhdURL.deletingLastPathComponent().appendingPathComponent(rawFilename)
        
        header += "ElementDataFile = \(rawFilename)\n"
        
        try header.write(to: mhdURL, atomically: true, encoding: .utf8)
        
        // Write .raw data file (binary doubles)
        var data = Data()
        for voxel in voxels {
            var d = voxel
            data.append(Data(bytes: &d, count: 8))
        }
        
        try data.write(to: rawURL)
    }
}
