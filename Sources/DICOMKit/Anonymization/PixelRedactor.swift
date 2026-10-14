// NEMA-verified: 2026a, checked 2026-09-29 — Burned In Annotation and Code Sequence Macro citations checked against PS3.3 2026a
// NEMA-verified: 2026a, checked 2026-10-01 — Clean Recognizable Visual Features Option per PS3.15 2026a E.3.2 (operator-directed: "may require intervention of or approval by a human operator"): the operator's regions are blanked on every frame, Icon Image Sequence removed, Recognizable Visual Features (0028,0302) set to NO and CID 7050 113102 recorded only then; no regions refused (D159)
import Foundation
import DICOMCore

/// Blanks burned-in identifiers out of Pixel Data and records the PS3.15 attestation.
///
/// ## What "cleaned" means here
///
/// PS3.15 E.3 is explicit that the Clean Pixel Data Option requires the **actual pixel
/// values** to be altered. Obscuring with an overlay, a display shutter, or a
/// presentation-state graphic does not qualify — the identifying bytes remain in the
/// file. Nor does cropping (it changes the image geometry rather than blanking), nor
/// modifying JPEG coefficients in place (that blurs rather than blanks). This type
/// decodes to native samples, overwrites the region, and re-emits uncompressed.
///
/// ## The attestation is earned, not assumed
///
/// (0028,0301) Burned In Annotation → `NO` and DCM **113101** "Clean Pixel Data Option"
/// in (0012,0064) are written *only* when regions were actually blanked. No surveyed
/// toolkit does this: DCMTK defines 113101 as a string constant with no behaviour,
/// dcm4che has the option commented out, fo-dicom omits the sequence entirely.
/// Stamping it on a pass-through file would be the same false-confidence bug the
/// (0012,0062) guard exists to prevent.
public struct PixelRedactor {

    /// What a cleaned region shows afterwards. Every style shares one safety-critical
    /// mechanic — **blank-then-draw**: the whole region is filled first (that is what
    /// destroys the original glyphs); a stamp is drawn only into the already-blanked box.
    public enum Style: Sendable, Equatable {
        /// Fill value only.
        case blank
        /// A fixed stamp (default `REDACTED`).
        case label(String)
        /// Semantic replacement: the header engine's own anonymized value for the
        /// attribute that was matched (name → anonymized name, date → shifted date, ID →
        /// pseudonym). Regions without a truthful value get the fallback stamp.
        case replace(fallback: String)

        /// Parses `--redact-style` (`blank` | `label` | `replace`).
        public static func parse(_ raw: String, label: String?) -> Style? {
            switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
            case "blank": return .blank
            case "label": return .label(label ?? RedactionLabelRenderer.defaultLabel)
            case "replace": return .replace(fallback: label ?? RedactionLabelRenderer.defaultLabel)
            default: return nil
            }
        }

