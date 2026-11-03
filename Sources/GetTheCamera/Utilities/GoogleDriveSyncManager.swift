import AppKit
import Combine
import CryptoKit
import Foundation
import Network
import Security

struct GoogleDriveFile: Identifiable {
	let id: String
	let name: String
	let size: String?
	let modifiedTime: String?
}

@MainActor
final class GoogleDriveSyncManager {
	static let shared = GoogleDriveSyncManager()

	@Published private(set) var status = "Not connected"

	private let clientIDKey = "GOOGLE_CLIENT_ID"
	private let refreshTokenService = "com.getthecamera.app.google-drive.refresh-token"
	private let accessTokenDefaultsKey = "googleDrive.accessToken"
	private let accessTokenExpiryDefaultsKey = "googleDrive.accessTokenExpiry"
	private let folderIDDefaultsKey = "googleDrive.folderID"
	private let queueDirectoryName = "GoogleDriveQueue"
	private let loopbackPort: UInt16 = 53682

	private init() {}

	var clientID: String? {
		if let value = ProcessInfo.processInfo.environment["GETTHECAMERA_GOOGLE_CLIENT_ID"],
		   !value.isEmpty {
			return value
		}
		if let value = Bundle.main.object(forInfoDictionaryKey: clientIDKey) as? String,
		   !value.isEmpty {
			return value
		}
		return nil
	}

	func connect() async {
		guard let clientID else {
			status = "Missing Google OAuth client ID"
			return
		}
		do {
			if refreshToken != nil {
				status = "Connected"
				try await ensureFolder()
				await processQueue()
				return
			}
			status = "Waiting for Google sign-in"
			_ = try await authorize(clientID: clientID)
			status = "Connected"
		} catch {
			status = "Sign-in failed"
			AppLog.error(.app, "Google Drive authorization failed:", error.localizedDescription)
		}
	}

	func listCloudFiles() async throws -> [GoogleDriveFile] {
		guard let clientID else {
			throw GoogleDriveError.configuration("Missing Google OAuth client ID")
		}
		let accessToken = try await validAccessToken(clientID: clientID)
		guard !accessToken.isEmpty else { throw GoogleDriveError.notAuthorized }
		let folderID = try await ensureFolder(accessToken: accessToken, clientID: clientID)

		var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
		components.queryItems = [
			URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed=false"),
			URLQueryItem(name: "fields", value: "files(id,name,size,modifiedTime)"),
			URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
			URLQueryItem(name: "pageSize", value: "100")
		]
		var request = URLRequest(url: components.url!)
		request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
		let (data, response) = try await URLSession.shared.data(for: request)
		try validate(response)

		struct ListResponse: Decodable {
			struct File: Decodable {
				let id: String
				let name: String
				let size: String?
				let modifiedTime: String?
			}
			let files: [File]?
		}
		let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
		return (decoded.files ?? []).map {
			GoogleDriveFile(id: $0.id, name: $0.name, size: $0.size, modifiedTime: $0.modifiedTime)
		}
	}

	func sync(clipAt fileURL: URL) async throws {
		guard let clientID else { throw GoogleDriveError.configuration("Missing Google OAuth client ID") }
		status = "Uploading"
		var accessToken = try await validAccessToken(clientID: clientID)
		if accessToken.isEmpty {
			throw GoogleDriveError.notAuthorized
		}
		let folderID = try await ensureFolder(accessToken: accessToken, clientID: clientID)
		accessToken = try await validAccessToken(clientID: clientID)

		var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!)
		request.httpMethod = "POST"
		request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
		let metadata = [
			"name": fileURL.lastPathComponent,
			"parents": [folderID]
		] as [String: Any]
		request.httpBody = try JSONSerialization.data(withJSONObject: metadata)

		let (_, response) = try await URLSession.shared.upload(for: request, from: Data())
		try validate(response)
		guard let http = response as? HTTPURLResponse,
		      let location = http.value(forHTTPHeaderField: "Location"),
		      let uploadURL = URL(string: location) else {
			throw GoogleDriveError.invalidResponse("Missing resumable upload URL")
		}

