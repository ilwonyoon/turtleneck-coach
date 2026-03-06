enum CameraSourceMode: String, CaseIterable {
    case auto
    case manual
}

struct CameraDeviceOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let modelID: String
    let isVirtual: Bool

    init(uniqueID: String, displayName: String, modelID: String, isVirtual: Bool) {
        self.id = uniqueID
        self.displayName = displayName
        self.modelID = modelID
        self.isVirtual = isVirtual
    }
}