        public var name: String {
            switch self {
            case .blank: return "blank"
            case .label: return "label"
            case .replace: return "replace"
            }
        }
    }

    /// What a redaction run did, for the console and the audit trail.
    public struct Outcome: Sendable, Equatable {
        /// Regions actually blanked.
        public let regions: [PixelRedactionPlan.Region]
        /// How the regions were chosen.
        public let basis: PixelRedactionPlan.Basis
        /// Provenance detail (template note, or the derivation used).
        public let note: String
        /// Frames blanked — every frame is redacted, never just the first.
        public let frameCount: Int
        /// True when an Icon Image Sequence was removed rather than re-derived.
        public let removedIconImage: Bool
        /// True when overlay plane elements were removed.
        public let removedOverlays: Bool
        /// Style applied to the regions.
        public let style: Style
        /// Regions too small to carry a legible stamp — blanked only. Reported, never
        /// silent.
        public let labelFallbackRegions: [PixelRedactionPlan.Region]
        /// `replace` style: the value actually drawn into each replaced region.
        public let replacements: [PixelRedactionPlan.Region: String]
        /// `replace` style: why a region got the fallback stamp instead of a value.
        public let replacementFallbackNotes: [PixelRedactionPlan.Region: String]

        public init(
            regions: [PixelRedactionPlan.Region], basis: PixelRedactionPlan.Basis, note: String,
            frameCount: Int, removedIconImage: Bool, removedOverlays: Bool,
            style: Style = .blank, labelFallbackRegions: [PixelRedactionPlan.Region] = [],
            replacements: [PixelRedactionPlan.Region: String] = [:],
            replacementFallbackNotes: [PixelRedactionPlan.Region: String] = [:]
        ) {
            self.regions = regions
            self.basis = basis
            self.note = note
            self.frameCount = frameCount
            self.removedIconImage = removedIconImage
            self.removedOverlays = removedOverlays
            self.style = style
            self.labelFallbackRegions = labelFallbackRegions
            self.replacements = replacements
            self.replacementFallbackNotes = replacementFallbackNotes
        }
    }

    public init() {}

    /// Executes a plan against DICOM file bytes, returning redacted bytes.
    ///
    /// - Important: run this **before** header de-identification. The plan reads
    ///   Manufacturer / model / Modality to choose regions, and de-identification
    ///   removes those attributes. CTP and Presidio document the same dependency.
    ///
    /// - Returns: the redacted DICOM bytes and what was done, or `nil` when the plan
    ///   required no pixel work.
    /// - Throws: ``PixelRedactionError/unresolvedRegion(_:)`` when the plan could not
    ///   locate the burned-in content — a refusal, never a silent pass-through.
    /// Per-region semantic replacement input for the `replace` style: the text to
    /// draw, or a note explaining why nothing truthful can be drawn.
    public enum Replacement: Sendable, Equatable {
        case value(String)
        case unavailable(reason: String)
    }

    public func redact(
        fileData: Data,
        plan: PixelRedactionPlan,
        fillValue: Int? = nil,
        style: Style = .blank,
        replacements: [PixelRedactionPlan.Region: Replacement] = [:]
    ) throws -> (data: Data, outcome: Outcome)? {
        switch plan.decision {
        case .nothingToDo:
            return nil

        case .unresolved(let reason):
            throw PixelRedactionError.unresolvedRegion(reason)

        case .redact(let regions, let basis):
            return try apply(regions: regions, basis: basis, plan: plan,
                             to: fileData, fillValue: fillValue, style: style,
                             replacements: replacements)
        }
    }

    /// Clean Recognizable Visual Features Option (PS3.15 2026a E.3.2), operator-directed.
    ///
    /// E.3.2: "if there is sufficient visual information within the Pixel Data of a set of
    /// instances to allow an individual to be recognized from the instances themselves or a
    /// reconstruction of a set of instances, then sufficient removal or distortion of the
    /// Pixel Data shall be applied to prevent recognition. This may require intervention of
    /// or approval by a human operator." DICOMKit has no detector of recognizable features
    /// (faces, facial surfaces of head volumes), so the operator names the regions; their
    /// stored pixel values are blanked on every frame (as for Clean Pixel Data, an overlay
    /// or shutter would not do), the Icon Image Sequence, which shows the same features, is
    /// removed, Recognizable Visual Features (0028,0302) is set to "NO" ("shall be added to
    /// the Data Set with a Value of NO") and DCM 113102 "Clean Recognizable Visual Features
    /// Option" is appended to De-identification Method Code Sequence (0012,0064). Whether the
    /// regions are sufficient to prevent recognition is the operator's judgement.
    ///
    /// Burned In Annotation (0028,0301) and 113101 are not written: these regions are not a
    /// claim that burned-in text was removed (that is ``redact(fileData:plan:fillValue:)``).
    ///
    /// - Throws: ``PixelRedactionError/noRecognizableVisualFeatureRegions`` when `regions` is
    ///   empty — no pixels changed, so (0028,0302) NO and 113102 would be a false claim.
    public func redactRecognizableVisualFeatures(
        fileData: Data,
        regions: [PixelRedactionPlan.Region],
        fillValue: Int? = nil
    ) throws -> (data: Data, outcome: Outcome) {
        guard !regions.isEmpty else { throw PixelRedactionError.noRecognizableVisualFeatureRegions }
        let sourceFile = try DICOMFile.read(from: fileData)
        let frameCount = max(1, sourceFile.dataSet.numberOfFrames ?? 1)
        let operations = regions.map {
            PixelOperation.mask(x: $0.x, y: $0.y, width: $0.width, height: $0.height,
                                fillValue: fillValue ?? 0)
        }
        let (maskedData, _) = try PixelEditor(verbose: false)
            .processData(fileData, operations: operations, derivation: nil)
        var file = try DICOMFile.read(from: maskedData)
        var dataSet = file.dataSet
        let removedIcon = dataSet[.iconImageSequence] != nil
        if removedIcon { dataSet.remove(tag: .iconImageSequence) }
        dataSet.setString("NO", for: .recognizableVisualFeatures, vr: .CS)
        Self.appendMethodCode(.cleanRecognizableVisualFeaturesOption, to: &dataSet)
        file = DICOMFile(fileMetaInformation: file.fileMetaInformation, dataSet: dataSet)
        let outcome = Outcome(
            regions: regions, basis: .explicit,
            note: "operator-specified region (Clean Recognizable Visual Features Option, PS3.15 E.3.2)",
            frameCount: frameCount, removedIconImage: removedIcon, removedOverlays: false)
        return (try file.write(), outcome)
    }

    /// Appends a CID 7050 Item to (0012,0064) unless that Code Value is already recorded.
    private static func appendMethodCode(_ code: ConfidentialityProfile.DeidentificationMethodCode,
                                         to dataSet: inout DataSet) {
        var items = dataSet.sequence(for: Tag(group: 0x0012, element: 0x0064)) ?? []
        let recorded = items.contains {
            $0.string(for: .codeValue)?.trimmingCharacters(in: .whitespaces) == code.codeValue
        }
        guard !recorded else { return }
        items.append(code.sequenceItem)
        dataSet.setSequence(items, for: Tag(group: 0x0012, element: 0x0064))
    }

    // MARK: - Application

    private func apply(
        regions: [PixelRedactionPlan.Region],
        basis: PixelRedactionPlan.Basis,
        plan: PixelRedactionPlan,
        to fileData: Data,
        fillValue: Int?,
        style: Style,
        replacements: [PixelRedactionPlan.Region: Replacement]
    ) throws -> (data: Data, outcome: Outcome) {
        let sourceFile = try DICOMFile.read(from: fileData)
        let note = provenanceNote(plan: plan, basis: basis, dataSet: sourceFile.dataSet)
        let frameCount = max(1, sourceFile.dataSet.numberOfFrames ?? 1)

        // Blank via the shared PixelEditor so the CLI, Studio and this path run one
        // masking implementation. It decodes encapsulated sources to native samples
        // and masks the region on *every* frame.
        let editor = PixelEditor(verbose: false)
        let fill = fillValue ?? 0
        // Blank FIRST, always. Every region is filled before any stamp is drawn, so the
        // original glyphs are gone regardless of style — the stamp is cosmetic on top of
        // a completed redaction, and 113101 stays earned in every style.
        var operations = regions.map {
            PixelOperation.mask(x: $0.x, y: $0.y, width: $0.width, height: $0.height, fillValue: fill)
        }
        var fallback: [PixelRedactionPlan.Region] = []
        var drawn: [PixelRedactionPlan.Region: String] = [:]
        var fallbackNotes: [PixelRedactionPlan.Region: String] = [:]
        // What to stamp into each (already blanked) region, if anything.
        var stampText: [(PixelRedactionPlan.Region, String)] = []
        switch style {
        case .blank:
            break
        case .label(let text):
            stampText = regions.map { ($0, text) }
        case .replace(let fallbackLabel):
            for r in regions {
                switch replacements[r] {
                case .value(let value):
                    stampText.append((r, value))
                    drawn[r] = value
                case .unavailable(let reason):
                    stampText.append((r, fallbackLabel))
                    fallbackNotes[r] = reason
                case nil:
                    stampText.append((r, fallbackLabel))
                    fallbackNotes[r] = "no header-mapped value for this region (not a classified PHI match)"
                }
            }
        }
        if !stampText.isEmpty {
            guard RedactionLabelRenderer.isAvailable else {
                throw PixelRedactionError.labelUnavailable
            }
            let foreground = Self.contrastingStoredValue(to: fill, in: sourceFile.dataSet)
            for (r, text) in stampText {
                if let mask = RedactionLabelRenderer.glyphMask(text: text, width: r.width, height: r.height) {
                    operations.append(.stamp(x: r.x, y: r.y, width: r.width, height: r.height,
                                             glyphMask: mask, foregroundValue: foreground))
                } else {
                    fallback.append(r)   // too small to render legibly — blank only, audited
                    drawn[r] = nil
                    if case .replace = style {
                        fallbackNotes[r] = "region too small to render legibly — blanked"
                    }
                }
            }
        }
        // derivation: nil — redaction keeps the instance identity and must not write a
        // Source Image Sequence naming the identified original (the de-identification
        // profile decides the UIDs).
        let (maskedData, _) = try editor.processData(fileData, operations: operations, derivation: nil)

        // Re-read so the attestation is written onto the masked result.
        var file = try DICOMFile.read(from: maskedData)
        var dataSet = file.dataSet

        // Enhanced multiframe invariant: masking changes only Pixel Data and the
        // descriptor. NumberOfFrames must still equal the per-frame functional-group
        // count, and the functional groups must be byte-stable — never emit otherwise.
        try Self.checkFunctionalGroupInvariant(source: sourceFile.dataSet, result: dataSet)

        // A thumbnail derived before cleaning still shows the identifiers. PS3.15 notes
        // the icon may be cleaned or recreated; removing it is the safe option, since
        // re-deriving one here would need a render policy this type should not own.
        let removedIcon = dataSet[.iconImageSequence] != nil
        if removedIcon { dataSet.remove(tag: .iconImageSequence) }

        // Overlay planes are burned into the rendered image by viewers and the film
        // path, so identifying overlay graphics survive pixel masking. Remove the
        // plane elements outright (PS3.15 Clean Graphics territory).
        let removedOverlays = removeOverlayPlanes(from: &dataSet)

        recordAttestation(in: &dataSet)

        // The output is always Explicit VR Little Endian (§5.1/§5.4): PixelEditor already
        // re-targets encapsulated sources; native Implicit/BE and dataset-level Deflate
        // sources are re-pointed here so the syntax describes the emitted bytes.
        let fmi = PixelEditor.explicitLittleEndianFileMeta(from: file.fileMetaInformation)
        file = DICOMFile(fileMetaInformation: fmi, dataSet: dataSet)
        let outcome = Outcome(
            regions: regions, basis: basis, note: note, frameCount: frameCount,
            removedIconImage: removedIcon, removedOverlays: removedOverlays,
            style: style, labelFallbackRegions: fallback,
            replacements: drawn, replacementFallbackNotes: fallbackNotes)
        return (try file.write(), outcome)
    }

    /// Refuses to emit an Enhanced multiframe object whose functional groups no longer
    /// match its frames (PIXEL_ANONYMIZATION_PIPELINE.md §4.3 / §9).
    static func checkFunctionalGroupInvariant(source: DataSet, result: DataSet) throws {
        guard let perFrame = result.sequence(for: .perFrameFunctionalGroupsSequence) else { return }
        let frames = max(1, result.numberOfFrames ?? 1)
        guard perFrame.count == frames else {
            throw PixelRedactionError.functionalGroupMismatch(frames: frames, perFrameItems: perFrame.count)
        }
        let sourcePerFrame = source.sequence(for: .perFrameFunctionalGroupsSequence) ?? []
        let sourceShared = source.sequence(for: .sharedFunctionalGroupsSequence) ?? []
        let resultShared = result.sequence(for: .sharedFunctionalGroupsSequence) ?? []
        guard sourcePerFrame.count == perFrame.count, sourceShared.count == resultShared.count else {
            throw PixelRedactionError.functionalGroupMismatch(frames: frames, perFrameItems: perFrame.count)
        }
        func stable(_ a: [SequenceItem], _ b: [SequenceItem]) -> Bool {
            for (x, y) in zip(a, b) {
                let ex = x.allElements, ey = y.allElements
                guard ex.count == ey.count else { return false }
                for (p, q) in zip(ex, ey) where p.tag != q.tag || p.valueData != q.valueData { return false }
            }
            return true
        }
        guard stable(sourcePerFrame, perFrame), stable(sourceShared, resultShared) else {
            throw PixelRedactionError.functionalGroupsAltered
        }
    }

    /// The stored value farthest from `fill` within the image's representable range, so
    /// a stamp contrasts with its blanked background at the image's real bit depth
    /// (MONOCHROME1/2 alike — contrast, not "brightness", is what a reviewer needs).
    static func contrastingStoredValue(to fill: Int, in dataSet: DataSet) -> Int {
        let (lo, hi) = storedRange(in: dataSet)
        return (fill - lo) >= (hi - fill) ? lo : hi
    }

    /// The representable stored-value range at the image's Bits Stored / Pixel
    /// Representation — `hi` is what "white" means for this image.
    public static func storedRange(in dataSet: DataSet) -> (lo: Int, hi: Int) {
        let bitsStored = Int(dataSet.uint16(for: .bitsStored) ?? dataSet.uint16(for: .bitsAllocated) ?? 8)
        let signed = (dataSet.uint16(for: .pixelRepresentation) ?? 0) == 1
        let lo = signed ? -(1 << (bitsStored - 1)) : 0
        let hi = signed ? (1 << (bitsStored - 1)) - 1 : (1 << bitsStored) - 1
        return (lo, hi)
    }

    /// One note per contributing source when the plan unioned several; the single
    /// basis note otherwise.
    private func provenanceNote(
        plan: PixelRedactionPlan, basis: PixelRedactionPlan.Basis, dataSet: DataSet
    ) -> String {
        if plan.sources.count > 1 {
            return plan.sources
                .map { "\($0.basis.rawValue): \(provenanceNote(basis: $0.basis, count: $0.regions.count, dataSet: dataSet))" }
                .joined(separator: "; ")
        }
        return provenanceNote(basis: basis, count: plan.sources.first?.regions.count, dataSet: dataSet)
    }

    private func provenanceNote(
        basis: PixelRedactionPlan.Basis, count: Int?, dataSet: DataSet
    ) -> String {
        switch basis {
        case .explicit:
            return "caller-specified region"
        case .keepRegionInversion:
            return "inverted from Sequence of Ultrasound Regions (0018,6011) — "
                + "blanked everything outside the declared scan area"
        case .deviceTemplate:
            return DeviceRedactionTemplates.matchNote(for: dataSet) ?? "device template"
        case .textDetection:
            // Report what was done — never that the image is now clean (principle #9).
            let n = count.map { "\($0) region\($0 == 1 ? "" : "s")" } ?? "regions"
            return "OCR text detection (Vision, \(n))"
        }
    }

    /// Removes every overlay plane group (0x6000–0x601E, even), including the retired
    /// *embedded* form whose bits live in Pixel Data's high bits and which therefore has
    /// no (60xx,3000) element of its own.
    private func removeOverlayPlanes(from dataSet: inout DataSet) -> Bool {
        var removed = false
        for group in stride(from: UInt16(0x6000), through: UInt16(0x601E), by: 2) {
            let present = dataSet.tags.contains { $0.group == group }
            guard present else { continue }
            for tag in dataSet.tags where tag.group == group {
                dataSet.remove(tag: tag)
                removed = true
            }
        }
        return removed
    }

    /// Writes the PS3.15 record for work that actually happened.
    private func recordAttestation(in dataSet: inout DataSet) {
        // (0028,0301) — PS3.15 E.3: "shall be added to the Data Set with a Value of NO".
        dataSet.setString("NO", for: .burnedInAnnotation, vr: .CS)

        // (0012,0064) De-identification Method Code Sequence — append DCM 113101 rather
        // than replacing, so an item written by another pass survives.
        ConfidentialityProfile.MethodCode.record(.cleanPixelData, in: &dataSet)
    }
}

