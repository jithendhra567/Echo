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
        let q = searchText.lowercased()
        return clips
            .compactMap { clip -> (Clip, Int)? in
                guard let score = searchScore(clip: clip, query: q) else { return nil }
                return (clip, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func searchScore(clip: Clip, query: String) -> Int? {
        let text   = (clip.plainText ?? clip.attributedString?.string ?? "").lowercased()
        let source = (clip.sourceAppName ?? "").lowercased()
        let window = (clip.windowTitle ?? "").lowercased()
        if text.contains(query)                                          { return 1_000 }
        if source.contains(query) || window.contains(query)              { return   500 }
        if fuzzySequential(query, in: text)                              { return   200 }
        if fuzzySequential(query, in: source) || fuzzySequential(query, in: window) { return 100 }
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
                .frame(maxWidth: 260)
            }

            // Search field — fills remaining middle space
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Search clips…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

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

            // Close button — right side
            Button { viewModel.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Circle().fill(Color.secondary.opacity(0.15)))
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
        if filteredClips.isEmpty {
            Spacer()
            Text(viewModel.clips.isEmpty
                 ? "Copy something to get started"
                 : "No results for \"\(searchText)\"")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(filteredClips) { clip in
                        ClipCardView(clip: clip)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
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
