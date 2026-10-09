import Foundation

// NEMA-verified: 2026a, checked 2026-10-01 — dicom-json renders each workitem's DICOM JSON Model object (PS3.18 2026a F.2) kept on WorkitemResult (D213); checked 2026-09-28 — carries no DICOM-standard data (console text for worklist results); the Final State note follows PS3.4 2026a CC.2.1.3
/// Output renderings shared by the `dicom-wado ups --search` CLI (UPS-RS) and
/// DICOMStudio's in-app UPS worklist search, so both produce identical text for the
/// same workitem results. This mirrors `QIDOResultFormatter` (QIDO-RS) and
/// `DICOMQueryResultFormatter` (DICOMNetwork, DIMSE C-FIND): a SINGLE formatter both
/// sides call, so their output pipelines cannot drift (the app previously hand-rolled
/// a divergent renderer that ignored `--format` and emitted a verbose per-record dump
/// with extra attributes the CLI never prints).
public enum UPSOutputFormat: String, Sendable, CaseIterable {
    case table
    case json
    case csv
    /// The PS3.18 2026a F.2 DICOM JSON Model: each workitem's attributes as the origin
    /// server returned them (`WorkitemResult.dicomJSON`), via `DICOMJSONModelFormatter`.
    case dicomJSON = "dicom-json"
}

/// Renders UPS-RS workitem search results to text. The only UPS worklist output
/// formatter in the codebase — used by both the `dicom-wado` CLI and the CLI Workshop.
public struct UPSResultFormatter {
    public init() {}

    public func format(_ workitems: [WorkitemResult], format: UPSOutputFormat) -> String {
        switch format {
        case .table: return table(workitems)
        case .json:  return json(workitems)
        case .csv:   return csv(workitems)
        case .dicomJSON: return DICOMJSONModelFormatter.format(workitems.compactMap(\.attributes))
        }
    }

    // MARK: - Table

    private func table(_ workitems: [WorkitemResult]) -> String {
        // Compute dynamic column width for UID based on longest value
        let maxUIDLength = workitems.reduce(12) { max($0, $1.workitemUID.count) }  // min 12 for header
        let uidWidth = min(maxUIDLength, 70)  // cap at 70 to avoid excessive width
        let totalWidth = uidWidth + 1 + 20 + 1 + 30 + 1 + 20

        var output = ""
        output += String(repeating: "=", count: totalWidth) + "\n"
        output += pad("Worklist UID", uidWidth) + " " + pad("State", 20) + " " + pad("Label", 30) + " " + pad("Patient", 20) + "\n"
        output += String(repeating: "=", count: totalWidth) + "\n"

        for item in workitems {
            let uid = truncate(item.workitemUID, maxLength: uidWidth)
            let state = item.state?.rawValue ?? ""
            let label = truncate(item.procedureStepLabel ?? "", maxLength: 30)
            let patient = truncate(item.patientName ?? "", maxLength: 20)

            output += pad(uid, uidWidth) + " " + pad(state, 20) + " " + pad(label, 30) + " " + pad(patient, 20) + "\n"
        }

        output += String(repeating: "=", count: totalWidth) + "\n"
        return output
    }

    // MARK: - JSON

