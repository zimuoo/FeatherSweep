import CleanerCore
import SwiftUI

struct CleanerView: View {
    @ObservedObject var model: CleanerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedCategories = Set<CleanupCategory>()
    @State private var expandedMessages = Set<String>()

    init(model: CleanerViewModel, initiallyExpandedCategories: Set<CleanupCategory> = []) {
        self.model = model
        _expandedCategories = State(initialValue: initiallyExpandedCategories)
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
                .padding(.horizontal, 21)
                .padding(.top, 9)
                .padding(.bottom, 13)
            Divider().padding(.horizontal, 20)
            ScrollView {
                VStack(spacing: 0) {
                    if model.result != nil {
                        Text("以下为清理前的扫描结果")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7)
                    }
                    ForEach(CleanupCategory.allCases) { category in
                        categoryRow(category)
                        if category != CleanupCategory.allCases.last { Divider() }
                    }
                    if let retained = model.report?.retainedBackups, !retained.isEmpty {
                        retainedGroup(retained)
                    }
                    if let completion = model.completionDescription {
                        Label(completion, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.12, green: 0.45, blue: 0.23))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .textSelection(.enabled)
                    }
                    ForEach(Array(model.details.enumerated()), id: \.offset) { _, group in
                        messageGroup(group.title, messages: group.messages)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 18))
                        .foregroundStyle(Branding.blue)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("保留密码、Cookie 与登录状态")
                            .font(.system(size: 12))
                        Text(model.isDemo ? "仅模拟，不修改文件 · 实际清理不进废纸篓" : "只清理勾选项 · 直接删除，不进废纸篓")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Color(red: 0.30, green: 0.36, blue: 0.45))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color(red: 0.95, green: 0.965, blue: 0.98), in: RoundedRectangle(cornerRadius: 9))
                HStack {
                    Text(model.selectionSummary)
                        .monospacedDigit()
                    Spacer()
                    if !model.isBusy && model.selectedCount == 0 {
                        Text("请先勾选要清理的项目")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("selectionSummary")
                HStack(spacing: 10) {
                    Button(action: model.scan) {
                        Label("查看垃圾", systemImage: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.isBusy)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("扫描并查看符合安全规则的文件（⌘R）")
                    .accessibilityIdentifier("scanButton")
                    Button(action: model.clean) {
                        Label("清理垃圾", systemImage: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(CleanerPrimaryButtonStyle())
                    .controlSize(.large)
                    .disabled(!model.canClean)
                    .help(model.selectedCount == 0 ? "请先勾选要清理的项目" : (model.isDemo ? "仅模拟清理所选项目，不会修改任何文件" : "重新核验所选项目后直接删除，不进废纸篓"))
                    .accessibilityIdentifier("cleanButton")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .frame(width: 460, height: 592)
        .background(Color.white)
        .tint(Branding.blue)
        .preferredColorScheme(.light)
    }

    private var summary: some View {
        HStack(spacing: 21) {
            DiskRingView(isBusy: model.isBusy, isCleaning: model.phase == .cleaning, isComplete: model.phase == .completed,
                         reduceMotion: reduceMotion)
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(model.summaryTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    if model.isDemo {
                        Text("演示")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .foregroundStyle(Branding.blue)
                            .background(Branding.blue.opacity(0.08), in: Capsule())
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(model.summaryAmount.number)
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .tracking(-2)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(model.displayedBytes)))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.36), value: model.displayedBytes)
                    Text(model.summaryAmount.unit)
                        .font(.system(size: 24, weight: .medium))
                }
                .foregroundStyle(Color(red: 0.05, green: 0.08, blue: 0.13))
                .help("\(model.displayedBytes.formatted()) 字节")
                Text(model.status)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("operationStatus")
                if model.isBusy {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 3)
                        .accessibilityLabel(model.phase == .scanning ? "扫描进度" : "清理进度")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 116)
    }

    private func categoryRow(_ category: CleanupCategory) -> some View {
        let candidates = model.candidates(for: category)
        let bytes = candidates.reduce(Int64(0)) { $0 + $1.estimatedBytes }
        let expanded = expandedCategories.contains(category)
        let selected = model.selectedCount(for: category)
        let bindings = candidates.map { candidate in
            Binding(get: { model.isSelected(candidate.id) }, set: { model.setSelected($0, for: candidate.id) })
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Group {
                    if bindings.isEmpty {
                        // An empty collection toggle otherwise renders as checked.
                        Toggle("选择\(category.title)的全部项目", isOn: .constant(false))
                    } else {
                        // A nonempty collection toggle provides the native mixed state.
                        Toggle("选择\(category.title)的全部项目", sources: bindings, isOn: \.self)
                    }
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .disabled(!model.canSelect || candidates.isEmpty)
                .accessibilityValue("已选 \(selected) / \(candidates.count) 项")
                .help("勾选或取消整个分类；请先阅读右侧影响说明")
                .accessibilityIdentifier("categorySelection-\(category.rawValue)")
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        if expanded { expandedCategories.remove(category) }
                        else { expandedCategories.insert(category) }
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(Branding.blue)
                            .frame(width: 23)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(category.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.primary)
                                if selected > 0 {
                                    Text("已选\(selected)/\(candidates.count)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Branding.blue)
                                        .fixedSize()
                                }
                            }
                            Text(model.categoryImpactSummary(for: category))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(model.report == nil ? "—" : CleanerViewModel.bytes(bytes))
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.55))
                            .frame(width: 9)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(category.title)，\(model.report == nil ? "尚未扫描" : CleanerViewModel.bytes(bytes))，\(model.categoryImpactSummary(for: category))")
                .accessibilityValue(expanded ? "已展开" : "已折叠")
                .accessibilityHint("查看每项影响、路径与清理依据")
                .accessibilityIdentifier("categoryDetails-\(category.rawValue)")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    if candidates.isEmpty {
                        Text(model.report == nil ? "扫描后显示路径与清理依据" : "未发现符合安全规则的文件")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { candidate in
                        candidateRow(candidate)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(red: 0.965, green: 0.972, blue: 0.98), in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 8)
            }
        }
    }

    private func candidateRow(_ candidate: CleanupCandidate) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Toggle("选择\(candidate.path)", isOn: Binding(
                get: { model.isSelected(candidate.id) },
                set: { model.setSelected($0, for: candidate.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
            .disabled(!model.canSelect)
            .accessibilityHint(candidate.impactDetail)
            .accessibilityIdentifier("candidateSelection-\(candidate.id)")
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.impactTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(candidate.impactDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(candidate.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(candidate.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(CleanerViewModel.bytes(candidate.estimatedBytes)) · \(candidate.estimatedBytes.formatted()) 字节 · \(candidate.fileCount) 个文件")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if let retained = candidate.retainedPath {
                    Text("保留：\(retained)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func retainedGroup(_ paths: [String]) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedMessages.contains("retained") },
            set: { if $0 { expandedMessages.insert("retained") } else { expandedMessages.remove("retained") } }
        )) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(paths, id: \.self) { path in
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
        } label: {
            Label("保留的最新快照与备份（\(paths.count)）", systemImage: "checkmark.shield")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }

    private func messageGroup(_ title: String, messages: [String]) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedMessages.contains(title) },
            set: { if $0 { expandedMessages.insert(title) } else { expandedMessages.remove(title) } }
        )) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
        } label: {
            Label("\(title)（\(messages.count)）", systemImage: "exclamationmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.65, green: 0.36, blue: 0.05))
        }
        .padding(.vertical, 7)
    }
}

private struct CleanerPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .background(isEnabled ? Branding.blue.opacity(configuration.isPressed ? 0.80 : 1) : Color(red: 0.93, green: 0.94, blue: 0.95),
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct DiskRingView: View {
    let isBusy: Bool
    let isCleaning: Bool
    let isComplete: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || !isBusy)) { timeline in
            let angle = isBusy && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) * 90 : 0
            ZStack {
                ZStack {
                    ForEach(0..<6) { index in
                        Circle()
                            .trim(from: CGFloat(index) / 6 + 0.022, to: CGFloat(index + 1) / 6 - 0.022)
                            .stroke(Branding.blue.opacity([1.0, 0.94, 0.78, 0.53, 0.30, 0.20][index]),
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
                .rotationEffect(.degrees(angle))
                if isCleaning && !reduceMotion {
                    ForEach(0..<7) { index in
                        let phase = (timeline.date.timeIntervalSinceReferenceDate / 1.4 + Double(index) / 7)
                            .truncatingRemainder(dividingBy: 1)
                        let direction = Double(index) * .pi * 2 / 7
                        let radius = 19 + phase * 23
                        Circle()
                            .fill(Branding.blue.opacity(0.38 * (1 - phase)))
                            .frame(width: index.isMultiple(of: 2) ? 4 : 3, height: index.isMultiple(of: 2) ? 4 : 3)
                            .offset(x: cos(direction) * radius, y: sin(direction) * radius)
                    }
                }
                ZStack {
                    if isComplete {
                        CompletionMark(reduceMotion: reduceMotion)
                            .frame(width: 58, height: 58)
                    } else {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 32, weight: .regular))
                            .foregroundStyle(Color(red: 0.34, green: 0.39, blue: 0.47))
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isComplete)
            }
            .padding(6)
        }
    }
}

private struct CompletionMark: View {
    let reduceMotion: Bool
    @State private var appeared = false
    private let green = Color(red: 0.16, green: 0.66, blue: 0.33)

    var body: some View {
        ZStack {
            Circle()
                .fill(green.opacity(0.12))
                .scaleEffect(appeared ? 1 : 0.72)
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.74), value: appeared)
            CompletionTick()
                .trim(from: 0, to: appeared ? 1 : 0)
                .stroke(green, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .padding(12)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.28).delay(0.08), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

private struct CompletionTick: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.52))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.79))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.91, y: rect.minY + rect.height * 0.22))
        }
    }
}

private extension CleanupCategory {
    var symbol: String {
        switch self {
        case .compilation: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "sparkles"
        case .temporary: return "doc.text"
        case .updates: return "icloud.and.arrow.down"
        case .webCache: return "externaldrive"
        case .blender: return "arrow.triangle.2.circlepath"
        case .daily: return "clock.arrow.circlepath"
        }
    }
}
