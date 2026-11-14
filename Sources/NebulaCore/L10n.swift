// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Follows the system's (or per-app override's) preferred language.
public enum L10n {
    public static func text(_ chinese: String, _ english: String) -> String {
        text(chinese, english, languages: Locale.preferredLanguages)
    }

    public static func text(_ chinese: String, _ english: String, languages: [String]) -> String {
        languages.first?.lowercased().hasPrefix("zh") == true ? chinese : english
    }
}
