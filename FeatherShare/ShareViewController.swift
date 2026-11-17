//
//  ShareViewController.swift
//  FeatherShare
//
//  "Share to Feather": copies the shared .ipa/.tipa into Feather's App Group inbox and
//  opens Feather, which imports it exactly like Library → Import from Files.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
	/// Type identifiers to load an attachment as, most specific first.
	private static let _typeIdentifiers = [
		"thewonderofyou.Feather.ipa",
		"thewonderofyou.Feather.tipa",
		"com.apple.itunes.ipa",
		"public.zip-archive",
		UTType.data.identifier,
	]

	private let _label = UILabel()
	private let _spinner = UIActivityIndicatorView(style: .medium)
	private var _didStart = false

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .systemBackground

		_label.text = "Sending to Feather…"
		_label.textAlignment = .center
		_label.numberOfLines = 0
		_spinner.startAnimating()

		let stack = UIStackView(arrangedSubviews: [_spinner, _label])
		stack.axis = .vertical
		stack.spacing = 12
		stack.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(stack)

		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
			stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
			stack.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
		])
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		guard !_didStart else { return }
		_didStart = true
		_handleShare()
	}

	private func _handleShare() {
		guard let inbox = SharedInbox.directory() else {
			_fail(
				"Feather's share extension can't reach Feather's shared storage (App Group) in this install. " +
				"Re-sign Feather with a provisioning profile that includes an App Group, " +
				"or pick Feather from the app row of the share sheet (\"Open in Feather\") instead."
			)
			return
		}

		let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
			.flatMap { $0.attachments ?? [] }

		let group = DispatchGroup()
		let lock = NSLock()
		var copiedCount = 0
		var lastError: Error?

		for provider in providers {
			guard let typeIdentifier = Self._typeIdentifiers.first(where: {
				provider.hasItemConformingToTypeIdentifier($0)
			}) else {
				continue
			}

			let suggestedName = provider.suggestedName
			group.enter()

			// The file handed to this callback is deleted when it returns, so copy it here.
			_ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
				defer { group.leave() }

				lock.lock()
				defer { lock.unlock() }

				guard let url else {
					lastError = error
					return
				}

				do {
					try Self._copy(url, suggestedName: suggestedName, into: inbox)
					copiedCount += 1
				} catch {
					lastError = error
				}
			}
		}

		group.notify(queue: .main) {
			guard copiedCount > 0 else {
				self._fail(lastError?.localizedDescription ?? "No .ipa or .tipa file was shared.")
				return
			}

			self._label.text = "Opening Feather…"
			self._openFeather()
			self.extensionContext?.completeRequest(returningItems: nil)
		}
	}

	private static func _copy(_ url: URL, suggestedName: String?, into inbox: URL) throws {
		let fileManager = FileManager.default

		var baseName = url.deletingPathExtension().lastPathComponent
		var pathExtension = url.pathExtension.lowercased()

		if let suggestedName, !suggestedName.isEmpty {
			let suggestedURL = URL(fileURLWithPath: suggestedName)
			baseName = suggestedURL.deletingPathExtension().lastPathComponent
			if !suggestedURL.pathExtension.isEmpty {
				pathExtension = suggestedURL.pathExtension.lowercased()
			}
		}

		if pathExtension != "ipa" && pathExtension != "tipa" {
			pathExtension = "ipa"
		}

		var destination = inbox.appendingPathComponent(baseName).appendingPathExtension(pathExtension)
		if fileManager.fileExists(atPath: destination.path) {
			destination = inbox
				.appendingPathComponent("\(baseName)-\(UUID().uuidString.prefix(8))")
				.appendingPathExtension(pathExtension)
		}

		try fileManager.copyItem(at: url, to: destination)
	}

	/// App extensions can't call `UIApplication.shared.open`, so walk the responder chain to
	/// the host's `UIApplication` and send it `openURL:options:completionHandler:` directly.
	private func _openFeather() {
		guard let url = URL(string: "feather://import-shared") else { return }

		let selector = NSSelectorFromString("openURL:options:completionHandler:")
		var responder: UIResponder? = self

		while let current = responder {
			if let application = current as? UIApplication, application.responds(to: selector) {
				typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
				let open = unsafeBitCast(application.method(for: selector), to: OpenURL.self)
				open(application, selector, url as NSURL, NSDictionary(), nil)
				return
			}
			responder = current.next
		}
	}

	private func _fail(_ message: String) {
		_spinner.stopAnimating()
		_label.text = message

		let alert = UIAlertController(title: "Feather", message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
			let error = NSError(domain: "thewonderofyou.Feather.Share", code: 1, userInfo: [
				NSLocalizedDescriptionKey: message,
			])
			self.extensionContext?.cancelRequest(withError: error)
		})
		present(alert, animated: true)
	}
}
