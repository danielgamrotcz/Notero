import SwiftUI
import Charts

struct VaultStatisticsView: View {
    @EnvironmentObject var appState: AppState
    @State private var stats = VaultStats()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Overview Section
                GroupBox("Overview") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()), GridItem(.flexible()),
                        GridItem(.flexible()), GridItem(.flexible())
                    ], spacing: 16) {
                        statCard("Notes", "\(stats.totalNotes)")
                        statCard("Folders", "\(stats.totalFolders)")
                        statCard("Words", "\(stats.totalWords)")
                        statCard("Characters", "\(stats.totalCharacters)")
                        statCard("Avg words/note", "\(stats.avgWordsPerNote)")
                        statCard("Orphan notes", "\(stats.orphanCount)")
                        statCard("Vault size", stats.vaultSizeString)
                        statCard("Links", "\(stats.totalLinks)")
                    }
                    .padding(.vertical, 8)
                }

                if let longest = stats.longestNote {
                    GroupBox("Notable") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Longest note: \(longest.name) (\(longest.words) words)")
                                .font(.system(size: 12))
                            if let mostLinked = stats.mostLinkedNote {
                                Text("Most linked: \(mostLinked.name) (\(mostLinked.links) incoming links)")
                                    .font(.system(size: 12))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Word Count Distribution
                GroupBox("Word Count Distribution") {
                    Chart(stats.wordDistribution) { item in
                        BarMark(
                            x: .value("Range", item.range),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .frame(height: 150)
                    .padding(.vertical, 8)
                }

                // Notes per Folder
                if !stats.notesPerFolder.isEmpty {
                    GroupBox("Notes per Folder") {
                        Chart(stats.notesPerFolder) { item in
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Folder", item.folder)
                            )
                            .foregroundStyle(Color.accentColor)
                        }
                        .frame(height: min(300, CGFloat(max(100, stats.notesPerFolder.count * 30))))
                        .padding(.vertical, 8)
                    }
                }

                // Activity Heatmap
                GroupBox("Writing Activity (Last 52 Weeks)") {
                    GeometryReader { geo in
                        ActivityHeatmapView(data: stats.dailyActivity, availableWidth: geo.size.width)
                    }
                    .frame(height: 140)
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 750, minHeight: 550)
        .background(Color(nsColor: NSColor(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255, alpha: 1)))
        .onAppear { computeStats() }
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func computeStats() {
        let vault = appState.vaultManager
        let files = vault.allMarkdownFiles()
        var totalWords = 0
        var totalChars = 0
        var totalLinks = 0
        var longestNote: (name: String, words: Int)?
        var linkCounts: [String: Int] = [:]
        var folderCounts: [String: Int] = [:]
        var wordBuckets = [0, 0, 0, 0] // 0-100, 100-500, 500-1000, 1000+

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let words = content.split { $0.isWhitespace || $0.isNewline }.count
            totalWords += words
            totalChars += content.count

            if words > (longestNote?.words ?? 0) {
                longestNote = (name, words)
            }

            // Word distribution
            if words < 100 { wordBuckets[0] += 1 }
            else if words < 500 { wordBuckets[1] += 1 }
            else if words < 1000 { wordBuckets[2] += 1 }
            else { wordBuckets[3] += 1 }

            // Folder counting
            let folder = file.deletingLastPathComponent().lastPathComponent
            folderCounts[folder, default: 0] += 1

            // Link counting
            let links = content.wikilinks()
            totalLinks += links.count
            for link in links {
                linkCounts[link.linkName, default: 0] += 1
            }
        }

        // Count folders
        var totalFolders = 0
        func countFolders(_ nodes: [FileTreeNode]) {
            for node in nodes {
                if case .folder(let folder) = node {
                    totalFolders += 1
                    countFolders(folder.children)
                }
            }
        }
        countFolders(vault.fileTree)

        // Orphan notes — notes that are neither linked to nor contain outgoing links
        let linkedNames = Set(linkCounts.keys.map { $0.lowercased() })
        var orphanCount = 0
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent.lowercased()
            if linkedNames.contains(name) { continue }
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let hasOutgoing = !content.wikilinks().isEmpty
            if !hasOutgoing {
                orphanCount += 1
            }
        }

        // Vault size
        let vaultSize = directorySize(url: vault.vaultURL)

        // Most linked note
        let mostLinked = linkCounts.max(by: { $0.value < $1.value })

        stats = VaultStats(
            totalNotes: files.count,
            totalFolders: totalFolders,
            totalWords: totalWords,
            totalCharacters: totalChars,
            avgWordsPerNote: files.isEmpty ? 0 : totalWords / files.count,
            totalLinks: totalLinks,
            orphanCount: orphanCount,
            vaultSizeString: ByteCountFormatter.string(fromByteCount: Int64(vaultSize), countStyle: .file),
            longestNote: longestNote.map { LongestNote(name: $0.name, words: $0.words) },
            mostLinkedNote: mostLinked.map { MostLinkedNote(name: $0.key, links: $0.value) },
            wordDistribution: [
                WordDistItem(range: "0-100", count: wordBuckets[0]),
                WordDistItem(range: "100-500", count: wordBuckets[1]),
                WordDistItem(range: "500-1K", count: wordBuckets[2]),
                WordDistItem(range: "1K+", count: wordBuckets[3])
            ],
            notesPerFolder: folderCounts.map { FolderCount(folder: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
                .prefix(10).map { $0 },
            dailyActivity: loadDailyActivity()
        )
    }

    private func directorySize(url: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += size
        }
        return total
    }

    private func loadDailyActivity() -> [DailyWordCount] {
        let defaults = UserDefaults.standard
        let calendar = Calendar.current
        var result: [DailyWordCount] = []

        for dayOffset in (0..<365).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let key = "goal-\(formatter.string(from: date))"
            let count = defaults.integer(forKey: key)
            result.append(DailyWordCount(date: date, words: count))
        }

        return result
    }
}

