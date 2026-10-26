#!/usr/bin/env python3
"""Independent, synthetic loopback qualification for intermediate MPPS updates.

Requires pydicom 3.0.1 and pynetdicom 3.0.4. Run with --bin-dir to exercise the
actual CLI, or --serve to expose the same strict peer to Workshop acceptance.
The peer implements only the documented MPPS attribute subset, not a full SCP.
It retains every request, response, and resulting state, including failures.
"""

import argparse
import copy
import hashlib
import json
import pathlib
import platform
import subprocess
import sys
import threading
import time

import pydicom
import pynetdicom
from pydicom.dataset import Dataset
from pydicom.tag import Tag
from pydicom.uid import ExplicitVRLittleEndian, ImplicitVRLittleEndian
from pynetdicom import AE, evt

MPPS = "1.2.840.10008.3.1.2.3.3"
CT = "1.2.840.10008.5.1.4.1.1.2"
STUDY = "2.25.8202601"
SERIES = STUDY + ".1"
IMAGES = [SERIES + "." + str(i) for i in range(1, 4)]
STATUS = Tag(0x00400252)
END_DATE = Tag(0x00400250)
END_TIME = Tag(0x00400251)
PERFORMED_SERIES = Tag(0x00400340)
CHARSET = Tag(0x00080005)
DESCRIPTION = Tag(0x00400254)
SENSITIVE_VRS = {"SH", "LO", "ST", "LT", "PN", "UC", "UT"}
# PS3.4 2026a Table F.7.2-1 N-SET subset exercised by these clients.
SETTABLE = {
    CHARSET, STATUS, END_DATE, END_TIME, DESCRIPTION, Tag(0x00400255),
    Tag(0x00081032), Tag(0x00401012), Tag(0x00400280), Tag(0x00400281),
    Tag(0x00400260), PERFORMED_SERIES,
}
REFERENCES = [
    "PS3.4 2026a Table F.7.2-1 and Notes 1-2",
    "PS3.4 2026a F.7.2.1.2 (create before set)",
    "PS3.4 2026a F.7.2.2.1 (same character set as N-CREATE)",
    "PS3.4 2026a F.7.2.2.2 (partial attributes, full sequence replacement, terminal state)",
    "PS3.4 2026a F.7.2.2.3 and Table F.7.2-2 (SCP terminal refusal)",
]


def save(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, default=str) + "\n")
    temporary.replace(path)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def charset(ds):
    value = ds.get("SpecificCharacterSet", "")
    if isinstance(value, str):
        return value or "ISO_IR 6"
    return "\\".join(value) or "ISO_IR 6"


def references(ds):
    return {
        (str(ref.ReferencedSOPClassUID), str(ref.ReferencedSOPInstanceUID))
        for series in ds.get("PerformedSeriesSequence", [])
        for name in ["ReferencedImageSequence", "ReferencedNonImageCompositeSOPInstanceSequence"]
        for ref in series.get(name, [])
    }


