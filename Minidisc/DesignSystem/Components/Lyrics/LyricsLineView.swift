import SwiftUI

struct LyricsLineView: View {
    let value: String
    let index: Int
    let currentIndex: Int?
    let isSynced: Bool
    let isTappable: Bool
    let onTap: () -> Void

    private var distance: Int {
        guard let currentIndex else { return 0 }
        return abs(index - currentIndex)
    }

    private var blurRadius: CGFloat {
        guard isSynced, currentIndex != nil else { return 0 }
        switch distance {
        case 0: return 0
        case 1: return 2.0
        case 2: return 3.5
        default: return 5.0
        }
    }

    private var opacity: Double {
        guard isSynced, currentIndex != nil else { return 1.0 }
        return distance == 0 ? 1.0 : 0.45
    }

    private var scale: CGFloat {
        guard isSynced, currentIndex != nil else { return 1.0 }
        return distance == 0 ? 1.05 : 1.0
    }

    private var lineFont: Font {
        .system(.title, design: .rounded, weight: .bold)
    }

    var body: some View {
        Text(value)
            .font(lineFont)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white.opacity(opacity))
            .blur(radius: blurRadius)
            .scaleEffect(scale, anchor: .leading)
            .animation(.easeInOut(duration: 0.25), value: currentIndex)
            .contentShape(Rectangle())
            .onTapGesture {
                if isTappable { onTap() }
            }
    }
}