		var uploadRequest = URLRequest(url: uploadURL)
		uploadRequest.httpMethod = "PUT"
		uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
		let (data, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, fromFile: fileURL)
		try validate(uploadResponse)
		_ = data
		status = "Connected"
	}

	func disconnect() {
		deleteRefreshToken()
		UserDefaults.standard.removeObject(forKey: accessTokenDefaultsKey)
		UserDefaults.standard.removeObject(forKey: accessTokenExpiryDefaultsKey)
		UserDefaults.standard.removeObject(forKey: folderIDDefaultsKey)
		status = "Not connected"
	}

	func queueForUpload(clipAt fileURL: URL) {
		let queueDirectory = queueURL
		try? FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
		let queued = queueDirectory.appendingPathComponent(fileURL.lastPathComponent)
		if fileURL.path != queued.path {
			try? FileManager.default.copyItem(at: fileURL, to: queued)
		}
		status = "Queued for upload"
	}

	func processQueue() async {
		let queueDirectory = queueURL
		guard let files = try? FileManager.default.contentsOfDirectory(
			at: queueDirectory,
			includingPropertiesForKeys: nil
		) else { return }
		for fileURL in files where fileURL.pathExtension != "json" {
			do {
				try await sync(clipAt: fileURL)
				try? FileManager.default.removeItem(at: fileURL)
			} catch {
				AppLog.error(.app, "Queued Drive upload failed:", error.localizedDescription)
			}
		}
	}

	private var queueURL: URL {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			?? FileManager.default.temporaryDirectory
		return base.appendingPathComponent("GetTheCamera", isDirectory: true)
			.appendingPathComponent(queueDirectoryName, isDirectory: true)
	}

	private var refreshToken: String? { readKeychain() }

	private func authorize(clientID: String) async throws -> String {
		let verifier = randomString(length: 64)
		let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
		let state = randomString(length: 32)
		let redirectURI = "http://127.0.0.1:\(loopbackPort)/oauth/callback"

		var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
		components.queryItems = [
			URLQueryItem(name: "client_id", value: clientID),
			URLQueryItem(name: "redirect_uri", value: redirectURI),
			URLQueryItem(name: "response_type", value: "code"),
			URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.file"),
			URLQueryItem(name: "access_type", value: "offline"),
			URLQueryItem(name: "prompt", value: "consent"),
			URLQueryItem(name: "state", value: state),
			URLQueryItem(name: "code_challenge", value: challenge),
			URLQueryItem(name: "code_challenge_method", value: "S256")
		]

		let code = try await listenForAuthorizationCode(
			authorizationURL: components.url!,
			redirectURI: redirectURI,
			state: state
		)

		let tokenRequestURL = URL(string: "https://oauth2.googleapis.com/token")!
		var request = URLRequest(url: tokenRequestURL)
		request.httpMethod = "POST"
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		request.httpBody = formEncoded([
			"client_id": clientID,
			"code": code,
			"code_verifier": verifier,
			"grant_type": "authorization_code",
			"redirect_uri": redirectURI
		]).data(using: .utf8)

		let (data, response) = try await URLSession.shared.data(for: request)
		try validate(response)
		let token = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
		guard let refresh = token.refresh_token else {
			throw GoogleDriveError.invalidResponse("Google did not return a refresh token")
		}
		try writeKeychain(refresh)
		cacheAccessToken(token.access_token, expiresIn: token.expires_in)
		return token.access_token
	}

	private func listenForAuthorizationCode(
		authorizationURL: URL,
		redirectURI: String,
		state: String
	) async throws -> String {
		try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.main.async {
				do {
					let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: self.loopbackPort)!)
					listener.newConnectionHandler = { connection in
						connection.start(queue: .main)
						connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
							defer { connection.cancel(); listener.cancel() }
							let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
							let firstLine = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first
							guard let requestTarget = firstLine else {
								self.send(connection, body: "GetTheCamera could not read the sign-in response.")
								continuation.resume(throwing: GoogleDriveError.invalidResponse("Invalid callback"))
								return
							}
							let callbackURL = requestTarget.hasPrefix("/")
								? "http://127.0.0.1:\(self.loopbackPort)\(requestTarget)"
								: String(requestTarget)
							guard let components = URLComponents(string: callbackURL) else {
								self.send(connection, body: "GetTheCamera could not read the sign-in response.")
								continuation.resume(throwing: GoogleDriveError.invalidResponse("Invalid callback"))
								return
							}
							let items = components.queryItems ?? []
							if items.first(where: { $0.name == "state" })?.value != state {
								self.send(connection, body: "Sign-in failed: state mismatch.")
								continuation.resume(throwing: GoogleDriveError.invalidResponse("OAuth state mismatch"))
								return
							}
							if let error = items.first(where: { $0.name == "error" })?.value {
								self.send(connection, body: "Google sign-in was cancelled or denied.")
								continuation.resume(throwing: GoogleDriveError.authorization(error))
								return
							}
							guard let code = items.first(where: { $0.name == "code" })?.value else {
								self.send(connection, body: "Google sign-in did not return an authorization code.")
								continuation.resume(throwing: GoogleDriveError.invalidResponse("Missing authorization code"))
								return
							}
							self.send(connection, body: "Google Drive is connected. You can close this window.")
							continuation.resume(returning: code)
						}
					}
					listener.start(queue: .main)
					NSWorkspace.shared.open(authorizationURL)
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
	}

	nonisolated private func send(_ connection: NWConnection, body: String) {
		let html = "<!doctype html><html><body><h2>\(body)</h2></body></html>"
		let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
		connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
	}

	private func ensureFolder() async throws {
		guard let clientID else { throw GoogleDriveError.configuration("Missing Google OAuth client ID") }
		_ = try await ensureFolder(accessToken: try await validAccessToken(clientID: clientID), clientID: clientID)
	}

	private func ensureFolder(accessToken: String, clientID: String) async throws -> String {
		if let folderID = UserDefaults.standard.string(forKey: folderIDDefaultsKey), !folderID.isEmpty {
			return folderID
		}
		var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
		request.httpMethod = "POST"
		request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONSerialization.data(withJSONObject: [
			"name": "GetTheCamera",
			"mimeType": "application/vnd.google-apps.folder"
		])
		let (data, response) = try await URLSession.shared.data(for: request)
		try validate(response)
		let folder = try JSONDecoder().decode(GoogleFolderResponse.self, from: data)
		UserDefaults.standard.set(folder.id, forKey: folderIDDefaultsKey)
		return folder.id
	}

	private func validAccessToken(clientID: String) async throws -> String {
		let expiry = UserDefaults.standard.double(forKey: accessTokenExpiryDefaultsKey)
		if let token = UserDefaults.standard.string(forKey: accessTokenDefaultsKey),
		   !token.isEmpty,
		   expiry > Date().timeIntervalSince1970 + 60 {
			return token
		}
		guard let refreshToken else { throw GoogleDriveError.notAuthorized }
		var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
		request.httpMethod = "POST"
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		request.httpBody = formEncoded([
			"client_id": clientID,
			"refresh_token": refreshToken,
			"grant_type": "refresh_token"
		]).data(using: .utf8)
		let (data, response) = try await URLSession.shared.data(for: request)
		try validate(response)
		let token = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
		cacheAccessToken(token.access_token, expiresIn: token.expires_in)
		return token.access_token
	}

	private func cacheAccessToken(_ token: String, expiresIn: Int) {
		UserDefaults.standard.set(token, forKey: accessTokenDefaultsKey)
		UserDefaults.standard.set(Date().timeIntervalSince1970 + Double(expiresIn), forKey: accessTokenExpiryDefaultsKey)
	}

	private func validate(_ response: URLResponse) throws {
		guard let http = response as? HTTPURLResponse else { throw GoogleDriveError.invalidResponse("No HTTP response") }
		guard (200 ... 299).contains(http.statusCode) else {
			throw GoogleDriveError.http(http.statusCode)
		}
	}

	private func readKeychain() -> String? {
		var query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: refreshTokenService,
			kSecAttrAccount as String: "refresh-token",
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne
		]
		var result: AnyObject?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      let data = result as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	private func writeKeychain(_ value: String) throws {
		let data = Data(value.utf8)
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: refreshTokenService,
			kSecAttrAccount as String: "refresh-token"
		]
		let attributes: [String: Any] = [kSecValueData as String: data]
		let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
		if status == errSecItemNotFound {
			var addQuery = query
			addQuery[kSecValueData as String] = data
			guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
				throw GoogleDriveError.keychain
			}
		} else if status != errSecSuccess {
			throw GoogleDriveError.keychain
		}
	}

	private func deleteRefreshToken() {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: refreshTokenService,
			kSecAttrAccount as String: "refresh-token"
		]
		SecItemDelete(query as CFDictionary)
	}

	private func randomString(length: Int) -> String {
		let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
		return String((0 ..< length).compactMap { _ in characters.randomElement() })
	}

	private func formEncoded(_ values: [String: String]) -> String {
		values.map { key, value in
			let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
			let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
			return "\(encodedKey)=\(encodedValue)"
		}.joined(separator: "&")
	}
}

private struct GoogleTokenResponse: Decodable {
	let access_token: String
	let refresh_token: String?
	let expires_in: Int
}

private struct GoogleFolderResponse: Decodable {
	let id: String
}

private enum GoogleDriveError: LocalizedError {
	case configuration(String)
	case authorization(String)
	case notAuthorized
	case invalidResponse(String)
	case http(Int)
	case keychain

	var errorDescription: String? {
		switch self {
		case .configuration(let message): return message
		case .authorization(let message): return message
		case .notAuthorized: return "Google Drive is not connected."
		case .invalidResponse(let message): return message
		case .http(let code): return "Google Drive request failed with HTTP \(code)."
		case .keychain: return "Could not save the Google Drive refresh token in the Keychain."
		}
	}
}

private extension Data {
	func base64URLEncodedString() -> String {
		base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}
}
