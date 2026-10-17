/// The fixed search path for the quota-axi child. The real user's ~/.local/bin leads so the agy CLI is found;
/// the system and Homebrew entries follow. The login shell's PATH is deliberately not inherited.
public enum QuotaRunnerPath {
    public static func make(home: String) -> String {
        "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }
}
