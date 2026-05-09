import SwiftUI

struct SourceTypeIcon: View {
    let sourceType: SourceType

    var body: some View {
        Image(systemName: sourceType.systemIcon)
            .accessibilityLabel(sourceType.displayName)
    }
}
