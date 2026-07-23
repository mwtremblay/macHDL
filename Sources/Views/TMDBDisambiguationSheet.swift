import SwiftUI

/// Presented by AddTVEpisodeSheet/AddVideoSheet when a TMDB name search
/// returns more than one plausible match (e.g. "The Office" US/UK, a
/// remake) -- AddTVEpisodeViewModel.lookUpEpisodeMetadata/
/// AddVideoViewModel.lookUpMovieMetadata populate the candidate list; this
/// is just a tappable picker over it, dismissing itself once a selection is
/// made. One shared view for both flows -- TMDBSearchCandidate already
/// reduces a show or movie result to the same name+year shape.
struct TMDBDisambiguationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let candidates: [TMDBSearchCandidate]
    let onSelect: (TMDBSearchCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)

            List(candidates) { candidate in
                Button {
                    onSelect(candidate)
                    dismiss()
                } label: {
                    HStack {
                        Text(candidate.name)
                        if let year = candidate.year {
                            Text("(\(year))")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 160)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }
        .padding()
        .frame(width: 360)
    }
}