/// Errors from the pixel-redaction path.
public enum PixelRedactionError: Error, LocalizedError, Equatable {
    /// The image declares burned-in identifiers but no strategy located them.
    case unresolvedRegion(String)
    /// The Clean Recognizable Visual Features Option was asked for without a region to blank.
    case noRecognizableVisualFeatureRegions
    /// The `label` style needs glyph rasterization (CoreGraphics/CoreText), absent here.
    case labelUnavailable
    /// Enhanced multiframe: NumberOfFrames no longer equals the per-frame FG count.
    case functionalGroupMismatch(frames: Int, perFrameItems: Int)
    /// Enhanced multiframe: functional-group content changed during the rewrite.
    case functionalGroupsAltered
    /// `--recompress`: the redacted rects were not flat fill after the codec round-trip.
    case recompressVerificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .functionalGroupMismatch(let frames, let items):
            return "Refusing to write: Number of Frames (\(frames)) does not match the per-frame "
                + "functional group count (\(items)) after pixel redaction."
        case .functionalGroupsAltered:
            return "Refusing to write: functional groups changed during pixel redaction."
        case .recompressVerificationFailed(let detail):
            return "Refusing to write: redacted regions did not survive re-encoding as blank (\(detail))."
        case .labelUnavailable:
            return "The label redaction style needs CoreGraphics/CoreText, which is not available "
                + "on this platform. Use --redact-style blank."
        case .unresolvedRegion(let reason):
            return """
                Cannot determine which pixels to blank. \(reason)

                No caller-specified region was given, the data set declares no clinical \
                region to invert (e.g. Sequence of Ultrasound Regions), and no device \
                template matched this Modality/Manufacturer/model.

                Refusing rather than guessing: passing the file through unchanged would \
                leave the identifiers in place while the output looked de-identified.
                """
        case .noRecognizableVisualFeatureRegions:
            return """
                Clean Recognizable Visual Features Option (PS3.15 E.3.2) needs one or more \
                regions to blank: recognizable features are not detected automatically, and \
                Recognizable Visual Features (0028,0302) = NO with code 113102 is written only \
                when pixels were actually removed.
                """
        }
    }
}
