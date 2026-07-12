import SwiftUI

struct ClipDashboardView: View {
    @Environment(ClipViewModel.self) private var viewModel
    @State private var searchText = ""
    @State private var selectedTag: ClipTag = .all

    private var filteredClips: [Clip] {
        var clips = viewModel.clips
        if selectedTag != .all {
            clips = clips.filter { $0.autoTag == selectedTag }
        }
        guard !searchText.isEmpty else { return clips }
        let q = searchText
        return clips
            .compactMap { clip -> (Clip, Int)? in
                guard let score = searchScore(clip: clip, query: q) else { return nil }
                return (clip, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func searchScore(clip: Clip, query: String) -> Int? {
        let text = clip.searchableText ?? ""
        let source = clip.sourceAppName ?? ""
        let window = clip.windowTitle ?? ""
        if text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return 1_000 }
        if source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || window.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return 500
        }
        let textLower = text.lowercased()
        let sourceLower = source.lowercased()
        let windowLower = window.lowercased()
        let q = query.lowercased()
        if fuzzySequential(q, in: textLower) { return 200 }
        if fuzzySequential(q, in: sourceLower) || fuzzySequential(q, in: windowLower) { return 100 }
        return nil
    }

    private func fuzzySequential(_ query: String, in text: String) -> Bool {
        var idx = text.startIndex
        for ch in query {
            guard let found = text[idx...].firstIndex(of: ch) else { return false }
            idx = text.index(after: found)
        }
        return true
    }

    private var availableTags: [ClipTag] {
        let usedTags = Set(viewModel.clips.map(\.autoTag))
        return [.all] + ClipTag.allCases.filter { $0 != .all && usedTags.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            cardArea
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(6)
    }

    // MARK: - Single control bar (tags + search + close in one row)

    private var controlBar: some View {
        HStack(spacing: 10) {

            // Tag pills — left side, capped width so search always has room
            if availableTags.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableTags, id: \.self) { tag in
                            TagPill(label: tag.rawValue, isSelected: selectedTag == tag) {
                                selectedTag = tag
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxWidth: 220)
            }

            // Search field — text can be dragged out without recording a new clip.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Search clips…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .textSelection(.enabled)

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
            )
            .frame(maxWidth: .infinity)
            .onDrag {
                guard !searchText.isEmpty else { return NSItemProvider() }
                viewModel.prepareExternalDrag(for: 2)
                return NSItemProvider(object: searchText as NSString)
            }

            PlainTextPasteToggle(style: .panel)
                .fixedSize()

            Spacer(minLength: 0)

            Button { viewModel.dismiss() } label: {
                Text("Close")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.red.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Card area

    @ViewBuilder
    private var cardArea: some View {
        Group {
            if filteredClips.isEmpty {
                Text(viewModel.clips.isEmpty
                     ? "Copy something to get started"
                     : "No results for \"\(searchText)\"")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(filteredClips) { clip in
                            ClipCardView(clip: clip)
                        }
                        if canLoadMorePages {
                            paginationTail
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(height: 205)
    }

    private var canLoadMorePages: Bool {
        searchText.isEmpty && selectedTag == .all && viewModel.hasMorePanelClips
    }

    private var paginationTail: some View {
        Group {
            if viewModel.isLoadingPanelPage {
                ProgressView()
                    .controlSize(.small)
            } else {
                Color.clear
            }
        }
        .frame(width: 48, height: 185)
        .onAppear { viewModel.loadNextPanelPage() }
    }
}

// MARK: - Tag pill

private struct TagPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15)))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
