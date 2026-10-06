// PrintFilmDestinationPickerTests.swift
// DICOMStudioTests
//
// The print screen's Film Destination (2000,0040) picker: MAGAZINE, PROCESSOR
// and BIN_i for any i ≥ 1 (PS3.3 2026a Table C.13-1 puts no maximum on the
// number of sorter bins).

#if canImport(SwiftUI)
import Testing
@testable import DICOMStudio
import DICOMNetwork
import DICOMPrintKit

@Suite("Print Film Destination Picker Tests")
struct PrintFilmDestinationPickerTests {

    @Test("The picker offers the two named Table C.13-1 terms and one sorter-bin row")
    func testChoices() {
        let values = FilmDestinationPicker.choices.map(\.value.rawValue)
        #expect(values == ["MAGAZINE", "PROCESSOR", "BIN_1"])
        #expect(FilmDestinationPicker.choices.last?.label == "Sorter bin")
    }

    @Test("Every BIN_i is shown as the bin row; the named terms are shown as themselves")
    func testChoiceForDestination() {
        #expect(FilmDestinationPicker.choice(for: .magazine) == .magazine)
        #expect(FilmDestinationPicker.choice(for: .processor) == .processor)
        #expect(FilmDestinationPicker.choice(for: .bin(1)) == FilmDestinationPicker.binChoice)
        #expect(FilmDestinationPicker.choice(for: .bin(7)) == FilmDestinationPicker.binChoice)
        #expect(FilmDestinationPicker.choice(for: .bin(42)) == FilmDestinationPicker.binChoice)
    }

    @Test("Choosing the bin row keeps the bin number in force; a named term replaces it")
    func testDestinationChoosing() {
        #expect(FilmDestinationPicker.destination(choosing: FilmDestinationPicker.binChoice, current: .bin(7)) == .bin(7))
        #expect(FilmDestinationPicker.destination(choosing: FilmDestinationPicker.binChoice, current: .magazine) == .bin(1))
        #expect(FilmDestinationPicker.destination(choosing: .processor, current: .bin(7)) == .processor)
    }

    @Test("A typed bin number becomes BIN_n, held at 1 or more and within the CS length")
    func testBinNumber() {
        #expect(FilmDestinationPicker.bin(3).rawValue == "BIN_3")
        #expect(FilmDestinationPicker.bin(12).rawValue == "BIN_12")
        #expect(FilmDestinationPicker.bin(0).rawValue == "BIN_1")
        #expect(FilmDestinationPicker.bin(-5).rawValue == "BIN_1")
        #expect(FilmDestinationPicker.bin(Int.max).rawValue == "BIN_\(FilmDestination.maximumBinNumber)")
        #expect(FilmDestinationPicker.bin(Int.max).rawValue.count <= 16)
    }

    @Test("The bin field speaks dicom-print's --film-destination tokens (DICOMPrintKit catalogToken, D242)")
    func testCatalogToken() {
        for n in [1, 2, 12, 999] {
            let destination = FilmDestinationPicker.bin(n)
            #expect(destination.catalogToken == "bin-\(n)")
            #expect(FilmDestination(catalogToken: destination.catalogToken) == destination)
        }
        #expect(FilmDestinationPicker.termAndToken(.bin(12)) == "BIN_12 (bin-12)")
        #expect(FilmDestinationPicker.termAndToken(.magazine) == "MAGAZINE (magazine)")
    }

    @Test("The bin reaches the job request as Film Destination BIN_n")
    @MainActor
    func testBinReachesRequest() {
        let viewModel = PrintViewModel(printerStorage: PrinterProfileStorageService(storageService: StorageService(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))))
        viewModel.filmDestination = FilmDestinationPicker.bin(5)
        #expect(viewModel.request.filmDestination.rawValue == "BIN_5")
    }
}
#endif
