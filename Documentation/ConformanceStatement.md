# DICOMKit capability and conformance disclosure

**Revision: 26 October 2026. Standard basis: DICOM 2026a. M0–M7 local item criteria accepted; remote verification pending at document creation.**

This document describes the repository's library, CLI and DICOMStudio capabilities and their observed limits. It replaces the April 2026 statement's unconditional support marks. It is an engineering disclosure, not a complete PS3.2 conformance statement for every application built with these libraries. A deployed application must identify its actual AEs, configuration, negotiated SOP Classes/transfer syntaxes, security policy and interoperability results.

The source reference is branch `codex/dicom-2026a-milestones` at c9001dd with the separately hashed UPS/JSON repair overlay. Current source/artifact manifests and reuse boundaries are in [M7 verification](2026a-milestones/M7/verification.json). This is not a release/version declaration.

## Meaning of the capability states

| State | Meaning |
|---|---|
| Implemented | A source execution path exists. This alone does not establish interoperability or complete standard coverage. |
| Limited | Implemented for the stated inputs, route, configuration or tested subset. |
| Refused | The requested operation is intentionally rejected; recognizing a name/UID is not support. |
| Unqualified / pending | The specified runtime, peer, platform or acceptance gate has not been established by the cited evidence. |

Local qualification in the 2026a milestone records uses **macOS arm64**, Xcode 27 / Swift 6.4, synthetic objects and bounded software peers. The records do not establish all-platform behavior, all SOP/IOD requirements, diagnostic fidelity, clinical fitness or physical-device compatibility. Parser/validator success and storage negotiation do not validate every mandatory or conditional attribute of an IOD.

## Implementation and network roles

DICOMCore supplies encoding, text, value and codec primitives; DICOMKit supplies files, datasets and conversion; DICOMDictionary supplies tag and SOP registries. DICOMNetwork supplies DIMSE services. DICOMWeb supplies clients and server request handlers. CLI tools and DICOMStudio expose selected paths; the compatibility DICOMToolbox API is a separate surface.

| Capability | Actual scope and state |
|---|---|
| Part 10 files and attributes | Implemented reading/writing, tag/VR/VM checks, identity synchronization and character-set-aware edits. [M2](2026a-milestones/M2/REPORT.md) qualifies its bounded attribute fixes, not every IOD. |
| Verification | Implemented C-ECHO SCU and SCP; configurable AE Titles and endpoints. |
| Storage | Implemented C-STORE services. `dicom-server` accepts classes in the [Storage SOP registry](../Sources/DICOMDictionary/StorageSOPClasses.swift), subject to negotiated transfer syntax. This is a registry/transport contract, not proof that every listed modality is rendered, generated or fully validated. |
| Query/Retrieve | Implemented Patient Root and Study Root FIND/MOVE/GET clients and `dicom-server` handlers. The six Q/R UIDs are enumerated in [ServerProtocol](../Sources/dicom-server/ServerProtocol.swift). [M3](2026a-milestones/M3/REPORT.md) and [M4](2026a-milestones/M4/REPORT.md) qualify specific filters, cancellation, counters and durable storage cases. |
| MWL, MPPS and UPS | Service/CLI implementations exist. Their existence does not qualify every workflow, external system or optional transaction; use the applicable tests and milestone criteria. |
| Storage commitment | Implementation exists; a complete deployment-specific durable commitment/interoperability claim is unqualified here. |

For `dicom-server`, the accepted transfer-syntax preference is Explicit VR Little Endian, Implicit VR Little Endian, then retired Explicit VR Big Endian. File codec availability does **not** imply that this SCP negotiates compressed transfer syntaxes. Its default maximum PDU size is 16,384 bytes; actual configuration and peer negotiation determine the session. Other services have their own association configurations.

File writing and `dicom-server` use Implementation Class UID `1.2.826.0.1.3680043.10.511.3.0.5.0` and Implementation Version Name `DICOMKIT_0.5.0`, from [DICOMFile+Write](../Sources/DICOMKit/DICOMFile+Write.swift). These protocol identifiers are not a repository release number; inspect each service's actual association identity when qualifying a deployment.

## Transfer syntax and pixel conversion

The [conversion catalog](../Sources/DICOMKit/DICOMConverter.swift) contains **25 selectable targets covering 21 UIDs**. Separate lossy/reversible choices share some general-purpose UIDs. Catalog membership is not a promise that the requested encoder can produce every image. The following applies to file conversion, not all network presentation contexts.

