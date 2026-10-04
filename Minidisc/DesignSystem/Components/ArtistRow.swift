import SwiftUI
import SwiftSonic

struct ArtistRow: View {
    let artist: ArtistID3
    var imageSize: CGFloat = 48
    var verticalPadding: CGFloat = 0

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            CoverArtView(
                id: artist.coverArt ?? artist.id,
                size: Int(imageSize * 2),
                placeholderSystemImage: "person.fill"
            )
            .frame(width: imageSize, height: imageSize)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.minidiscCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let count = artist.albumCount {
                    Text("\(count) albums")
                        .font(.minidiscCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
    }
}
