import SwiftUI

struct LyricsLineView: View {
    let value: String
    let index: Int
    let currentIndex: Int?
    let isSynced: Bool
    let isTappable: Bool
    var isUserScrolling: Bool = false
    let onTap: () -> Void

    private var isLineActive: Bool {
        currentIndex == index
    }

    private var distance: Int {
        guard let currentIndex else { return 0 }
        return abs(index - currentIndex)
    }

    private var blurRadius: CGFloat {
        if isUserScrolling { return 0 }
        guard isSynced, currentIndex != nil else { return 0 }
        if isLineActive { return 0 }
        switch distance {
        case 1: return 2.0
        case 2: return 3.5
        default: return 5.0
        }
    }

    private var opacity: Double {
        guard isSynced, currentIndex != nil else { return 1.0 }
        return isLineActive ? 1.0 : 0.45
    }

    private var lineFont: Font {
        .system(size: 34, weight: .bold)
    }

    var body: some View {
        Text(value)
            .font(lineFont)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.white.opacity(opacity))
            .blur(radius: blurRadius)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isLineActive)
            .animation(.easeInOut(duration: 0.25), value: isUserScrolling)
            .contentShape(Rectangle())
            .onTapGesture {
                if isTappable { onTap() }
            }
    }
}
