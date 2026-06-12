import SwiftUI

/// The main window: a searchable grid of saved PCs, in the spirit of the
/// macOS Windows App connection center.
struct ConnectionCenterView: View {
    @EnvironmentObject private var deviceList: DeviceListModel
    @EnvironmentObject private var launchStore: SessionLaunchStore

    @State private var selectedDeviceID: UUID?

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 18),
    ]

    var body: some View {
        Group {
            if deviceList.devices.isEmpty {
                ConnectionCenterEmptyState {
                    deviceList.addNewDevice()
                }
            } else {
                deviceGrid
            }
        }
        .frame(minWidth: 740, minHeight: 480)
        .navigationTitle("RDPeek")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    deviceList.addNewDevice()
                } label: {
                    Label("Add PC", systemImage: "plus")
                }
                .help("Add a PC (⌘N)")
            }

            ToolbarItem {
                Menu {
                    Picker("Sort By", selection: $deviceList.sortOrder) {
                        ForEach(DeviceSortOrder.allCases) { order in
                            Text(verbatim: order.title).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort devices")
            }
        }
        .searchable(
            text: $deviceList.searchText,
            placement: .toolbar,
            prompt: "Search devices"
        )
        .sheet(item: $deviceList.editorState) { editorState in
            DeviceEditorSheet(editorState: editorState)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: deletionBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let device = deviceList.devicePendingDeletion {
                    deviceList.confirmDeletion(of: device)
                }
            }
            Button("Cancel", role: .cancel) {
                deviceList.devicePendingDeletion = nil
            }
        } message: {
            Text("The saved password for this PC is removed from your Keychain too. This cannot be undone.")
        }
        .alert(
            "Something Went Wrong",
            isPresented: errorBinding,
            actions: {
                Button("OK") {
                    deviceList.errorMessage = nil
                }
            },
            message: {
                Text(verbatim: deviceList.errorMessage ?? "")
            }
        )
        .onAppear {
            launchStore.onConnectionStart = { deviceID in
                deviceList.touchLastConnected(deviceID: deviceID)
            }
            launchStore.onCredentialPersistence = { deviceID, identity, remembered in
                deviceList.recordCredentialPersistence(
                    deviceID: deviceID,
                    identity: identity,
                    remembered: remembered
                )
            }
        }
    }

    private var deviceGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(deviceList.filteredDevices) { device in
                    DeviceCardView(
                        device: device,
                        isSelected: selectedDeviceID == device.id,
                        onSelect: { selectedDeviceID = device.id },
                        onConnect: { connect(device) },
                        onEdit: { deviceList.edit(device) },
                        onDuplicate: { deviceList.duplicate(device) },
                        onDelete: { deviceList.requestDeletion(of: device) }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .padding(20)
            .animation(.spring(duration: 0.35, bounce: 0.15), value: deviceList.filteredDevices.map(\.id))
        }
        .overlay {
            if deviceList.filteredDevices.isEmpty {
                ContentUnavailableView.search(text: deviceList.searchText)
            }
        }
        .background {
            // Return connects the selection; Delete asks to remove it.
            Button("") {
                if let device = selectedDevice {
                    connect(device)
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .opacity(0)

            Button("") {
                if let device = selectedDevice {
                    deviceList.requestDeletion(of: device)
                }
            }
            .keyboardShortcut(.delete, modifiers: [])
            .opacity(0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDeviceID = nil
        }
    }

    private var selectedDevice: DeviceProfile? {
        deviceList.filteredDevices.first { $0.id == selectedDeviceID }
    }

    private func connect(_ device: DeviceProfile) {
        selectedDeviceID = device.id
        deviceList.connect(device, using: launchStore)
    }

    private var deletionTitle: String {
        guard let device = deviceList.devicePendingDeletion else {
            return "Delete PC?"
        }
        return "Delete “\(device.displayName)”?"
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { deviceList.devicePendingDeletion != nil },
            set: { isPresented in
                if isPresented == false {
                    deviceList.devicePendingDeletion = nil
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { deviceList.errorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    deviceList.errorMessage = nil
                }
            }
        )
    }
}

/// First-run state with a gentle breathing beacon and a single clear action.
struct ConnectionCenterEmptyState: View {
    var onAddDevice: () -> Void

    @State private var isBreathing = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 132, height: 132)
                    .scaleEffect(isBreathing ? 1.06 : 0.97)
                    .animation(
                        .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
                        value: isBreathing
                    )

                Image(systemName: "display")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 8) {
                Text("No PCs Yet")
                    .font(.title2.weight(.semibold))
                Text("Add your first PC to start a remote desktop session.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                onAddDevice()
            } label: {
                Label("Add PC", systemImage: "plus")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isBreathing = true
        }
    }
}