class StrictMPPSPeer:
    def __init__(self, root, port=0):
        self.root = root
        self.lock = threading.RLock()
        self.states = {}
        self.requests = []
        self.associations = []
        self.errors = []
        self.ae = AE(ae_title="E1MPPS")
        self.ae.acse_timeout = 5
        self.ae.dimse_timeout = 5
        self.ae.network_timeout = 5
        self.ae.add_supported_context(MPPS, [ExplicitVRLittleEndian, ImplicitVRLittleEndian])
        self.server = self.ae.start_server(
            ("127.0.0.1", port), block=False,
            evt_handlers=[(evt.EVT_ACCEPTED, self.accepted),
                          (evt.EVT_N_CREATE, self.create), (evt.EVT_N_SET, self.update)],
        )
        self.port = self.server.server_address[1]
        self.persist()
        save(root / "ready.json", {
            "host": "127.0.0.1", "port": self.port, "called_aet": "E1MPPS",
            "stop_file": str(root / "stop"), "references": REFERENCES,
            "scope": "Synthetic selected MPPS attributes; not a complete IOD/SCP certification",
        })

    def persist(self):
        with self.lock:
            save(self.root / "requests.json", self.requests)
            save(self.root / "states.json", {k: v.to_json_dict() for k, v in self.states.items()})
            save(self.root / "peer-errors.json", self.errors)
            save(self.root / "associations.json", self.associations)

    def accepted(self, event):
        with self.lock:
            self.associations.append({"calling_aet": event.assoc.requestor.ae_title,
                                      "called_aet": event.assoc.acceptor.ae_title})
            self.persist()

    def request(self, event, operation, ds, uid, raw):
        row = {
            "number": len(self.requests) + 1, "operation": operation,
            "uid": uid, "syntax": str(event.context.transfer_syntax),
            "dataset": ds.to_json_dict(), "raw_sha256": hashlib.sha256(raw).hexdigest(),
        }
        (self.root / (f"request-{row['number']:03}.dcmdata")).write_bytes(raw)
        self.requests.append(row)
        return row

    def finish(self, row, status, reason="", error_id=None):
        row.update(status=f"{status:04X}", reason=reason)
        if row["uid"] in self.states:
            row["state_after"] = self.states[row["uid"]].to_json_dict()
        self.persist()
        response = Dataset()
        response.Status = status
        if reason:
            response.ErrorComment = reason[:64]
        if error_id is not None:
            response.ErrorID = error_id
        return response, None

    def create(self, event):
        with self.lock:
            ds = event.attribute_list
            uid = str(event.request.AffectedSOPInstanceUID)
            row = self.request(event, "N-CREATE", ds, uid, event.request.AttributeList.getvalue())
            try:
                if uid in self.states:
                    return self.finish(row, 0x0111, "Duplicate SOP Instance")
                if ds.get("PerformedProcedureStepStatus") != "IN PROGRESS":
                    return self.finish(row, 0x0106, "N-CREATE requires IN PROGRESS")
                if ds.get("PerformedProcedureStepEndDate") or ds.get("PerformedProcedureStepEndTime"):
                    return self.finish(row, 0x0106, "N-CREATE end fields must be empty")
                for keyword in ["Modality", "PerformedStationAETitle", "PerformedProcedureStepStartDate",
                                "PerformedProcedureStepStartTime", "PerformedProcedureStepID"]:
                    if not ds.get(keyword):
                        return self.finish(row, 0x0120, "Missing required attribute " + keyword)
                if not ds.get("ScheduledStepAttributesSequence"):
                    return self.finish(row, 0x0120, "Missing Scheduled Step Attributes Sequence")
                for tag in [END_DATE, END_TIME, DESCRIPTION, PERFORMED_SERIES]:
                    if tag not in ds:
                        return self.finish(row, 0x0120, "Missing Type 2 attribute " + str(tag))
                self.states[uid] = copy.deepcopy(ds)
                return self.finish(row, 0)
            except Exception as error:
                self.errors.append({"operation": "N-CREATE", "error": repr(error)})
                return self.finish(row, 0x0110, "Peer exception")

    def update(self, event):
        with self.lock:
            ds = event.modification_list
            uid = str(event.request.RequestedSOPInstanceUID)
            row = self.request(event, "N-SET", ds, uid, event.request.ModificationList.getvalue())
            try:
                if uid not in self.states:
                    return self.finish(row, 0x0112, "No such SOP Instance")
                current = self.states[uid]
                if current.PerformedProcedureStepStatus != "IN PROGRESS":
                    return self.finish(row, 0x0110, "Performed Procedure Step Object may no longer be updated", 0xA710)
                if len(ds) == 0 or all(element.tag == CHARSET for element in ds):
                    return self.finish(row, 0x0106, "Empty modification list")
                for element in ds:
                    if element.tag not in SETTABLE:
                        return self.finish(row, 0x0105, "Attribute not supported for N-SET " + str(element.tag))
                    if element.tag != CHARSET and element.tag not in current:
                        return self.finish(row, 0x0105, "Attribute was not created " + str(element.tag))
                if any(element.VR in SENSITIVE_VRS for element in ds.iterall()):
                    if charset(ds) != charset(current):
                        return self.finish(row, 0x0106, "N-SET character set differs from N-CREATE")
                requested_status = ds.get("PerformedProcedureStepStatus", current.PerformedProcedureStepStatus)
                if requested_status not in ["IN PROGRESS", "COMPLETED", "DISCONTINUED"]:
                    return self.finish(row, 0x0106, "Invalid Performed Procedure Step Status")
                if requested_status == "IN PROGRESS" and (ds.get("PerformedProcedureStepEndDate") or ds.get("PerformedProcedureStepEndTime")):
                    return self.finish(row, 0x0106, "Intermediate update cannot finalize end date/time")
                updated = copy.deepcopy(current)
                for element in ds:
                    if element.tag != CHARSET:
                        updated[element.tag] = copy.deepcopy(element)
                if PERFORMED_SERIES in ds:
                    for series in ds.PerformedSeriesSequence:
                        if not series.get("SeriesInstanceUID") or not series.get("ProtocolName"):
                            return self.finish(row, 0x0106, "Series requires UID and Protocol Name")
                        for keyword in ["PerformingPhysicianName", "OperatorsName", "SeriesDescription",
                                        "RetrieveAETitle", "ReferencedImageSequence", "ReferencedNonImageCompositeSOPInstanceSequence"]:
                            if keyword not in series:
                                return self.finish(row, 0x0120, "Series missing Type 2 " + keyword)
                    if not references(current).issubset(references(updated)):
                        return self.finish(row, 0x0106, "Sequence update lost prior acquired instance references")
                if requested_status in ["COMPLETED", "DISCONTINUED"]:
                    if not updated.get("PerformedProcedureStepEndDate") or not updated.get("PerformedProcedureStepEndTime"):
                        return self.finish(row, 0x0106, "Final state requires end date/time")
                    if not updated.get("PerformedSeriesSequence"):
                        return self.finish(row, 0x0106, "Final state requires a nonempty Performed Series Sequence")
                self.states[uid] = updated
                return self.finish(row, 0)
            except Exception as error:
                self.errors.append({"operation": "N-SET", "error": repr(error)})
                return self.finish(row, 0x0110, "Peer exception")

    def close(self):
        self.server.shutdown()
        self.ae.shutdown()
        self.persist()
        save(self.root / "finished.json", {"requests": len(self.requests),
                                            "associations": len(self.associations), "errors": self.errors})


