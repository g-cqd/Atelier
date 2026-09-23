import DiffComparison
import Foundation
import SwiftUI

/// Settings ▸ Tools' list of the repositories the user trusts, each with a button that revokes it.
struct TrustedRepositoriesSection: View {
    let trust: RepositoryTrust

    var body: some View {
        Section("Trusted Repositories") {
            let roots = trust.trustedRoots
            if roots.isEmpty {
                Text("No repository is trusted.")
                    .foregroundStyle(.secondary)
            }
            ForEach(roots, id: \.self) { root in
                HStack {
                    Text((root.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(root.path(percentEncoded: false))
                    Spacer()
                    Button("Revoke") { trust.revoke(root) }
                }
            }
            Text(
                "Hover documentation starts sourcekit-lsp, which builds the project and so runs its code, and Fetch "
                    + "runs, only in the repositories listed here. A hover in any other repository asks once, and "
                    + "Trust Repository… in its source menu asks again. Revoking stops sourcekit-lsp there."
            )
            .settingsCaption()
        }
    }
}