| Family / UID suffix under `1.2.840.10008.1.2` | Read/decode | Write/encode and limits |
|---|---|---|
| Implicit VR LE (base UID), Explicit VR LE `.1`, retired Explicit VR BE `.2` | Implemented | Implemented; retired BE is a compatibility route. |
| Deflated Explicit VR LE `.1.99` | Implemented | Implemented; package/platform dependencies apply. |
| JPEG Baseline `.4.50` | Limited to supported JPEG/image descriptors | Implemented 8-bit process; not a 12/16-bit JPEG encoder. |
| JPEG Extended `.4.51` | Limited | Grayscale implementation. Color encoding is refused. The M7 correction emits SOF1 for 8-bit grayscale; independent DCMTK decoding and explicit SOF1 inspection pass for the recorded 8/12-bit samples. Pre-fix output is not validated Extended JPEG. |
| JPEG Lossless `.4.57`, SV1 `.4.70` | Limited | Implemented within supported precision/component descriptors. Strict precision checks described below apply. |
| JPEG 2000 `.4.90` lossless-only, `.4.91` general | Limited | Implemented; general UID has distinct lossy and reversible target choices. |
| JPEG 2000 Part 2 `.4.92`, `.4.93` | Limited; genuine unsupported multi-component transform content is refused | **Refused** by the current route planner. Three catalog target choices remain recognizable, but do not provide an encoder. |
| HTJ2K `.4.201`, RPCL lossless `.4.202`, general `.4.203` | Limited | Implemented routes; general UID has lossy/reversible choices. No exhaustive bit-depth, progression, malformed-stream or accelerator qualification. |
| JPEG-LS `.4.80` lossless, `.4.81` near-lossless | Limited | Implemented. The earlier “JPEG-LS not supported” statement is obsolete. Strict precision/descriptor checks apply. |
| JPEG XL `.4.110` lossless, `.4.112` general | Limited | Implemented; general UID has lossy/reversible choices. Not an all-profile/interoperability guarantee. |
| JPEG XL JPEG recompression `.4.111` | Limited | Specialized JPEG-bitstream recompression, not arbitrary native-pixel encoding. Current source restricts eligible source syntax/precision; see the catalog and transcoder. |
| RLE `.5` | Implemented for supported pixel descriptors | Implemented; finite independent fixtures do not exhaust every descriptor/layout. |

The codec registry includes J2KSwift 11.0.3, JLSwift 0.10.1, JXLSwift 1.4.0 and JliSwift 0.6.0 in the current [resolved dependencies](../Package.resolved). Platform-specific backends and conditional imports affect availability. Recognition of additional UIDs in `TransferSyntax` does not imply a registered decoder or encoder.

The strict JPEG/JPEG-LS paths reject the exercised peer objects whose codestream precision is 16 while dataset Bits Stored is 12. This is an explicit interoperability limit; it must not be counted as successful decoding or relabeled universal peer nonconformance. Pixel metadata and compressed-stream consistency are governed by PS3.5 §8.2 and the applicable Annex A transfer syntax. The final M7 codec campaign records **78 passes, 10 supported refusals and two strict-precision interoperability limits**, with zero unexpected failures. These are finite synthetic cases on macOS arm64, not an all-target or all-platform claim; see [M7 verification](2026a-milestones/M7/verification.json). Native decompression now selects OW from Bits Allocated/implicit encoding, preserves target word order and pads only the final complete Pixel Data value. Eager implicit-VR parsing also selects OW; explicit OB/OW input is preserved for validation.

JPIP Referenced `.4.94` / `.4.95` and JPIP HTJ2K Referenced `.4.204` / `.4.205` describe externally referenced pixel delivery. UID recognition is not normal `dicom-convert` pixel-codec support or qualification of a JPIP service. MPEG/video UID recognition similarly does not establish a video encoder/decoder contract in this statement. Experimental private JP3D uses a private SOP/runtime route; it is not a standard DICOM transfer syntax or qualified clinical interchange feature.

## Text and attribute encoding

The strict edit path recognizes the allowed declaration combinations in [CharacterSetHandler](../Sources/DICOMCore/CharacterSetHandler.swift), including the default repertoire, permitted single-byte sets, UTF-8, GB18030/GBK and supported ISO 2022 extensions. Unknown/invalid declarations, undeclared escape designations and unrepresentable target edits are refused. The tolerant legacy read helper accepts additional aliases; those are not valid declaration claims.

