//
//  SharedInbox.swift
//  FeatherShare
//
//  Keep in sync with Feather/Utilities/SharedInbox.swift.
//

import Foundation
import Darwin

/// A folder in Feather's App Group container where the share extension drops shared
/// `.ipa`/`.tipa` files for the main app to import.
///
/// Sideload signers usually rename App Groups, so the group identifier is read from this
/// process's own signed entitlements first and only falls back to the default in Info.plist.
enum SharedInbox {
	static let folderName = "FeatherShareInbox"

	static func appGroupIdentifiers() -> [String] {
		var identifiers = _entitledAppGroups()
		if let fallback = Bundle.main.object(forInfoDictionaryKey: "FeatherAppGroupIdentifier") as? String {
			identifiers.append(fallback)
		}

		var seen = Set<String>()
		return identifiers.filter { seen.insert($0).inserted }
	}

	/// The shared inbox folder, or `nil` when this install has no usable App Group.
	static func directory() -> URL? {
		let fileManager = FileManager.default

		for identifier in appGroupIdentifiers() {
			guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
				continue
			}

			let inbox = container.appendingPathComponent(folderName, isDirectory: true)
			do {
				try fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)
				return inbox
			} catch {
				continue
			}
		}

		return nil
	}

	/// `com.apple.security.application-groups` from this process's code signature.
	private static func _entitledAppGroups() -> [String] {
		typealias SecTaskCreateFromSelf = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
		typealias SecTaskCopyValueForEntitlement = @convention(c) (
			AnyObject,
			CFString,
			UnsafeMutablePointer<Unmanaged<CFError>?>?
		) -> Unmanaged<AnyObject>?

		guard
			let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
			let createSymbol = dlsym(handle, "SecTaskCreateFromSelf"),
			let copySymbol = dlsym(handle, "SecTaskCopyValueForEntitlement")
		else {
			return []
		}

		let create = unsafeBitCast(createSymbol, to: SecTaskCreateFromSelf.self)
		let copyValue = unsafeBitCast(copySymbol, to: SecTaskCopyValueForEntitlement.self)

		guard let task = create(nil)?.takeRetainedValue() else {
			return []
		}

		let value = copyValue(task, "com.apple.security.application-groups" as CFString, nil)?.takeRetainedValue()
		return value as? [String] ?? []
	}
}
