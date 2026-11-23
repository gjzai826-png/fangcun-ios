import SwiftUI

enum Theme {
    static let accent = Color(red: 104 / 255, green: 88 / 255, blue: 208 / 255)
    static let ink = Color(red: 30 / 255, green: 27 / 255, blue: 46 / 255)
    static let muted = Color(red: 110 / 255, green: 106 / 255, blue: 128 / 255)
    static let paper = Color(red: 243 / 255, green: 245 / 255, blue: 251 / 255)
    static let line = Color(red: 228 / 255, green: 231 / 255, blue: 242 / 255)
    static let good = Color(red: 31 / 255, green: 163 / 255, blue: 113 / 255)
    static let warn = Color(red: 224 / 255, green: 138 / 255, blue: 42 / 255)
    static let bad = Color(red: 212 / 255, green: 83 / 255, blue: 78 / 255)
}

extension View {
    func paperScreen() -> some View {
        background(Theme.paper.ignoresSafeArea())
    }

    func card() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct Badge: View {
    var text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TagWrap: View {
    var tags: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.paper)
                    .clipShape(Capsule())
            }
        }
        .accessibilityIdentifier("feeAndParkingTags")
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct InfoRow: View {
    var title: String
    var value: String
    var body: some View {
        HStack {
            Text(title).foregroundStyle(Theme.muted)
            Spacer()
            Text(value.isEmpty ? "未填" : value).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct ErrorAlert: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("没有完成", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        modifier(ErrorAlert(message: message))
    }
}

func statusColor(_ status: PropertyStatus) -> Color {
    switch status {
    case .available: return Theme.good
    case .reserved, .needsVerification, .unknown: return Theme.warn
    case .rented, .sold, .offline: return Theme.muted
    }
}
