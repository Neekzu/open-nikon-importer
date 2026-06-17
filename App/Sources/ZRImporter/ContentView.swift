import AVKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: CameraImportModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            contentArea
            Divider()
            footer
        }
        .frame(minWidth: 1180, minHeight: 680)
        .onChange(of: model.selectedIDs) {
            model.selectionDidChange()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.cameraName)
                    .font(.headline)
                Text(model.connectionStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.refresh()
            } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
            .help("Katalog neu lesen")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Filter")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    filterControl
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Ansicht")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    displayModeControl
                }

                Text("\(model.visibleFiles.count) Dateien · \(model.visibleTotalSizeLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 5)

                Spacer()

                Button {
                    model.chooseDestination()
                } label: {
                    Label("Ziel", systemImage: "folder")
                }
                .disabled(!model.canChangeDestination)
                .help("Importziel wählen")

                Button {
                    model.revealDestination()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Ziel im Finder zeigen")
            }

            statusChipRow

            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                Text(model.destinationURL.path(percentEncoded: false))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }

            if let note = model.systemNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error = model.lastErrorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var filterControl: some View {
        HStack(spacing: 1) {
            ForEach(FileFilter.allCases) { filter in
                segmentedButton(
                    title: filter.rawValue,
                    selected: model.filter == filter,
                    width: 66
                ) {
                    model.filter = filter
                }
            }
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var displayModeControl: some View {
        HStack(spacing: 1) {
            ForEach(DisplayMode.allCases) { mode in
                segmentedButton(
                    title: mode.rawValue,
                    selected: model.displayMode == mode,
                    width: 92
                ) {
                    model.displayMode = mode
                }
            }
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func segmentedButton(
        title: String,
        selected: Bool,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(width: width, height: 26)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .background(selected ? Color(nsColor: .selectedControlColor).opacity(0.72) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var statusChipRow: some View {
        HStack(spacing: 8) {
            ForEach(model.workflowStatusChips) { chip in
                workflowStatusChip(chip)
            }
        }
    }

    private func workflowStatusChip(_ chip: WorkflowStatusChip) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(for: chip.kind))
                .frame(width: 7, height: 7)
            Text(chip.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(chip.value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .overlay(
            Capsule()
                .stroke(statusColor(for: chip.kind).opacity(chip.kind == .idle ? 0.16 : 0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var contentArea: some View {
        if !model.hasConnectedCamera {
            noCameraOnboarding
        } else {
            HSplitView {
                Group {
                    if model.visibleFiles.isEmpty {
                        emptyCatalogState
                    } else if model.displayMode == .list {
                        fileTable
                    } else {
                        thumbnailGrid
                    }
                }
                .frame(minWidth: 720, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                detailPanel
                    .frame(minWidth: 320, idealWidth: 400, maxWidth: 520)
            }
        }
    }

    private var noCameraOnboarding: some View {
        VStack(spacing: 22) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 58, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Kamera per USB-C verbinden")
                    .font(.title2.weight(.semibold))
                Text("Kamera einschalten, MTP/PTP-Transfermodus nutzen und danach den Katalog aktualisieren.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
            }

            HStack(spacing: 10) {
                onboardingStep("1", "USB-C")
                onboardingStep("2", "MTP/PTP")
                onboardingStep("3", "Aktualisieren")
            }

            Button {
                model.refresh()
            } label: {
                Label("Katalog aktualisieren", systemImage: "arrow.clockwise")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func onboardingStep(_ number: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(label)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyCatalogState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.magnifyingglass")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(model.files.isEmpty ? "Keine importierbaren Dateien gefunden" : "Keine Dateien im aktuellen Filter")
                .font(.headline)
            Text(model.files.isEmpty ? "Der Katalog ist leer oder macOS meldet noch keine sichtbaren Medien." : "Filter ändern oder den Katalog erneut lesen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button {
                model.refresh()
            } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var fileTable: some View {
        Table(model.visibleFiles, selection: $model.selectedIDs) {
            TableColumn("Name") { item in
                HStack(spacing: 8) {
                    thumbnailView(for: item, size: CGSize(width: 62, height: 40))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .lineLimit(1)
                        if let proxy = model.pairedProxy(for: item) {
                            Text("Proxy: \(proxy.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .width(min: 260, ideal: 360)

            TableColumn("Format") { item in
                HStack(spacing: 6) {
                    Text(model.mediaKind(for: item).label)
                    if !item.fileExtension.isEmpty {
                        Text(item.fileExtension)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.14), in: Capsule())
                    }
                    if item.sourceLabel == "PTP" {
                        Text("PTP")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.18), in: Capsule())
                    }
                }
                .foregroundStyle(.secondary)
            }
            .width(150)

            TableColumn("Datum") { item in
                Text(item.createdAt.map(Self.dateFormatter.string(from:)) ?? "-")
                    .foregroundStyle(.secondary)
            }
            .width(180)

            TableColumn("Größe") { item in
                Text(item.sizeLabel)
                    .foregroundStyle(.secondary)
            }
            .width(120)

            TableColumn("Status") { item in
                statusView(for: item)
            }
            .width(min: 180, ideal: 260)
        }
    }

    private var thumbnailGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 246), spacing: 14, alignment: .topLeading)],
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(model.visibleFiles) { item in
                    thumbnailCard(for: item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func thumbnailCard(for item: CameraFileItem) -> some View {
        let selected = model.selectedIDs.contains(item.id)

        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                thumbnailSurface(for: item)

                Text(model.mediaKind(for: item).label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.62), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(7)
            }

            Text(item.name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .frame(minHeight: 30, alignment: .topLeading)

            HStack(spacing: 6) {
                Text(item.createdAt.map(Self.shortDateFormatter.string(from:)) ?? "-")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(item.sizeLabel)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let proxy = model.pairedProxy(for: item) {
                Label(proxy.name, systemImage: "rectangle.on.rectangle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor.opacity(0.86) : Color.secondary.opacity(0.12), lineWidth: selected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            model.select(item)
        }
        .onTapGesture(count: 2) {
            model.preview(item)
        }
    }

    private func thumbnailSurface(for item: CameraFileItem) -> some View {
        ZStack {
            if let image = model.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(nsColor: .underPageBackgroundColor)
                Image(systemName: iconName(for: item))
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(iconColor(for: item))
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .background(.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let item = model.selectedItem {
                    previewSection(for: item)
                    metadataSection(for: item)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Keine Datei ausgewählt")
                            .font(.headline)
                        Text("Dateien auswählen, um Details und Vorschau zu sehen.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func previewSection(for item: CameraFileItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName(for: item))
                    .foregroundStyle(iconColor(for: item))
                Text(model.mediaKind(for: item).label)
                    .font(.headline)
                Spacer()
                if item.isRawVideo {
                    Text(item.fileExtension)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(iconColor(for: item).opacity(0.16), in: Capsule())
                }
            }

            previewSurface(for: item)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(item.name)
                .font(.callout.weight(.semibold))
                .lineLimit(2)

            if let status = model.previewStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    model.previewSelection(openQuickLook: true)
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .keyboardShortcut(.space, modifiers: [])

                if let url = model.previewURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .help("Preview-Datei im Finder zeigen")
                }
            }
        }
    }

    @ViewBuilder
    private func previewSurface(for item: CameraFileItem) -> some View {
        if let url = model.previewURL {
            let ext = url.pathExtension.uppercased()
            if ["MOV", "MP4", "M4V"].contains(ext) {
                VideoPreviewView(url: url)
            } else if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.86))
            } else {
                previewPlaceholder(for: item, title: "Lokale Datei bereit")
            }
        } else {
            previewPlaceholder(for: item, title: model.mediaKind(for: item).label)
        }
    }

    private func previewPlaceholder(for item: CameraFileItem, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: iconName(for: item))
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(iconColor(for: item))
            Text(title)
                .font(.headline)
            Text(item.sizeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func thumbnailView(for item: CameraFileItem, size: CGSize) -> some View {
        ZStack {
            if let image = model.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(nsColor: .underPageBackgroundColor)
                Image(systemName: iconName(for: item))
                    .font(.system(size: min(size.width, size.height) * 0.42, weight: .semibold))
                    .foregroundStyle(iconColor(for: item))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .background(.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private func metadataSection(for item: CameraFileItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workflow")
                .font(.headline)

            metadataRows(model.workflowRows(for: item))

            let technicalRows = model.technicalRows(for: item)
            if !technicalRows.isEmpty {
                DisclosureGroup {
                    metadataRows(technicalRows)
                        .padding(.top, 6)
                } label: {
                    Text("Technische Details")
                        .font(.headline)
                }
            }
        }
    }

    private func metadataRows(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow(alignment: .top) {
                    Text(row.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 112, alignment: .leading)
                    Text(row.1)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(row.0 == "Lokal" ? 3 : 2)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.importSelected()
            } label: {
                Label("Auswahl importieren", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canImportSelection)
            .help("Ausgewählte Dateien importieren")

            Button {
                model.importVisible()
            } label: {
                Label("Sichtbare importieren", systemImage: "tray.and.arrow.down")
            }
            .disabled(!model.canImportAllVisible)
            .help("Alle aktuell gefilterten Dateien importieren")

            Button {
                model.previewSelection(openQuickLook: true)
            } label: {
                Label("Preview", systemImage: "eye")
            }
            .disabled(model.selectedItem == nil)
            .help("Ausgewählte Datei mit Space/Quick Look previewen")

            Spacer()

            if model.lastImportedFolder != nil {
                Button {
                    model.revealLastImport()
                } label: {
                    Label("Im Finder zeigen", systemImage: "finder")
                }
                .help("Letzten Import im Finder öffnen")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func statusView(for item: CameraFileItem) -> some View {
        switch model.importStates[item.id] ?? .idle {
        case .idle:
            if let reason = item.unavailableReason {
                Label("Blockiert", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(reason)
            } else {
                Text("")
            }
        case .queued:
            Label("Wartet", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .importing(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 60)
                Text("\(Int(progress * 100)) %")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .complete:
            Label("Fertig", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "xmark.octagon.fill")
                Text("Fehler")
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .foregroundStyle(.red)
            .help(message)
        }
    }

    private func iconName(for item: CameraFileItem) -> String {
        if item.fileExtension == "NEV" { return "film.stack" }
        if item.fileExtension == "R3D" { return "record.circle" }
        if model.mediaKind(for: item) == .videoProxy { return "rectangle.on.rectangle" }
        if item.isMovie { return "film" }
        if item.isRaw { return "camera.aperture" }
        return "photo"
    }

    private func iconColor(for item: CameraFileItem) -> Color {
        if item.fileExtension == "NEV" { return .purple }
        if item.fileExtension == "R3D" { return .red }
        if model.mediaKind(for: item) == .videoProxy { return .cyan }
        if item.isMovie { return .blue }
        if item.isRaw { return .purple }
        return .green
    }

    private func statusColor(for kind: WorkflowStatusKind) -> Color {
        switch kind {
        case .ready:
            return .green
        case .working:
            return .blue
        case .warning:
            return .orange
        case .blocked:
            return .red
        case .idle:
            return .secondary
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct VideoPreviewView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .background(.black)
            .onAppear {
                player = AVPlayer(url: url)
            }
            .onDisappear {
                player?.pause()
            }
            .onChange(of: url) { _, newURL in
                player?.pause()
                player = AVPlayer(url: newURL)
            }
    }
}