M2 evidence includes default/Latin-1, UTF-8 and Japanese ISO 2022 round trips, nested inherited/overridden declarations, significant whitespace and transactional edits. A supported declaration name does not qualify every character or every platform encoding backend. See [M2 verification](2026a-milestones/M2/verification.json) for the exact automated and packaged-app cases.

## DICOMweb: client and server are different surfaces

The server is request-handling logic integrated through an HTTP bridge; it is not, by itself, a deployed HTTPS listener. Provider behavior and authentication are part of the deployment contract.

| Transaction | Client | Server handler and qualification boundary |
|---|---|---|
| QIDO | Implemented six resource forms | All studies, all series, series in study, all instances, instances in study, instances in series. Resource-aware keys, pagination and response projection are qualified in M3. There is no seventh “single study” QIDO form. Third-party providers must adopt the canonical matching contract; otherwise filtered searches return 501. |
| WADO instances and metadata | Implemented | Six study/series/instance object and JSON-metadata retrieval routes were exercised over HTTP in M4. |
| Frames, rendered images, thumbnails, bulk data | Client request APIs exist; remote support required | **Refused with 501** in the current server. Bulk data is not advertised as supported. |
| XML metadata | Client/server media support is route-specific | Current server does not implement `application/dicom+xml` metadata. |
| STOW | Implemented | Instance/multipart storage handler exists; this statement does not qualify every media type, failure combination or IOD. |
| UPS | Implemented operations | Workitem handlers exist with an optional UPS provider. Full subscription/event/deployment conformance is unqualified here. |
| Service capabilities | Client/deployment-specific use | Service-base OPTIONS supports PS3.18 §8.9 WADL XML / Annex G JSON with media negotiation. CORS preflight is separate. M4 tests cross-check advertised implemented routes. |
| DELETE study/series/instance | Extension-specific | Repository extension, not a standard PS3.18 storage transaction. |

The [M4 report](2026a-milestones/M4/REPORT.md) and [capability evidence](2026a-milestones/M4/evidence/capabilities/results.json) delimit tested resource/method/media behavior. HTTPS, access control and persistence must be supplied and qualified by the deployment.

## Print Management and Workshop

Implemented SCU/SCP paths include Basic Grayscale and Basic Color Print Management, Film Session/Film Box/Image Box, Printer N-GET, optional Presentation LUT/Annotation Box, and Print Job query/events. Negotiated contexts and SCP configuration control optional availability. [Print context definitions](../Sources/DICOMNetwork/PrintPresentationContexts.swift) and [SCP configuration](../Sources/DICOMNetwork/PrintSCPTypes.swift) define the exact SOP set.

[M6 evidence](2026a-milestones/M6/REPORT.md) records **24 passing independent software-peer cases and one DCMTK peer limitation**, plus **25 CLI/ViewModel comparisons across all 10 print commands**. The independent peers have complementary capabilities; DCMTK's disabled-LUT probe accepted the context and is unqualified as a refusal test. The separate pynetdicom case verifies actual refused-context behavior. Terminal Print Job acknowledgment/lifetime and accepted B604 warnings are covered by specific cases.

Native packaged DICOMStudio CLI Workshop print acceptance is complete for all ten commands within the recorded finite software scope. All 28 native groups are accepted within the recorded scope; exact next pushed-head CI was pending at document creation. Existing SCP tolerance for color Planar Configuration 0 is compatibility behavior; strict outbound color uses 1 and the negative test uses invalid value 2. There is no physical printer, real OS paper queue, film-density, calibration or diagnostic-quality qualification.

## Security and transport disclosure

