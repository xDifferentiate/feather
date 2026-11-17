//
//  Notification+Feather.swift
//  Feather
//

import Foundation

extension Notification.Name {
	/// Posted when an `.ipa`/`.tipa` opened from another app (Files, Safari, share sheet,
	/// Share to Feather) starts importing, so the tab bar can switch to the Library.
	static let featherShowLibrary = Notification.Name("Feather.showLibrary")
}
