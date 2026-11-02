import SwiftUI

/// The main window: a searchable grid of saved PCs, in the spirit of the
/// macOS Windows App connection center.
struct ConnectionCenterView: View {
    @EnvironmentObject private var deviceList: DeviceListModel
    let launchStore: SessionLaunchStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDeviceID: UUID?
    @FocusState private var isGridFocused: Bool
    /// How many cards a grid row holds, for moving the selection up and down.
    @State private var columnCount = 1

    private let columns = [
        GridItem(
            .adaptive(minimum: DeviceGridNavigation.cardMinimumWidth, maximum: DeviceGridNavigation.cardMaximumWidth),
            spacing: DeviceGridNavigation.spacing
        ),
    ]

    var body: some View {
        let devices = deviceList.filteredDevices
        Group {
            if deviceList.loadFailed {
                // Not the empty state: its Add PC would fail to save.
                ContentUnavailableView(
                    "Saved PCs Can't Be Read",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The saved PC list can't be read by this version of RDPeek and is kept unchanged.")
                )
            } else if deviceList.devices.isEmpty {
                ConnectionCenterEmptyState {
                    deviceList.addNewDevice()
                }
            } else {
                deviceGrid(devices)
            }
        }
        // For Edit PC and Duplicate PC in the File menu. None while the
        // editor or the Delete dialog is up, which they would replace.
        .focusedSceneValue(
            \.selectedDevice,
            deviceList.editorState == nil && deviceList.devicePendingDeletion == nil
                ? devices.first { $0.id == selectedDeviceID }
                : nil
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            if deviceList.unreadableDeviceCount > 0 {
                UnreadableDevicesNotice(count: deviceList.unreadableDeviceCount) {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        deviceList.dismissUnreadableDeviceNotice()
                    }
                }
                .transition(.opacity)
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
            DeviceEditorSheet(editorState: editorState) { device in
                connect(device)
            }
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
            Text("Its saved password is removed from your Keychain too, unless another PC remembers the same sign-in. This cannot be undone.")
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
    }

    /// `devices` is `filteredDevices`, which `body` computes once per update.
    private func deviceGrid(_ devices: [DeviceProfile]) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: DeviceGridNavigation.spacing) {
                    ForEach(devices) { device in
                        DeviceCardView(
                            device: device,
                            isSelected: selectedDeviceID == device.id,
                            onSelect: { select(device.id) },
                            onConnect: { connect(device) },
                            onEdit: { deviceList.edit(device) },
                            onDuplicate: { deviceList.duplicate(device) },
                            onDelete: { deviceList.requestDeletion(of: device) }
                        )
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .onGeometryChange(for: Int.self) { geometry in
                    DeviceGridNavigation.columnCount(forWidth: geometry.size.width)
                } action: { count in
                    columnCount = count
                }
                .padding(20)
                .animation(.spring(duration: 0.35, bounce: 0.15), value: devices.map(\.id))
            }
            .overlay {
                if devices.isEmpty {
                    ContentUnavailableView.search(text: deviceList.searchText)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                select(nil)
            }
            // Return connects the selection and Delete asks to remove it, only
            // while the grid has keyboard focus: as window-wide shortcuts they
            // also fired while typing in the search field. The arrow keys
            // move the selection.
            .focusable(interactions: .edit)
            .focusEffectDisabled()
            .focused($isGridFocused)
            .onKeyPress(.return) {
                guard let device = devices.first(where: { $0.id == selectedDeviceID }) else {
                    return .ignored
                }
                connect(device)
                return .handled
            }
            .onDeleteCommand {
                if let device = devices.first(where: { $0.id == selectedDeviceID }) {
                    deviceList.requestDeletion(of: device)
                }
            }
            .onMoveCommand { direction in
                guard let index = DeviceGridNavigation.index(
                    after: direction,
                    from: devices.firstIndex { $0.id == selectedDeviceID },
                    count: devices.count,
                    columns: columnCount
                ) else {
                    return
                }
                select(devices[index].id)
                scrollProxy.scrollTo(devices[index].id)
            }
        }
    }

    /// Selecting, or clicking the empty grid, also gives the grid keyboard
    /// focus, so Return, Delete and the arrow keys act on the selection.
    private func select(_ deviceID: UUID?) {
        selectedDeviceID = deviceID
        isGridFocused = true
    }

    private func connect(_ device: DeviceProfile) {
        select(device.id)
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

/// The PC selected in the Connection Center.
struct SelectedDeviceKey: FocusedValueKey {
    typealias Value = DeviceProfile
}

extension FocusedValues {
    var selectedDevice: DeviceProfile? {
        get { self[SelectedDeviceKey.self] }
        set { self[SelectedDeviceKey.self] = newValue }
    }
}

/// Says that saved PCs this version cannot read — damaged, or from a newer
/// RDPeek — are left out of the grid but kept, so none seems lost.
private struct UnreadableDevicesNotice: View {
    let count: Int
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label {
                Text(verbatim: message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
            .font(.callout)

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var message: String {
        count == 1
            ? "1 saved PC can't be read by this version of RDPeek and is kept unchanged."
            : "\(count) saved PCs can't be read by this version of RDPeek and are kept unchanged."
    }
}

/// First-run state with a gentle breathing beacon and a single clear action.
/// The beacon holds still under Reduce Motion.
struct ConnectionCenterEmptyState: View {
    var onAddDevice: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        reduceMotion ? nil : .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
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
            isBreathing = reduceMotion == false
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            isBreathing = reduceMotion == false
        }
    }
}
