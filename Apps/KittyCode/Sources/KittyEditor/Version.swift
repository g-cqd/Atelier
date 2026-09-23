/// The version `kittycode --version` reports: `.github/workflows/kittycode-release.yml` rewrites this file with the
/// tag's version before a release build, so any other build reports `0.0.0-dev`.
public enum BuildVersion {
    public static let release = "0.0.0-dev"
}