    private func json(_ workitems: [WorkitemResult]) -> String {
        var items: [[String: Any]] = []
        for item in workitems {
            var dict: [String: Any] = ["workitemUID": item.workitemUID]
            if let s = item.state { dict["state"] = s.rawValue }
            if let p = item.priority { dict["priority"] = p.rawValue }
            if let pp = item.progressPercentage { dict["progressPercentage"] = pp }
            if let pd = item.progressDescription { dict["progressDescription"] = pd }
            if let sd = item.scheduledStartDateTime { dict["scheduledStartDateTime"] = sd }
            if let ec = item.expectedCompletionDateTime { dict["expectedCompletionDateTime"] = ec }
            if let md = item.modificationDateTime { dict["modificationDateTime"] = md }
            if let l = item.procedureStepLabel { dict["procedureStepLabel"] = l }
            if let wl = item.worklistLabel { dict["worklistLabel"] = wl }
            if let sid = item.scheduledProcedureStepID { dict["scheduledProcedureStepID"] = sid }
            if let pn = item.patientName { dict["patientName"] = pn }
            if let pid = item.patientID { dict["patientID"] = pid }
            if let dob = item.patientBirthDate { dict["patientBirthDate"] = dob }
            if let sex = item.patientSex { dict["patientSex"] = sex }
            if let suid = item.studyInstanceUID { dict["studyInstanceUID"] = suid }
            if let acc = item.accessionNumber { dict["accessionNumber"] = acc }
            if let ref = item.referringPhysicianName { dict["referringPhysicianName"] = ref }
            if let tx = item.transactionUID { dict["transactionUID"] = tx }
            items.append(dict)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    // MARK: - CSV

    private func csv(_ workitems: [WorkitemResult]) -> String {
        var output = "WorkitemUID,State,ProcedureStepLabel,PatientName,PatientID\n"
        for item in workitems {
            let uid = csvEscape(item.workitemUID)
            let state = csvEscape(item.state?.rawValue ?? "")
            let label = csvEscape(item.procedureStepLabel ?? "")
            let patient = csvEscape(item.patientName ?? "")
            let patientID = csvEscape(item.patientID ?? "")

            output += "\(uid),\(state),\(label),\(patient),\(patientID)\n"
        }
        return output
    }

    // MARK: - Utilities

    private func truncate(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength { return string }
        let endIndex = string.index(string.startIndex, offsetBy: maxLength - 3)
        return String(string[..<endIndex]) + "..."
    }

    private func pad(_ string: String, _ width: Int) -> String {
        if string.count >= width { return string }
        return string + String(repeating: " ", count: width - string.count)
    }

    private func csvEscape(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }
}

// MARK: - Shared console output (dicom-wado ups CLI ⇄ Workshop UPS executor)

/// Builds the console text for UPS create and change-state operations. The CLI
/// text is canonical and the Workshop executor renders identical strings, so the
/// two surfaces cannot drift.
public enum UPSConsole {
    /// The create-workitem response block (UID, optional retrieve URL, warnings).
    public static func createResponseText(_ response: UPSCreateResponse) -> String {
        var out = "Created worklist item:\n"
        out += "  UID: \(response.workitemUID)\n"
        if let url = response.retrieveURL {
            out += "  Retrieve URL: \(url)\n"
        }
        if !response.warnings.isEmpty {
            out += "  Warnings:\n"
            for warning in response.warnings {
                out += "    - \(warning)\n"
            }
        }
        return out
    }

    /// Verbose header before a change-state request.
    public static func updateVerboseHeader(uid: String, stateRaw: String, requestingAE: String?, transactionUID: String?) -> String {
        var out = "Updating worklist item \(uid) to state: \(stateRaw)\n"
        if let ae = requestingAE { out += "  Requesting AE: \(ae)\n" }
        if let tx = transactionUID { out += "  Transaction UID: \(tx)\n" }
        return out
    }

    /// Verbose line before the Final State attribute update that precedes COMPLETED.
    public static func finalStateUpdatingLine() -> String {
        "Updating workitem with Final State attributes (required before COMPLETED)...\n"
    }

    /// Verbose line after the Final State attribute update succeeds.
    public static func finalStateUpdatedLine() -> String {
        "Final State attributes updated successfully\n"
    }

    /// The change-state result block (success line, optional transaction UID, warnings).
    public static func updateResultText(uid: String, stateRaw: String, transactionUID: String?, warnings: [String]) -> String {
        var out = "Successfully updated worklist item \(uid) to \(stateRaw)\n"
        if let tx = transactionUID { out += "Transaction UID: \(tx)\n" }
        for warning in warnings { out += "Warning: \(warning)\n" }
        return out
    }
}
