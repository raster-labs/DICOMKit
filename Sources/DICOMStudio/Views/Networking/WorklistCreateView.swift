// WorklistCreateView.swift
// DICOMStudio
//
// DICOM Studio — "New Worklist Item" sheet of the Networking panel's worklist area (HL7 ORM^O01
// over MLLP, or the archive's REST API). Moved out of the CLI Workshop's dicom-mwl tool on
// 2026-10-06 (P-STUDIO-MWL-CREATE). Owner decision: the create flow stays in the app only
// (Networking panel); dicom-mwl has no `create` subcommand and none is added to the CLI or to
// DICOMNetwork, so the Workshop's dicom-mwl tool offers only the CLI's own subcommand (query).
// NEMA-verified: 2026a, checked 2026-10-06 — carries no DICOM-standard data of its own: the field labels name the PS3.3 2026a attributes verified in WorklistCreateViewModel.swift (Tables C.4-10, C.4-11, C.4-12, C.7-1, 16/16); the pickers are WorklistCreateViewModel.modalityValues / patientSexValues

#if canImport(SwiftUI)
import SwiftUI

/// The Networking panel's "New Worklist Item" form (P-STUDIO-MWL-CREATE).
@available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
public struct WorklistCreateView: View {
    @Bindable var viewModel: WorklistCreateViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: WorklistCreateViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Host (host or host:port)", text: $viewModel.host)
                        .accessibilityLabel("Worklist server host")
                    Picker("Create Method", selection: $viewModel.method) {
                        ForEach(WorklistCreateMethod.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    if viewModel.method == .hl7 {
                        TextField("HL7 Port", text: $viewModel.hl7Port)
                        TextField("Sending Application (MSH-3)", text: $viewModel.sendingApplication)
                        TextField("Sending Facility (MSH-4)", text: $viewModel.sendingFacility)
                        TextField("Receiving Application (MSH-5)", text: $viewModel.receivingApplication)
                        TextField("Receiving Facility (MSH-6)", text: $viewModel.receivingFacility)
                    } else {
                        TextField("Port", text: $viewModel.port)
                        TextField("Calling AE Title", text: $viewModel.callingAET)
                        TextField("Called AE Title", text: $viewModel.calledAET)
                        TextField("REST Base URL (default http://<host>:8080/dcm4chee-arc)", text: $viewModel.restBaseURL)
                    }
                    TextField("Timeout (s)", text: $viewModel.timeout)
                }

                Section("Patient") {
                    TextField("Patient's Name (0010,0010) — required", text: $viewModel.patientName)
                    TextField("Patient ID (0010,0020) — required", text: $viewModel.patientID)
                    TextField("Patient's Birth Date (0010,0030) YYYYMMDD", text: $viewModel.patientBirthDate)
                    Picker("Patient's Sex (0010,0040)", selection: $viewModel.patientSex) {
                        ForEach(WorklistCreateViewModel.patientSexValues, id: \.self) { v in
                            Text(v.isEmpty ? "Unknown" : v).tag(v)
                        }
                    }
                }

                Section("Request") {
                    TextField("Accession Number (0008,0050)", text: $viewModel.accessionNumber)
                    TextField("Referring Physician's Name (0008,0090)", text: $viewModel.referringPhysician)
                    TextField("Requested Procedure ID (0040,1001)", text: $viewModel.procedureID)
                    TextField("Requested Procedure Description (0032,1060)", text: $viewModel.procedureDescription)
                }

                Section("Scheduled Procedure Step") {
                    Picker("Modality (0008,0060)", selection: $viewModel.modality) {
                        ForEach(WorklistCreateViewModel.modalityValues, id: \.self) { v in
                            Text(v).tag(v)
                        }
                    }
                    TextField("Scheduled Station AE Title (0040,0001)", text: $viewModel.scheduledStationAET)
                    TextField("Scheduled Station Name (0040,0010)", text: $viewModel.stationName)
                    TextField("Start Date (0040,0002) YYYYMMDD / today / tomorrow", text: $viewModel.scheduledDate)
                    TextField("Start Time (0040,0003) HHMMSS", text: $viewModel.scheduledTime)
                    TextField("Scheduled Procedure Step ID (0040,0009)", text: $viewModel.spsID)
                    TextField("Scheduled Procedure Step Description (0040,0007)", text: $viewModel.spsDescription)
                    TextField("Scheduled Performing Physician's Name (0040,0006)", text: $viewModel.performingPhysician)
                }

                if !viewModel.output.isEmpty {
                    Section("Result") {
                        Text(viewModel.output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Worklist Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        viewModel.clearOutput()
                        Task { await viewModel.run() }
                    }
                    .disabled(viewModel.isRunning
                              || viewModel.host.isEmpty
                              || viewModel.patientName.isEmpty
                              || viewModel.patientID.isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
    }
}
#endif
