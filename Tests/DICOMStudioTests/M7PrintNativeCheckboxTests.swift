#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI
import XCTest
@testable import DICOMStudio

@MainActor
final class M7PrintNativeCheckboxTests: XCTestCase {
    func testHostedPrintOptionsStayInsideNarrowDefaultAndExpandedPaneWidths() throws {
        let parameters = CLIWorkshopPrintCatalog.parameters.filter {
            $0.parameterType == .booleanToggle && ($0.visibleWhen?.values.contains("send") ?? false)
        }
        XCTAssertEqual(parameters.count, 7)
        // Actual pane sizes are 240 / 380 / 620; the form and card consume
        // 28 points of padding per side. Include the surrounding field/card
        // structure so an oversized native row cannot widen the whole form.
        for paneWidth: CGFloat in [240, 380, 620] {
            let host = NSHostingView(rootView:
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Connection Retries", text: .constant("0"))
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(parameters, id: \.id) { parameter in
                            CLIWorkshopPrintOptionCheckbox(parameter: parameter, isOn: .constant(false))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }.padding(16)
            )
            host.frame = NSRect(x: 0, y: 0, width: paneWidth, height: 1600)
            host.layoutSubtreeIfNeeded()
            func checkboxes(in view: NSView) -> [CLIWorkshopPrintNativeCheckbox] {
                (view as? CLIWorkshopPrintNativeCheckbox).map { [$0] } ?? view.subviews.flatMap { checkboxes(in: $0) }
            }
            let controls = checkboxes(in: host)
            XCTAssertEqual(controls.count, parameters.count, "Pane width \(paneWidth)")
            for checkbox in controls {
                let rect = checkbox.convert(checkbox.bounds, to: host)
                XCTAssertGreaterThan(rect.width, 0, checkbox.title)
                XCTAssertGreaterThan(rect.height, 0, checkbox.title)
                XCTAssertGreaterThanOrEqual(rect.minX, 27.5, checkbox.title)
                XCTAssertLessThanOrEqual(rect.maxX, paneWidth - 27.5, checkbox.title)
                XCTAssertTrue(checkbox.cell?.wraps == true, checkbox.title)
                XCTAssertEqual(checkbox.lineBreakMode, .byWordWrapping, checkbox.title)
            }
        }
    }