// MARK: - Activity Heatmap

struct ActivityHeatmapView: View {
    let data: [DailyWordCount]
    var availableWidth: CGFloat? = nil
    @State private var hoveredDay: DailyWordCount?

    var body: some View {
        let calendar = Calendar.current
        let cellSize: CGFloat = 14
        let gap: CGFloat = 2

        let maxWeeks: Int = if let availableWidth {
            min(53, Int(availableWidth / (cellSize + gap)))
        } else {
            53
        }

        VStack(alignment: .leading, spacing: 2) {
            // Tooltip
            if let day = hoveredDay {
                Text("\(day.date.formatted(.dateTime.month(.wide).day())) · \(day.words) words")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(height: 14)
            } else {
                Color.clear.frame(height: 14)
            }

            Canvas { context, size in
                let weeks = min(maxWeeks, data.count / 7 + 1)
                for (index, day) in data.suffix(weeks * 7).enumerated() {
                    let weekIndex = index / 7
                    let dayIndex = index % 7

                    let x = CGFloat(weekIndex) * (cellSize + gap)
                    let y = CGFloat(dayIndex) * (cellSize + gap)
                    let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)

                    let color = heatmapColor(words: day.words)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))

                    // Current day border
                    if calendar.isDateInToday(day.date) {
                        context.stroke(Path(roundedRect: rect, cornerRadius: 2),
                                     with: .color(.accentColor), lineWidth: 1)
                    }
                }
            }
            .frame(width: CGFloat(maxWeeks) * (cellSize + gap), height: 7 * (cellSize + gap))
        }
    }

    private func heatmapColor(words: Int) -> Color {
        if words == 0 { return Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255) }
        if words <= 100 { return Color.accentColor.opacity(0.25) }
        if words <= 300 { return Color.accentColor.opacity(0.50) }
        if words <= 700 { return Color.accentColor.opacity(0.75) }
        return Color.accentColor
    }
}

// MARK: - Models

struct VaultStats {
    var totalNotes = 0
    var totalFolders = 0
    var totalWords = 0
    var totalCharacters = 0
    var avgWordsPerNote = 0
    var totalLinks = 0
    var orphanCount = 0
    var vaultSizeString = "0 KB"
    var longestNote: LongestNote?
    var mostLinkedNote: MostLinkedNote?
    var wordDistribution: [WordDistItem] = []
    var notesPerFolder: [FolderCount] = []
    var dailyActivity: [DailyWordCount] = []
}

struct LongestNote { let name: String; let words: Int }
struct MostLinkedNote { let name: String; let links: Int }

struct WordDistItem: Identifiable {
    let id = UUID()
    let range: String
    let count: Int
}

struct FolderCount: Identifiable {
    let id = UUID()
    let folder: String
    let count: Int
}

struct DailyWordCount: Identifiable {
    let id = UUID()
    let date: Date
    let words: Int
}
