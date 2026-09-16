// Generated stub overwritten by `.github/workflows/release.yml` at
// release time. Local / unreleased builds always report the
// `0.0.0-dev` placeholder so a `kittycode --version` produces a useful
// string without anyone hand-bumping a literal between releases.
//
// The release workflow rewrites this file with the tag-derived version
// before `swift build -c release`. Audit D9.
public enum BuildVersion {
    public static let release = "0.0.0-dev"
}
