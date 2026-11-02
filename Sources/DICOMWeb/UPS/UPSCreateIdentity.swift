import DICOMCore

/// Resolves the two UPS-RS Create identity forms before any request is sent.
/// PS3.18 2026a 11.4.1.1: the Worklist target carries its UID in the Data Set;
/// the Workitem target carries it in the `workitem` query parameter.
struct UPSCreateIdentity {
    let uid: String
    let usesQueryParameter: Bool
    let workitem: [String: Any]

    init(workitem: [String: Any], explicitUID: String?) throws {
        let bodyUID: String?
        if let raw = workitem[UPSTag.sopInstanceUID] {
            guard let element = raw as? [String: Any],
                  element["vr"] as? String == "UI",
                  let values = element["Value"] as? [String], values.count == 1,
                  DICOMValueRules.isValidUID(values[0]),
                  element["InlineBinary"] == nil, element["BulkDataURI"] == nil else {
                throw UPSError.invalidWorkitemData(reason:
                    "SOP Instance UID (0008,0018) must be one valid DICOM UID with VR UI")
            }
            bodyUID = values[0]
        } else {
            bodyUID = nil
        }
        if let explicitUID {
            guard DICOMValueRules.isValidUID(explicitUID) else {
                throw UPSError.invalidWorkitemData(reason: "The workitem query UID must be a valid DICOM UID")
            }
            guard bodyUID == nil || bodyUID == explicitUID else {
                throw UPSError.invalidWorkitemData(reason:
                    "SOP Instance UID (0008,0018) conflicts with the workitem query UID")
            }
        }
        uid = explicitUID ?? bodyUID ?? UIDGenerator.generateUID().value
        usesQueryParameter = explicitUID != nil
        var payload = workitem
        if usesQueryParameter {
            payload.removeValue(forKey: UPSTag.sopInstanceUID)
        } else if bodyUID == nil {
            payload[UPSTag.sopInstanceUID] = ["vr": "UI", "Value": [uid]]
        }
        self.workitem = payload
    }
}
