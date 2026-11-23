import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: ScribeModel

    private let limits: [(Int, String)] = [
        (0, "제한 없음"), (30, "30분"), (60, "1시간"), (90, "1시간 30분"),
        (120, "2시간"), (240, "4시간"), (480, "8시간")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                if let msg = model.errorMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal).padding(.vertical, 6)
                }
                transcript
                controls
            }
            .navigationTitle("owlSeven")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("저장된 기록") { FilesView() }
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.running ? Color.red : Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)
            Text(model.status).font(.subheadline)
            Spacer()
            Text(model.elapsedText).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            List {
                if model.lines.isEmpty && model.interim.isEmpty {
                    Text("녹음 시작을 누르면 받아쓴 내용이 여기에 쌓입니다.\n화면을 꺼도, 다른 앱을 써도 계속 받아씁니다.")
                        .font(.callout).foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                ForEach(model.lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(line.time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text((line.star ? "★ " : "") + line.text)
                            .foregroundStyle(line.mark ? Color.orange : Color.primary)
                            .fontWeight(line.star ? .semibold : .regular)
                    }
                    .listRowBackground(line.star ? Color.orange.opacity(0.12) : Color.clear)
                    .id(line.id)
                }
                if !model.interim.isEmpty {
                    Text(model.interim).foregroundStyle(.secondary).id("interim")
                }
            }
            .listStyle(.plain)
            .onChange(of: model.lines.count) {
                if let last = model.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("녹음 시간", selection: $model.limitMinutes) {
                    ForEach(limits, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.menu)
                .disabled(model.running)
                .frame(maxWidth: .infinity)

                Button(action: model.toggle) {
                    Text(model.running ? "정지" : "녹음 시작")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.running ? Color.red : Color.accentColor)
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 10) {
                Button(action: model.markStar) {
                    Text("★ 모르는 말").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!model.running)

                ShareLink(item: model.currentShareText) {
                    Text("Claude로 보내기").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(model.lines.allSatisfy { $0.mark })
            }
        }
        .padding()
        .background(.bar)
    }
}

struct FilesView: View {
    @EnvironmentObject var model: ScribeModel

    var body: some View {
        List {
            if model.savedFiles.isEmpty {
                Text("저장된 기록이 없습니다.").foregroundStyle(.secondary)
            }
            ForEach(model.savedFiles, id: \.self) { url in
                HStack {
                    Text(url.deletingPathExtension().lastPathComponent)
                    Spacer()
                    ShareLink(item: ScribeModel.shareText(for: url)) {
                        Label("보내기", systemImage: "square.and.arrow.up")
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .onDelete { idx in idx.map { model.savedFiles[$0] }.forEach(model.delete) }
            Section {
                Text("기록은 파일 앱 > 나의 iPhone > owlSeven > 받아쓰기 폴더에도 있습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("저장된 기록")
        .onAppear { model.refreshFiles() }
    }
}