def exercise_cli(binary, root, peer):
    checks = []
    records = []

    def check(label, condition):
        checks.append({"assertion": label, "result": "Passed" if condition else "Failed"})
        save(root / "assertions.json", checks)
        assert condition, label

    def run(name, operation, args, successful=True, network=True):
        argv = [str(binary), operation, "127.0.0.1", "--port", str(peer.port),
                "--aet", "E1CLI", "--called-aet", "E1MPPS", "--timeout", "5", *args]
        before = len(peer.requests)
        result = subprocess.run(argv, capture_output=True, text=True, timeout=20)
        (root / (name + ".stdout.txt")).write_text(result.stdout)
        (root / (name + ".stderr.txt")).write_text(result.stderr)
        records.append({"id": name, "argv": argv, "exit": result.returncode,
                        "request_count": len(peer.requests) - before})
        save(root / "cli-actions.json", records)
        check(name + " exit", (result.returncode == 0) == successful)
        check(name + " wire count", len(peer.requests) - before == (1 if network else 0))
        return peer.requests[-1] if network else None

    def create(name, extra=None):
        row = run(name, "create", ["--study-uid", STUDY, "--modality", "CT",
                                  "--patient-id", "E1-SYNTHETIC", "--patient-name", "E1^PATIENT",
                                  "--procedure-step-description", "BASELINE", *(extra or [])])
        check(name + " remains IN PROGRESS", row["state_after"]["00400252"]["Value"] == ["IN PROGRESS"])
        return row["uid"]

    def update(name, uid, extra, **kwargs):
        return run(name, "update", ["--mpps-uid", uid, *extra], **kwargs)

    def series_args(images):
        args = ["--study-uid", STUDY, "--series-uid", SERIES, "--protocol-name", "E1-CT",
                "--sop-class-uid", CT]
        for image in images:
            args += ["--image-uid", image]
        return args

    try:
        uid = create("create-ascii")
        row = update("intermediate-explicit", uid, ["--status", "IN PROGRESS", "--procedure-step-description", "FIRST"])
        check("explicit status is carried", row["dataset"]["00400252"]["Value"] == ["IN PROGRESS"])
        check("intermediate has no end fields", "00400250" not in row["dataset"] and "00400251" not in row["dataset"])
        check("scalar update does not empty sequences", "00400340" not in row["dataset"] and "00400260" not in row["dataset"])
        row = update("intermediate-omitted", uid, ["--procedure-step-description", "SECOND"])
        check("omitted status absent on wire", "00400252" not in row["dataset"])
        check("omitted status preserves IN PROGRESS", row["state_after"]["00400252"]["Value"] == ["IN PROGRESS"])
        check("updated scalar stored", row["state_after"]["00400254"]["Value"] == ["SECOND"])
        update("intermediate-sequence", uid, ["--status", "IN PROGRESS", *series_args(IMAGES[:2])])
        before_refs = references(peer.states[uid])
        row = update("scalar-preserves-sequence", uid, ["--procedure-step-description", "THIRD"])
        check("scalar preserves prior image references", references(peer.states[uid]) == before_refs)
        check("unrelated patient value preserved", str(peer.states[uid].PatientName) == "E1^PATIENT")
        update("sequence-replacement", uid, series_args(IMAGES))
        check("full replacement retains all acquired images", references(peer.states[uid]) == {(CT, image) for image in IMAGES})
        update("empty-intermediate-refused", uid, [], successful=False, network=False)
        row = update("complete", uid, ["--status", "COMPLETED", *series_args(IMAGES)])
        check("COMPLETED retained", row["state_after"]["00400252"]["Value"] == ["COMPLETED"])
        check("terminal end date/time supplied", bool(row["dataset"].get("00400250", {}).get("Value")) and bool(row["dataset"].get("00400251", {}).get("Value")))
        row = update("after-complete-refused", uid, ["--procedure-step-description", "TOO LATE"], successful=False)
        check("terminal SCP response 0110", row["status"] == "0110")
        check("refused update preserves terminal data", row["state_after"]["00400254"]["Value"] == ["THIRD"])
        uid = create("create-utf8", ["--specific-character-set", "ISO_IR 192"])
        row = update("same-charset", uid, ["--procedure-step-description", "MÜLLER follow-up", "--specific-character-set", "ISO_IR 192"])
        check("UTF8 decoded correctly", row["state_after"]["00400254"]["Value"] == ["MÜLLER follow-up"])
        check("original charset preserved", charset(peer.states[uid]) == "ISO_IR 192")
        row = update("mismatched-charset-refused", uid, ["--procedure-step-description", "MÜLLER wrong charset", "--specific-character-set", "ISO_IR 100"], successful=False)
        check("mismatched charset status 0106", row["status"] == "0106")
        check("mismatched update did not mutate state", row["state_after"]["00400254"]["Value"] == ["MÜLLER follow-up"])
        uid = create("create-for-discontinuation")
        update("nonascii-without-original-charset-refused", uid, ["--procedure-step-description", "MÜLLER"], successful=False, network=False)
        update("discontinue-without-series-refused", uid, ["--status", "DISCONTINUED"], successful=False, network=False)
        row = update("discontinue-no-images", uid, ["--status", "DISCONTINUED", "--series-uid", SERIES + ".2", "--protocol-name", "NO-IMAGES"])
        check("DISCONTINUED has one empty-image series", len(row["state_after"]["00400340"]["Value"]) == 1 and not references(peer.states[uid]))
        update("after-discontinue-refused", uid, ["--status", "IN PROGRESS", "--procedure-step-description", "TOO LATE"], successful=False)
        check("peer had no implementation exceptions", not peer.errors)
        save(root / "results.json", {
            "result": "Passed", "actions": len(records), "assertions": len(checks),
            "binary_sha256": digest(binary), "script_sha256": digest(pathlib.Path(__file__)),
            "references": REFERENCES,
            "limits": ["Synthetic subset, no full IOD or external PACS certification.",
                       "Each CLI invocation is a separate process: authoritative SCP rejects post-terminal or mismatched-charset requests; same-process SCU preflight is tested separately.",
                       "Wire success is not native GUI evidence; Workshop runs use --serve independently."],
        })
    except Exception as error:
        save(root / "results.json", {"result": "Failed", "error": repr(error),
                                     "actions": len(records), "assertions": len(checks)})
        raise


