import SwiftUI

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @State private var isStaleExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let status = model.status {
                        sessionsList(status)
                    }
                    else {
                        Text(model.isRefreshing ? "Reading agents…" : "agent-hub did not answer")
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 520)
            Divider()
            footer
        }
        .frame(width: 440)
        .onAppear { model.panelDidOpen() }
        .onDisappear { model.panelDidClose() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Agent Hub").font(.headline)
            if let generatedAt = model.status?.generatedAt {
                Text(generatedAt, style: .relative).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Toggle("Open edited files on focus", isOn: $model.isOpeningEditedFilesOnFocus)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help("Refresh now")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func sessionsList(_ status: PanelStatus) -> some View {
        let active = status.sessions.filter { $0.state != "stale" }
        let stale = status.sessions.filter { $0.state == "stale" }

        if status.isAgentTabsAvailable == false {
            Label("Agent Tabs plugin is not reachable", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
        }

        ForEach(active) { session in
            SessionRow(session: session, model: model)
        }

        if stale.isEmpty == false {
            DisclosureGroup(isExpanded: $isStaleExpanded) {
                ForEach(stale) { session in
                    SessionRow(session: session, model: model)
                }
            } label: {
                Text("\(stale.count) stale sessions").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let clones = model.status?.clones {
                cloneLine("Unity", clones.filter(\.isUnityOpen).map(\.name))
                cloneLine("Free", clones.filter(\.isFree).map(\.name))
            }
            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func cloneLine(_ title: String, _ names: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).frame(width: 36, alignment: .leading)
            Text(names.isEmpty ? "—" : names.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SessionRow: View {
    let session: PanelSession
    @ObservedObject var model: PanelModel
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(stateColor).frame(width: 8, height: 8).padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.title).fontWeight(.medium).lineLimit(1)
                    Text(session.projectName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(stateLabel).font(.caption2.weight(.semibold)).foregroundStyle(stateColor)
                    Text(formatIdle(session.idleSeconds)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if let preview = session.waitingFor ?? session.lastMessagePreview, preview.isEmpty == false {
                    Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            HStack(spacing: 2) {
                if session.artifactUrl != nil {
                    Button { model.openArtifact(session) } label: { Image(systemName: "doc.richtext") }
                        .help("Open the agent's artifact in the browser")
                }
                Button { model.showAgent(session) } label: { Image(systemName: "arrow.up.forward.app") }
                    .disabled(session.hasTerminalTab == false)
                    .help(focusHelp)
            }
            .buttonStyle(.borderless)
            .padding(.top, 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .onHover { isHovered = $0 }
    }

    private var focusHelp: String {
        guard session.hasTerminalTab else { return "No Rider terminal tab found for this session" }
        let files = session.reviewFiles.count
        return model.isOpeningEditedFilesOnFocus && files > 0 ? "Show the agent's tab and open \(files) edited files" : "Show the agent's tab in Rider"
    }

    private var stateLabel: String {
        switch session.state {
        case "review": return session.reviewFiles.isEmpty ? "REVIEW" : "REVIEW · \(session.reviewFiles.count)"
        default: return session.state.uppercased()
        }
    }

    private var stateColor: Color {
        switch session.state {
        case "waiting": return .orange
        case "review": return .green
        case "working": return .blue
        case "stale": return .red.opacity(0.7)
        default: return .secondary
        }
    }

    private func formatIdle(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }
}
