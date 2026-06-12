import AppKit
import Foundation
import RDPKit
import SwiftUI

/// Opens and tracks remote session windows and their diagnostics windows.
@MainActor
final class SessionLaunchStore: ObservableObject, RemoteSessionOpening {
    @Published private(set) var openSessionCount = 0

    /// True while a remote session window is the key window; drives the
    /// contextual Session menu in the menu bar.
    @Published private(set) var isSessionWindowKey = false

    /// Command state of the key session window; nil while none is key.
    @Published private(set) var keySessionCommands: SessionCommandState?

    func updateKeySessionCommands(_ state: SessionCommandState?) {
        if keySessionCommands != state {
            keySessionCommands = state
        }
    }

    private var sessionWindowControllers: [UUID: SessionWindowController] = [:] {
        didSet {
            openSessionCount = sessionWindowControllers.count
        }
    }

    func noteSessionWindowKey(_ isKey: Bool) {
        if isSessionWindowKey != isKey {
            isSessionWindowKey = isKey
        }
    }

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

    /// Opens a session window for the draft, or focuses the existing window if
    /// this device already has one.
    @discardableResult
    func openRemoteSession(_ draft: RDPConnectionDraft) -> UUID {
        if let deviceID = draft.deviceID,
           let existing = sessionWindowControllers.values.first(where: { $0.deviceID == deviceID })
        {
            existing.showWindow(nil)
            return existing.sessionID
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
        return id
    }

    func recordConnectionStart(for deviceID: UUID?) {
        guard let deviceID else {
            return
        }
        onConnectionStart?(deviceID)
    }

    func recordCredentialPersistence(for deviceID: UUID?, identity: RDPConnectionIdentity, remembered: Bool) {
        guard let deviceID else {
            return
        }
        onCredentialPersistence?(deviceID, identity, remembered)
    }

    var hasOpenSessions: Bool {
        openSessionCount > 0
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

    func unregisterDiagnostics(for id: UUID) {
        diagnosticsModels.removeValue(forKey: id)
        diagnosticsWindowControllers.removeValue(forKey: id)?.close()
    }
}