def seed_external_instance(binary, root, peer):
    """Create through a separate CLI process so Workshop has no local context."""
    argv = [str(binary), "create", "127.0.0.1", "--port", str(peer.port),
            "--aet", "E1WORKSHOP", "--called-aet", "E1MPPS", "--timeout", "5",
            "--study-uid", STUDY + ".9", "--modality", "CT",
            "--patient-id", "E1-EXTERNAL", "--patient-name", "Émile^EXTERNAL",
            "--procedure-step-description", "EXTERNAL BASELINE", "--specific-character-set", "ISO_IR 192"]
    before = len(peer.requests)
    result = subprocess.run(argv, capture_output=True, text=True, timeout=20)
    (root / "external-seed.stdout.txt").write_text(result.stdout)
    (root / "external-seed.stderr.txt").write_text(result.stderr)
    save(root / "external-seed.json", {"argv": argv, "exit": result.returncode,
                                      "binary_sha256": digest(binary)})
    assert result.returncode == 0 and len(peer.requests) == before + 1, "External CLI seed failed"
    row = peer.requests[-1]
    assert row["operation"] == "N-CREATE" and row["status"] == "0000"
    return row["uid"]


def workshop_plan(port, external_uid=None):
    """Use actual Workshop create actions; the harness resolves saved UID names."""
    result = []

    def action(name, operation, values, expected=0, save_uid=None):
        row = {"name": name, "expectedExit": expected, "values": {
            "host": "127.0.0.1", "port": str(port), "aet": "E1WORKSHOP",
            "called-aet": "E1MPPS", "timeout": "5", "operation": operation, **values,
        }}
        if save_uid:
            row["saveUID"] = save_uid
        result.append(row)

    def create(name, key, extra=None):
        action(name, "create", {"study-uid": STUDY, "modality": "CT",
                               "patient-id": "E1-SYNTHETIC", "patient-name": "E1^PATIENT",
                               "procedure-step-description": "BASELINE", **(extra or {})}, save_uid=key)

    def update(name, key, values, expected=0):
        action(name, "update", {"mpps-uid": "$" + key, "status-update": "", **values}, expected)

    series = {"study-uid": STUDY, "series-uid": SERIES, "protocol-name": "E1-CT",
              "sop-class-uid": CT, "image-uid": "; ".join(IMAGES[:2])}
    create("create-ascii", "ascii")
    update("intermediate-explicit", "ascii", {"status-update": "IN PROGRESS", "update-procedure-step-description": "FIRST"})
    update("intermediate-omitted", "ascii", {"update-procedure-step-description": "SECOND"})
    update("intermediate-sequence", "ascii", {"status-update": "IN PROGRESS", **series})
    update("scalar-preserves-sequence", "ascii", {"update-procedure-step-description": "THIRD"})
    update("sequence-replacement", "ascii", {**series, "image-uid": "; ".join(IMAGES)})
    update("empty-intermediate-refused", "ascii", {}, 64)
    update("complete", "ascii", {"status-update": "COMPLETED", **series, "image-uid": "; ".join(IMAGES)})
    update("after-complete-refused", "ascii", {"update-procedure-step-description": "TOO LATE"}, 1)
    create("create-utf8", "utf8", {"specific-character-set": "ISO_IR 192"})
    update("same-charset", "utf8", {"update-procedure-step-description": "MÜLLER follow-up", "specific-character-set": "ISO_IR 192"})
    update("mismatched-charset-refused", "utf8", {"update-procedure-step-description": "MÜLLER wrong charset", "specific-character-set": "ISO_IR 100"}, 1)
    create("create-for-discontinuation", "discontinued")
    update("nonascii-without-original-charset-refused", "discontinued", {"update-procedure-step-description": "MÜLLER"}, 1)
    update("discontinue-without-series-refused", "discontinued", {"status-update": "DISCONTINUED"}, 1)
    update("discontinue-no-images", "discontinued", {"status-update": "DISCONTINUED", "series-uid": SERIES + ".2", "protocol-name": "NO-IMAGES"})
    update("after-discontinue-refused", "discontinued", {"status-update": "IN PROGRESS", "update-procedure-step-description": "TOO LATE"}, 1)
    if external_uid:
        # A failed attempt must not establish the instance's original repertoire.
        action("external-wrong-charset-refused", "update", {
            "mpps-uid": external_uid, "status-update": "",
            "update-procedure-step-description": "WRONG REPERTOIRE",
        }, 1)
        action("external-corrected-charset-retry", "update", {
            "mpps-uid": external_uid, "status-update": "",
            "update-procedure-step-description": "EXTERNAL RETRY",
            "specific-character-set": "ISO_IR 192",
        })
    return result


