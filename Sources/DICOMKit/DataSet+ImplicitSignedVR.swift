import DICOMCore
import DICOMDictionary

extension DataSet {
    /// Implicit VR carries no on-wire VR. Resolve the US/SS dictionary alternatives
    /// after the entire dataset is available, including inherited item context.
    /// Explicit VR parsing must never call this: its recorded VR remains evidence.
    func resolvingImplicitSignedVR() -> DataSet {
        DataSet(elements: Self.resolveSignedElements(allElements, inherited: nil))
    }

    private static func resolveSignedElements(_ elements: [DataElement], inherited: UInt16?) -> [DataElement] {
        let representation: UInt16?
        if let local = elements.first(where: { $0.tag == .pixelRepresentation }) {
            representation = local.vr == .US && local.valueData.count == 2
                && (local.uint16Value ?? 2) <= 1 ? local.uint16Value : nil
        } else {
            representation = inherited
        }
        return elements.map { element in
            if let items = element.sequenceItems {
                let resolved = items.map { SequenceItem(elements: resolveSignedElements($0.allElements, inherited: representation)) }
                return DataElement(tag: element.tag, vr: element.vr, length: element.length,
                                   valueData: element.valueData, sequenceItems: resolved, byteOrder: element.byteOrder)
            }
            guard element.vr == .US || element.vr == .SS, let representation,
                  let entry = DataElementDictionary.lookup(tag: element.tag),
                  Set(entry.vr) == Set([VR.US, .SS]) else { return element }
            return DataElement(tag: element.tag, vr: representation == 1 ? .SS : .US,
                               length: element.length, valueData: element.valueData,
                               byteOrder: element.byteOrder, specificCharacterSet: element.specificCharacterSet)
        }
    }
}
