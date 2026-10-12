import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

@main
struct DICOMAnon: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-anon",
        abstract: "De-identify DICOM files: PS3.15 Annex E Basic Profile, header and pixels",
        discussion: """
            Applies the DICOM PS3.15 Annex E Basic Application Level Confidentiality \
            Profile to every file — always. The standard's named retention options are \
            the only way to keep more, and its Clean Pixel Data option is on by default: \
            burned-in text is located (declared regions, device templates, on-device OCR) \
            and blanked out of the pixels themselves. The output records what was done in \
            (0012,0063)/(0012,0064).

            Burned In Annotation (0028,0301) policy: YES → pixels are cleaned; absent → \
            OCR decides; NO → the declaration is trusted and the pixels are left alone \
            (overlay planes or --redact-region override that trust).

            Examples:
              dicom-anon file.dcm --output anon.dcm
              dicom-anon file.dcm --output anon.dcm --shift-dates 100 --retain-characteristics
              dicom-anon study/ --output anon_study/ --recursive --audit-log anon.log --verbose
              dicom-anon file.dcm --dry-run                       (preview header + pixel plan)
              dicom-anon file.dcm --output anon.dcm --ocr-mode header --text-only --redact-fill white
              dicom-anon file.dcm --output anon.dcm --redact-region 0,0,1024,90 --recompress source
            """,
        version: "2.0.0"
    )

    @Argument(help: "Path to DICOM file or directory")
    var inputPath: String

    @Option(name: .shortAndLong, help: "Output file or directory path")
    var output: String?

    @Option(name: .long, help: "Remove an attribute by tag or keyword")
    var remove: [String] = []

    @Option(name: .long, help: "Replace an attribute using tag=value or keyword=value")
    var replace: [String] = []

    // ----- PS3.15 Annex E retention options -----
    @Flag(name: .long, help: "Retain Longitudinal Temporal Information With Full Dates Option: keep every date and time as-is")
    var retainDates: Bool = false

    @Option(name: .long, help: """
        Retain Longitudinal Temporal Information With Modified Dates Option: shift every date by \
        this many days (intervals survive, real dates do not). Alternative to --retain-dates.
        """)
    var shiftDates: Int?

    @Flag(name: .long, help: "Retain Patient Characteristics Option (age, sex, size, weight)")
    var retainCharacteristics: Bool = false

    @Flag(name: .long, help: "Retain Device Identity Option (manufacturer model, station name, serial number)")
    var retainDevice: Bool = false

    @Flag(name: .long, help: "Retain Institution Identity Option (institution name, address, department)")
    var retainInstitution: Bool = false

    @Flag(name: .long, help: "Retain UIDs Option: retain UIDs instead of regenerating them consistently")
    var retainUids: Bool = false

    @Flag(name: .long, help: "Clean Descriptors Option: remove identifying information from retained study/series descriptions and protocol text")
    var cleanDescriptors: Bool = false

    @Flag(name: .long, help: "Keep only private attributes declared safe")
    var retainSafePrivate: Bool = false

    @Flag(name: .long, help: "Remove identifying text from graphic annotations")
    var cleanGraphics: Bool = false

    @Flag(name: .long, help: "PS3.15 Clean Structured Content Option")
    var cleanStructuredContent: Bool = false

    @Flag(name: .long, help: "PS3.15 Clean Recognizable Visual Features Option: requires --redact-region")
    var cleanRecognizableVisualFeatures: Bool = false

    @Option(name: .long, help: "Basic Application Level Confidentiality Profile: ps315 (default) or basic")
    var profile: String = "ps315"

    @Flag(name: .long, help: "Retain Longitudinal Temporal Information with Full Dates (alias for --retain-dates)")
    var retainFullDates = false

    @Flag(name: .long, help: "Retain Longitudinal Temporal Information with Modified Dates; requires --shift-dates")
    var retainModifiedDates = false

    // ----- Clean Pixel Data option -----
    @Flag(name: .long, inversion: .prefixedNo, help: """
        Clean Pixel Data (default on): blank burned-in identifiers out of the image \
        itself, from the declared clinical region, the device template, on-device OCR \
        and any --redact-region, unioned. REFUSES rather than guessing when an image \
        declares burned-in text and no source can locate it. --no-clean-pixel-data \
        de-identifies the header only and refuses files whose pixels may still carry PHI.
        """)
    var cleanPixelData: Bool = true

    @Option(name: .long, help: "Region to blank as x,y,width,height (repeatable); unioned with the automatic sources")
    var redactRegion: [String] = []

    @Option(name: .long, help: """
        Fill for blanked pixels: black (default, stored value 0), white (the largest \
        stored value at the image's bit depth, resolved per file), or a stored pixel value.
        """)
    var redactFill: String?

    @Option(name: .long, help: """
        What a cleaned region shows: blank (fill value only, default), label (a fixed \
        stamp drawn INTO the already-blanked box), or replace (the header engine's own \
        de-identified value for the matched attribute — a shifted date, say — so pixels \
        and header tell one story; needs --ocr-mode classify or header; uncertain regions \
        and attributes the profile removes get the label instead).
        """)
    var redactStyle: String = "blank"

    @Option(name: .long, help: "Stamp text for --redact-style label (default: REDACTED)")
    var redactLabel: String?

    @Option(name: .long, help: """
        Re-encode the CLEAN pixels after redaction: 'source' mirrors the input transfer \
        syntax (lossless sources round-trip exactly outside the redacted regions; lossy \
        sources are re-quantized — second-generation loss, header ratio/method updated), \
        or any dicom-compress codec name (jpeg-ls, rle, jpeg2000-lossless, …). Without \
        this the output is Explicit VR Little Endian. The redacted regions are re-verified \
        blank after re-encoding.
        """)
    var recompress: String?

    @Option(name: .long, help: """
        OCR mode — the two differ in which way they fail. header redacts only text \
        matching the file's own PHI (names, IDs, dates, institution, physicians) or a \
        PHI-shaped pattern and keeps everything else — scales, legends and free \
        annotations survive; it FAILS OPEN (text the header never carried is not \
        recognised) and says so. classify (default) adds PHI keywords and redacts \
        anything not positively allowlisted (laterality, units, technique); it fails \
        closed. To erase an area whatever it reads, name it with --redact-region.
        """)
    var ocrMode: String = "classify"

    @Flag(name: .long, help: "OCR every frame instead of the first/middle/last sample")
    var ocrAllFrames: Bool = false

    @Flag(name: .long, help: """
        Blank only the text OCR flagged (and any --redact-region), at its exact position: \
        no automatic banner band from the declared Ultrasound Regions or the device \
        template. Pair with --ocr-mode header to remove exactly the study's own \
        identifiers, institution and dates. Drops the band safety net — text OCR misses \
        is kept, so verify visually before release.
        """)
    var textOnly: Bool = false

    @Flag(name: .long, help: """
        Proceed even when the pixels may still carry PHI (Burned In Annotation = YES with \
        --no-clean-pixel-data, overlay planes present, or OCR-detected text this run \
        leaves unredacted). Without this, such files are refused unwritten. The output is \
        marked Patient Identity Removed = NO.
        """)
    var allowBurnedInPHI: Bool = false

    // ----- Run control -----
    @Flag(name: .long, help: "Process directories recursively")
    var recursive: Bool = false

    @Flag(name: .long, help: "Preview changes (header and pixel plan) without modifying files")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Create backup of original files")
    var backup: Bool = false

    @Option(name: .long, help: "Path to audit log file (tags and actions, never values)")
    var auditLog: String?

    @Flag(name: .long, help: "Force parsing of files without DICM prefix")
    var force: Bool = false

    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false

    mutating func run() async throws {
        // Every input in the CLI's own vocabulary; parsing, validation, the
        // pixel-first ordering, the refusal contract and every console line live
        // in the shared workflow so DICOMStudio's CLI Workshop runs the same code.
        var request = AnonymizationWorkflow.Request(inputPath: inputPath)
        request.output = output
        request.remove = remove
        request.replace = replace
        guard ["ps315", "basic"].contains(profile) else {
            throw ValidationError("The OCR workflow supports --profile ps315 or basic. Legacy profiles are available through the library API only.")
        }
        guard !retainModifiedDates || (shiftDates != nil && !retainDates && !retainFullDates) else {
            throw ValidationError("--retain-modified-dates requires --shift-dates and cannot be combined with full-date retention.")
        }
        request.retainDates = retainDates || retainFullDates
        request.shiftDates = shiftDates
        request.retainCharacteristics = retainCharacteristics
        request.retainDevice = retainDevice
        request.retainInstitution = retainInstitution
        request.retainUids = retainUids
        request.cleanDescriptors = cleanDescriptors
        request.retainSafePrivate = retainSafePrivate
        request.cleanGraphics = cleanGraphics
        request.cleanStructuredContent = cleanStructuredContent
        request.cleanRecognizableVisualFeatures = cleanRecognizableVisualFeatures

        request.cleanPixelData = cleanPixelData
        request.redactRegion = redactRegion
        request.redactFill = redactFill
        request.redactStyle = redactStyle
        request.redactLabel = redactLabel
        request.recompress = recompress
        request.ocrMode = ocrMode
        request.ocrAllFrames = ocrAllFrames
        request.textOnly = textOnly
        request.allowBurnedInPHI = allowBurnedInPHI
        request.recursive = recursive
        request.dryRun = dryRun
        request.backup = backup
        request.auditLog = auditLog
        request.force = force
        request.verbose = verbose

        let outcome = try await AnonymizationWorkflow().run(request) { print($0, terminator: "") }

        // Exit with error if any failures
        if outcome.exitCode != 0 {
            throw ExitCode.failure
        }
    }
}