| Surface | State and boundary |
|---|---|
| DIMSE TCP | Implemented unsecured transport. AE Titles are routing identifiers, not proof of authentication. |
| `dicom-server --tls` / `enableTLS=true` | TLS listener is **not implemented**. M7 changes configuration validation to refuse before storage/listener startup, rather than silently opening plaintext. Final actual CLI checks verify refusal for the flag alone, configuration true, and configuration false combined with the flag; no storage directory or listener is created. |
| DIMSE CLI clients | No general TLS command-line option is exposed; library TLS capability must not be represented as CLI TLS support. |
| DICOMNetwork TLS | Library configuration/connection paths implement TLS 1.2/1.3 through platform networking/security APIs. The final independent campaign passes four C-ECHO cases across TLS 1.2/1.3 and four trust/hostname/protocol refusals, corroborated by eight valid endpoint controls and peer TLS alerts. Complete PS3.15 profile qualification is not claimed. |
| Certificate policy | Library verification, configured trust/pinning and client identity options exist. Mutual TLS, revocation behavior and the complete required cipher/profile matrix remain unqualified here. Insecure configuration is not a secure profile. |
| DICOMweb authentication | Basic, supplied Bearer token, API-key and custom-header client mechanisms exist. Supplying a Bearer header is not a complete OAuth2 authorization flow or server access-control implementation. |
| User Identity Negotiation | Protocol structures exist; complete endpoint authentication/authorization behavior is not qualified by their presence. |
| Audit | The network logger emits DICOMKit JSON-Lines/OSLog records. It is **not** the PS3.15 Annex A.5 audit-message format and does not establish IHE ATNA conformance. |

PS3.15 2026a B.12/B.13 transport-profile claims require the complete applicable version, cipher and certificate requirements, not merely a successful TLS handshake. No blanket AES-256, mutual-TLS, revocation or ATNA guarantee is made. See [TLSConfiguration](../Sources/DICOMNetwork/TLSConfiguration.swift) and [AuditLogger](../Sources/DICOMNetwork/AuditLogger.swift) for implemented primitives.

## Platform and qualification limits

[Package.swift](../Package.swift) declares Swift tools 6.4 and deployment floors macOS 15, iOS 18, tvOS 18 and visionOS 2. These are package declarations, not runtime qualifications. The source records a visionOS dependency-floor limitation; no successful visionOS, iOS, tvOS, Linux or other-platform runtime campaign is claimed here. CPU/GPU fallback, codec dependency behavior and resource limits require platform-specific verification.

Private dictionaries, SR/RT/segmentation parsing, image viewing, anonymization and validation are implemented capabilities with separate coverage. A known private tag or a rendered object does not prove vendor completeness, anonymization against every identifying field, complete IOD correctness or safe clinical use. Outstanding findings and exclusions remain in the [milestone ledger](2026a-milestones/items.json); this document does not waive them.

## Standard and evidence references

The milestone records use frozen official DICOM **2026a** source hashes rather than an unversioned “current” standard. Relevant parts are [PS3.2](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part02/PS3.2.html) for application conformance statements, [PS3.3](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part03/PS3.3.html) for IODs, [PS3.4](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part04/PS3.4.html) for service classes, [PS3.5](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part05/PS3.5.html) for encoding, [PS3.6](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part06/PS3.6.html) for registered identifiers, PS3.7/PS3.8 for DIMSE/transport, PS3.10 for files, [PS3.15](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part15/PS3.15.html) for security profiles and [PS3.18](https://dicom.nema.org/medical/dicom/2026a/output/chtml/part18/PS3.18.html) for web services.

The [M6 source/evidence record](2026a-milestones/M6/verification.json) and [final M7 qualification record](2026a-milestones/M7/verification.json) distinguish automated tests, independent software peers and all 28 bounded native groups including fresh repaired UPS acceptance. The historical M7 campaign binaries passed 34 independent network cases and 24 print cases; DC-F07 remains a peer limitation, with the actual optional-context refusal covered independently by PY-F08. Local M7 item acceptance is recorded; exact next pushed-head remote CI, merge, release and deployment approval are not asserted by this revision.

## Qualification-discovered UPS and JSON repairs

Client UPS creation now preserves valid collection-body identity, supports validated explicit query identity, rejects conflicts locally and generates a client UID when absent. Strict CLI/public-client tests and the rebuilt native UPS Create/Get/refusal pass against the independent strict peer. Actual app identity/relaunch and 54 assertions are recorded; no full UPS IOD/server claim follows. Existing server UID-less fallback remains permissive and unqualified. No full UPS server or lifecycle claim is added.

The JSON decoder now binds its actual UTF-8 text context; the complete DICOMWeb product passes after the real M2 integration regression, invalid encoder fixture and stale capability expectations were corrected. Original failures remain in the M7 evidence, with exact classification. Earlier focused runs are not described as baseline full-product passes.

Remote state above is the immutable snapshot recorded at 2026-10-26T09:34:23.083422+00:00. Consult [the milestone branch Actions](https://github.com/raster-labs/DICOMKit/actions?query=branch%3Acodex%2Fdicom-2026a-milestones) for current status; the final user report and remote receipt bind the actual pushed revision after verification.