def verify_workshop(root, action_file):
    """Check captured datasets independently of the app's own success labels."""
    wire = json.loads((root / "requests.json").read_text())
    plan = json.loads((root / "workshop-requests.json").read_text())
    actions = json.loads(action_file.read_text())
    metadata = json.loads((root / "workshop-plan-metadata.json").read_text()) if (root / "workshop-plan-metadata.json").exists() else {}
    external_uid = metadata.get("external_uid")
    requests = [row for row in wire if row["uid"] != external_uid]
    checks = []

    def check(label, condition):
        checks.append({"assertion": label, "result": "Passed" if condition else "Failed"})
        save(root / "workshop-assertions.json", checks)
        assert condition, label

    try:
        check("all Workshop actions recorded", len(actions) == len(plan))
        for expected, actual in zip(plan, actions):
            check(expected["name"] + " exit", expected["name"] == actual["name"] and expected["expectedExit"] == actual["exit"])
        check("exactly eleven base requests reached SCP", len(requests) == 11)
        check("all received requests accepted by independent rules", all(row["status"] == "0000" for row in requests))
        check("no peer implementation exceptions", not json.loads((root / "peer-errors.json").read_text()))
        check("three real N-CREATEs", [row["operation"] for row in requests].count("N-CREATE") == 3)
        check("explicit intermediate status on wire", requests[1]["dataset"]["00400252"]["Value"] == ["IN PROGRESS"])
        check("omitted intermediate status absent", "00400252" not in requests[2]["dataset"])
        check("omitted update retains original state", requests[2]["state_after"]["00400252"]["Value"] == ["IN PROGRESS"])
        for index in [1, 2, 3, 4, 5, 8]:
            check(f"intermediate request {index + 1} has no end fields", "00400250" not in requests[index]["dataset"] and "00400251" not in requests[index]["dataset"])
        for index in [1, 2, 4, 8]:
            check(f"scalar request {index + 1} does not wipe sequences", "00400340" not in requests[index]["dataset"] and "00400260" not in requests[index]["dataset"])
        check("first sequence has two acquired references", references(Dataset.from_json(requests[3]["state_after"])) == {(CT, image) for image in IMAGES[:2]})
        check("scalar update preserves acquired references", requests[3]["state_after"]["00400340"] == requests[4]["state_after"]["00400340"])
        check("full replacement retains three references", references(Dataset.from_json(requests[5]["state_after"])) == {(CT, image) for image in IMAGES})
        completed = Dataset.from_json(requests[6]["state_after"])
        check("complete status and scalar retained", completed.PerformedProcedureStepStatus == "COMPLETED" and completed.PerformedProcedureStepDescription == "THIRD")
        check("complete end date/time present", bool(completed.PerformedProcedureStepEndDate) and bool(completed.PerformedProcedureStepEndTime))
        utf8 = Dataset.from_json(requests[8]["state_after"])
        check("same original UTF8 charset", charset(utf8) == "ISO_IR 192")
        check("UTF8 value survives decoding", utf8.PerformedProcedureStepDescription == "MÜLLER follow-up")
        check("unrelated patient name preserved", str(utf8.PatientName) == "E1^PATIENT")
        stopped = Dataset.from_json(requests[10]["state_after"])
        check("discontinued has nonempty series without invented references", stopped.PerformedProcedureStepStatus == "DISCONTINUED" and len(stopped.PerformedSeriesSequence) == 1 and not references(stopped))
        check("discontinued end date/time present", bool(stopped.PerformedProcedureStepEndDate) and bool(stopped.PerformedProcedureStepEndTime))
        if external_uid:
            external = [row for row in wire if row["uid"] == external_uid]
            check("external charset retry has seed and two wire attempts", len(external) == 3 and len(wire) == 14)
            check("external seed then refused wrong charset then corrected success", [(row["operation"], row["status"]) for row in external] == [("N-CREATE", "0000"), ("N-SET", "0106"), ("N-SET", "0000")])
            check("wrong default declaration omitted on wire", "00080005" not in external[1]["dataset"])
            check("wrong charset attempt preserves entire original dataset", external[1]["state_after"] == external[0]["state_after"])
            check("corrected update explicitly carries original charset", external[2]["dataset"]["00080005"]["Value"] == ["ISO_IR 192"])
            corrected = Dataset.from_json(external[2]["state_after"])
            check("corrected retry succeeds without process restart", corrected.PerformedProcedureStepDescription == "EXTERNAL RETRY" and corrected.PerformedProcedureStepStatus == "IN PROGRESS")
            check("retry retains unrelated Unicode original value", str(corrected.PatientName) == "Émile^EXTERNAL")
        save(root / "workshop-verification.json", {"result": "Passed", "actions": len(actions), "requests": len(wire), "assertions": len(checks), "references": REFERENCES,
                                             "scope": "Actual CLIWorkshop ViewModel execution and independent decoded wire; native UI acceptance is separate"})
    except Exception as error:
        save(root / "workshop-verification.json", {"result": "Failed", "error": repr(error), "assertions": len(checks)})
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--bin-dir", type=pathlib.Path)
    mode.add_argument("--serve", action="store_true")
    mode.add_argument("--verify-workshop", type=pathlib.Path, metavar="ACTION_RESULTS")
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--lifetime", type=float, default=1200)
    parser.add_argument("--seed-bin-dir", type=pathlib.Path,
                        help="With --serve, seed an externally created UTF8 instance using dicom-mpps and add Workshop retry checks")
    args = parser.parse_args()
    root = args.output_dir.resolve()
    if args.verify_workshop:
        verify_workshop(root, args.verify_workshop)
        return
    if args.seed_bin_dir and not args.serve:
        parser.error("--seed-bin-dir requires --serve")
    root.mkdir(parents=True, exist_ok=True)
    if list(root.iterdir()):
        parser.error("Use an empty output directory to preserve earlier evidence")
    if pydicom.__version__ != "3.0.1" or pynetdicom.__version__ != "3.0.4":
        parser.error("Use pinned pydicom 3.0.1 / pynetdicom 3.0.4")
    save(root / "provenance.json", {
        "python": sys.version, "platform": platform.platform(),
        "pydicom": pydicom.__version__, "pynetdicom": pynetdicom.__version__,
        "script_sha256": digest(pathlib.Path(__file__)),
    })
    peer = StrictMPPSPeer(root, args.port)
    try:
        external_uid = seed_external_instance((args.seed_bin_dir / "dicom-mpps").resolve(), root, peer) if args.seed_bin_dir else None
        save(root / "workshop-requests.json", workshop_plan(peer.port, external_uid))
        save(root / "workshop-plan-metadata.json", {"external_uid": external_uid})
        print(json.dumps({"ready": True, "port": peer.port}), flush=True)
        if args.serve:
            deadline = time.monotonic() + args.lifetime
            while not (root / "stop").exists() and time.monotonic() < deadline:
                time.sleep(0.1)
        else:
            exercise_cli((args.bin_dir / "dicom-mpps").resolve(), root, peer)
    finally:
        peer.close()


if __name__ == "__main__":
    main()