    func testRealPrintWorkshopFormFitsActualSplitPaneWidths() throws {
        // The isolated checkbox test above cannot detect another form control
        // widening the shared scroll document. In particular, six long command
        // names in a segmented picker previously clipped every row, although
        // each checkbox fitted correctly when hosted on its own.
        func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, in: $0) }
        }
        for (tool, command) in [
            ("dicom-print", "dicom-print send --aet APP --dry-run pacs://127.0.0.1:1 '/tmp/a long literal image name.dcm'"),
            ("dicom-printscp", "dicom-printscp serve --port 0 --output none --duration 1")
        ] {
            let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
            vm.selectTool(id: tool)
            try vm.importPrintCommand(command)
            let host = NSHostingView(rootView: CLIWorkshopView(viewModel: vm))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            host.frame = NSRect(x: 0, y: 0, width: 1200, height: 900)
            host.layoutSubtreeIfNeeded()
            let split = try XCTUnwrap(descendants(NSSplitView.self, in: host).first,
                                      "The test must host the actual Workshop split hierarchy")
            // NSSplitView also owns a divider subview. Only its arranged
            // subviews are content panes; do not count that AppKit decoration.
            XCTAssertEqual(split.arrangedSubviews.count, 2)
            let pane = try XCTUnwrap(split.arrangedSubviews.first)
            for width: CGFloat in [240, 380, 620] {
                split.setPosition(width, ofDividerAt: 0)
                split.layoutSubtreeIfNeeded()
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(pane.bounds.width, width, accuracy: 1, "\(tool) actual pane width")
                let boxes = descendants(CLIWorkshopPrintNativeCheckbox.self, in: pane)
                XCTAssertFalse(boxes.isEmpty, "\(tool) must render its real form controls")
                for box in boxes {
                    let rect = box.convert(box.bounds, to: pane)
                    XCTAssertGreaterThan(rect.width, 0, box.title)
                    XCTAssertGreaterThanOrEqual(rect.minX, -0.5, "\(tool) \(width): \(box.title)")
                    XCTAssertLessThanOrEqual(rect.maxX, pane.bounds.width + 0.5,
                                             "\(tool) \(width): \(box.title)")
                }
                // These fields share the same vertical document as the flags.
                // Check them too so a checkbox-only correction cannot hide a
                // continued form-wide overflow.
                let fields = descendants(NSTextField.self, in: pane).filter { $0.isEditable }
                XCTAssertFalse(fields.isEmpty, "\(tool) must include its real editable fields")
                for field in fields {
                    let rect = field.convert(field.bounds, to: pane)
                    XCTAssertGreaterThanOrEqual(rect.minX, -0.5, "\(tool) \(width): \(field.stringValue)")
                    XCTAssertLessThanOrEqual(rect.maxX, pane.bounds.width + 0.5,
                                             "\(tool) \(width): \(field.stringValue)")
                }
            }
            XCTAssertTrue(vm.commandHistory.isEmpty, "Layout qualification must never run the command")
        }
    }

    func testEveryPrintFlagHasNativeCheckboxNameHelpIdentifierAndState() {
        let parameters = (CLIWorkshopPrintCatalog.parameters + CLIWorkshopPrintSCPCatalog.parameters)
            .filter { $0.parameterType == .booleanToggle }
        XCTAssertFalse(parameters.isEmpty)
        // AppKit reports AXUnknown for an unexposed stock checkbox too, even
        // after NSApplication initialization and attachment to a hidden window.
        // Compare the native control here; actual AXCheckBox role/name is a
        // separate mandatory packaged-app gate, not a detached-control claim.
        let stockCheckbox = NSButton(checkboxWithTitle: "Stock checkbox", target: nil, action: nil)
        for parameter in parameters {
            var enabled = false
            let binding = Binding(get: { enabled }, set: { enabled = $0 })
            let checkbox = CLIWorkshopPrintNativeCheckbox(parameter: parameter, isOn: binding)
            XCTAssertEqual(checkbox.accessibilityRole(), stockCheckbox.accessibilityRole(), parameter.id)
            XCTAssertEqual(checkbox.accessibilityLabel(), parameter.displayName, parameter.id)
            XCTAssertFalse(parameter.displayName.isEmpty, parameter.id)
            XCTAssertEqual(checkbox.accessibilityHelp() ?? "", parameter.helpText, parameter.id)
            XCTAssertEqual(checkbox.accessibilityIdentifier(), "print-option-\(parameter.id)")
            XCTAssertEqual(checkbox.state, .off, parameter.id)
            checkbox.performClick(nil)
            XCTAssertTrue(enabled, parameter.id)
            XCTAssertEqual(checkbox.state, .on, parameter.id)
            checkbox.performClick(nil)
            XCTAssertFalse(enabled, parameter.id)
            XCTAssertEqual(checkbox.state, .off, parameter.id)
        }
    }

    func testReusedCheckboxUpdatesBindingAndHonorsDisabledState() throws {
        let raw = try XCTUnwrap(CLIWorkshopPrintCatalog.parameters.first { $0.id == "raw" })
        let dryRun = try XCTUnwrap(CLIWorkshopPrintCatalog.parameters.first { $0.id == "dryRun" })
        var original = false, replacement = true
        let originalBinding = Binding(get: { original }, set: { original = $0 })
        let replacementBinding = Binding(get: { replacement }, set: { replacement = $0 })
        let checkbox = CLIWorkshopPrintNativeCheckbox(parameter: raw, isOn: originalBinding)
        checkbox.update(parameter: dryRun, isOn: replacementBinding, isEnabled: false)
        XCTAssertFalse(checkbox.isEnabled)
        XCTAssertEqual(checkbox.state, .on)
        XCTAssertEqual(checkbox.accessibilityLabel(), dryRun.displayName)
        XCTAssertEqual(checkbox.accessibilityIdentifier(), "print-option-dryRun")
        checkbox.performClick(nil)
        XCTAssertTrue(replacement, "A disabled form cannot mutate its argument binding")
        XCTAssertFalse(original)
        checkbox.update(parameter: dryRun, isOn: replacementBinding)
        XCTAssertTrue(checkbox.isEnabled)
        checkbox.performClick(nil)
        XCTAssertFalse(replacement)
        XCTAssertFalse(original, "A reused row must not retain the previous parameter binding")
    }

    func testNativePressChangesOnlyTheSelectedPrintArgumentAndPreview() throws {
        for (tool, command, flag) in [
            ("dicom-print", "dicom-print send pacs://localhost x.dcm --aet APP", "--raw"),
            ("dicom-print", "dicom-print send pacs://localhost x.dcm --aet APP", "--dry-run"),
            ("dicom-printscp", "dicom-printscp serve --port 0 --output none --duration 1", "--quiet")
        ] {
            let vm = CLIWorkshopViewModel(service: CLIWorkshopService())
            vm.selectTool(id: tool)
            try vm.importPrintCommand(command)
            let parameter = try XCTUnwrap((vm.visibleParameters() + vm.advancedParameters()).first { $0.flag == flag })
            let binding = Binding<Bool>(
                get: { vm.parameterValues.first { $0.parameterID == parameter.id }?.stringValue == "true" },
                set: { vm.updateParameterValue(parameterID: parameter.id, value: $0 ? "true" : "false") })
            let checkbox = CLIWorkshopPrintNativeCheckbox(parameter: parameter, isOn: binding)
            let before = try CLIWorkshopPrintCommandCodec.arguments(toolID: tool,
                parameterValues: vm.parameterValues, parameterDefinitions: vm.parameterDefinitions)
            let beforePreview = vm.commandPreview
            XCTAssertFalse(before.contains(flag))
            checkbox.performClick(nil)
            let after = try CLIWorkshopPrintCommandCodec.arguments(toolID: tool,
                parameterValues: vm.parameterValues, parameterDefinitions: vm.parameterDefinitions)
            XCTAssertEqual(after.filter { $0 == flag }.count, 1)
            XCTAssertEqual(after.filter { $0 != flag }, before)
            XCTAssertTrue(vm.commandPreview.contains(flag))
            XCTAssertTrue(vm.isCommandValid)
            checkbox.performClick(nil)
            XCTAssertEqual(vm.commandPreview, beforePreview)
            XCTAssertTrue(vm.commandHistory.isEmpty, "Changing a checkbox does not execute a command")
        }
    }
}
#endif
