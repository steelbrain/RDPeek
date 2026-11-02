import AppKit
import Combine
import Foundation
import RDPKit

/// Opens and tracks remote session windows and their diagnostics windows.
@MainActor
final class SessionLaunchStore: ObservableObject, RemoteSessionOpening {
    /// Command state of the key session window, published while it is key
    /// and nil while no session window is; drives the contextual Session
    /// menu in the menu bar.
    @Published private(set) var keySessionCommands: SessionCommandState?

    var isSessionWindowKey: Bool {
        keySessionCommands != nil
    }

    func updateKeySessionCommands(_ state: SessionCommandState?) {
        if keySessionCommands != state {
            keySessionCommands = state
        }
    }

    private var sessionWindowControllers: [UUID: SessionWindowController] = [:]
    private var savedDevicesSubscription: AnyCancellable?
    private var diagnosticsWindowControllers: [UUID: DiagnosticsWindowController] = [:]
    private var diagnosticsModels: [UUID: RemoteSessionDiagnosticsModel] = [:]

    /// Called when a connection attempt starts, so the device list can record
    /// the most recent connection.
    var onConnectionStart: ((UUID) -> Void)?

    /// Called when a session saved or deleted a keychain credential, so the
    /// profile's remember-password flag stays truthful. Carries the identity
    /// the credential was stored under: the sign-in overlay can use a
    /// different username than the profile, and only a matching profile may
    /// have its flag updated.
    var onCredentialPersistence: ((UUID, RDPConnectionIdentity, _ remembered: Bool) -> Void)?

    /// Called when a session's sign-in, which the server verified, was
    /// kept, so a PC saved with no user name takes the account.
    var onAcceptedSignIn: ((UUID, RDPConnectionIdentity) -> Void)?

    /// Whether a profile other than the given one remembers its password
    /// under the identity, so the Keychain item must stay.
    var passwordRememberedElsewhere: ((RDPConnectionIdentity, _ excludingDeviceID: UUID) -> Bool)?

    /// Opens a session window for the draft, or focuses the existing window if
    /// this device already has one; that window connects again, with the
    /// PC as saved, when its session ended.
    func openRemoteSession(_ draft: RDPConnectionDraft) {
        if let existing = sessionWindowControllers.values.first(where: { $0.deviceID == draft.deviceID }) {
            existing.sessionController.followSavedDevice(draft)
            existing.showWindow(nil)
            existing.sessionController.connectFromSavedDevice()
            return
        }

        let id = UUID()
        let preferredScreen = NSApp.keyWindow?.screen ?? NSScreen.main
        let controller = SessionWindowController(
            sessionID: id,
            draft: draft,
            launchStore: self,
            preferredScreen: preferredScreen
        )
        controller.onClose = { [weak self] sessionID in
            self?.sessionWindowControllers.removeValue(forKey: sessionID)
        }
        sessionWindowControllers[id] = controller
        controller.showWindow(nil)
    }

    /// Keeps open session windows in step with the saved PCs: each follows
    /// its PC's saved settings, and one whose PC was deleted keeps no
    /// password for it.
    func followSavedDevices(_ devices: some Publisher<[DeviceProfile], Never>) {
        savedDevicesSubscription = devices.sink { [weak self] devices in
            self?.savedDevicesChanged(devices)
        }
    }

    private func savedDevicesChanged(_ devices: [DeviceProfile]) {
        for controller in sessionWindowControllers.values {
            if let device = devices.first(where: { $0.id == controller.deviceID }) {
                controller.sessionController.followSavedDevice(RDPConnectionDraft(device: device))
            } else {
                controller.sessionController.savedDeviceWasDeleted()
            }
        }
    }

    func recordConnectionStart(for deviceID: UUID) {
        onConnectionStart?(deviceID)
    }

    func isPasswordRemembered(for identity: RDPConnectionIdentity, byOtherThan deviceID: UUID) -> Bool {
        passwordRememberedElsewhere?(identity, deviceID) ?? false
    }

    func recordCredentialPersistence(for deviceID: UUID, identity: RDPConnectionIdentity, remembered: Bool) {
        onCredentialPersistence?(deviceID, identity, remembered)
    }

    func recordAcceptedSignIn(for deviceID: UUID, identity: RDPConnectionIdentity) {
        onAcceptedSignIn?(deviceID, identity)
    }

    /// The PC editor saved a new password for the identity: windows signing
    /// in as it find that password from the next connection the user
    /// starts, rather than send the one they signed in with.
    func savedPasswordChanged(for identity: RDPConnectionIdentity) {
        for controller in sessionWindowControllers.values {
            controller.sessionController.savedPasswordChanged(for: identity)
        }
    }

    func registerDiagnostics(_ model: RemoteSessionDiagnosticsModel, for id: UUID) {
        diagnosticsModels[id] = model
    }

    func openDiagnostics(for id: UUID) {
        if let controller = diagnosticsWindowControllers[id] {
            controller.showWindow(nil)
            return
        }

        guard let model = diagnosticsModels[id] else {
            return
        }

        let controller = DiagnosticsWindowController(
            sessionID: id,
            title: model.snapshot.title,
            model: model
        )
        controller.onClose = { [weak self] sessionID in
            self?.diagnosticsWindowControllers.removeValue(forKey: sessionID)
        }
        diagnosticsWindowControllers[id] = controller
        controller.showWindow(nil)
    }

    func isShowingDiagnostics(for id: UUID) -> Bool {
        diagnosticsWindowControllers[id] != nil
    }

    func unregisterDiagnostics(for id: UUID) {
        diagnosticsModels.removeValue(forKey: id)
        diagnosticsWindowControllers.removeValue(forKey: id)?.close()
    }
}
