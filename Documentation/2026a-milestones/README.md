# DICOM 2026a milestones

This is the current implementation ledger for the 24 October 2026 review at
`4b68d7e22829418c88e48dd53d98b25fee50d90d`. The review produced 68 action items:
The original scope covered 46 items. On 26 October 2026 the user additionally
authorized NET-08-A, WS-DORM-01 and WS-DORM-02 as E1: 49 items are now in scope
and 19 remain deferred. M0–M7 receipts remain historical evidence for their source.

- [Milestone plan and CLI/app acceptance gates](PLAN.md)
- [Current completed and pending status](STATUS.md)
- [All 68 items and their acceptance criteria](items.json)
- [M0 source, standard, fixture and command baseline](M0/baseline.json)
- [M0 verification and evidence index](M0/verification.json)
- [M0 reproduction and later qualification procedure](M0/REPRODUCE.md)
- [M1 completion report](M1/REPORT.md)
- [M1 verification and reproduction](M1/REPRODUCE.md)
- [M2 completion report](M2/REPORT.md)
- [M2 verification and reproduction](M2/REPRODUCE.md)
- [Existing print command contracts for the later M6 milestone](print-cli-contract.json)

Use **one branch**, `codex/dicom-2026a-milestones`, for the milestone series.
The current authorization is **E1 only**, following completed M0–M7. Update STATUS.md,
items.json and the [E1 report](E1/REPORT.md) with executed evidence before pushing.
Do not merge into main; the user retains merge authority.

The older standard-implementation reports are dated historical evidence. Their
earlier “complete” labels do not close the behavioral findings in this ledger.
M0 repairs audit infrastructure; it changes no Swift product behavior.
