//
//  FirestoreREST.swift
//  DementiaCareHackathon
//
//  Reads and writes Firestore through its HTTPS API, so the app needs no Firebase package.
//  The project ID and API key are read from GoogleService-Info.plist.
//  This works with Firestore security rules in test mode (no sign-in).
//

import Foundation

/// Latitude and longitude as stored in Firestore.
struct GeoPoint: Equatable {
    let latitude: Double
    let longitude: Double
}

/// One document: its ID and its fields as plain Swift values
/// (String, Double, Int, Bool, Date, GeoPoint, Data).
struct FirestoreDocument {
    let id: String
    let fields: [String: Any]
}

struct FirestoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum FirestoreREST {
    // MARK: - Configuration

    private static let config: (projectID: String, apiKey: String)? = {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let dictionary = NSDictionary(contentsOf: url),
              let projectID = dictionary["PROJECT_ID"] as? String,
              let apiKey = dictionary["API_KEY"] as? String else {
            print("GoogleService-Info.plist is missing or incomplete")
            return nil
        }
        return (projectID, apiKey)
    }()

    // MARK: - Field values for writing

    static func string(_ value: String) -> [String: Any] { ["stringValue": value] }
    static func double(_ value: Double) -> [String: Any] { ["doubleValue": value] }
    static func int(_ value: Int) -> [String: Any] { ["integerValue": String(value)] }
    static func bool(_ value: Bool) -> [String: Any] { ["booleanValue": value] }
    static func bytes(_ value: Data) -> [String: Any] { ["bytesValue": value.base64EncodedString()] }

    static func timestamp(_ value: Date) -> [String: Any] {
        ["timestampValue": writeFormatter.string(from: value)]
    }

    static func geoPoint(latitude: Double, longitude: Double) -> [String: Any] {
        ["geoPointValue": ["latitude": latitude, "longitude": longitude]]
    }

    // MARK: - Requests

    /// Creates the document or updates only the given fields, keeping all other fields.
    static func patch(
        _ path: String,
        fields: [String: [String: Any]],
        completion: ((Error?) -> Void)? = nil
    ) {
        let mask = fields.keys.map { URLQueryItem(name: "updateMask.fieldPaths", value: $0) }
        send(method: "PATCH", path: path, query: mask, body: ["fields": fields]) { result in
            switch result {
            case .success:
                completion?(nil)
            case .failure(let error):
                print("Firestore write error (\(path)): \(error.localizedDescription)")
                completion?(error)
            }
        }
    }

    static func delete(_ path: String, completion: ((Error?) -> Void)? = nil) {
        send(method: "DELETE", path: path) { result in
            switch result {
            case .success:
                completion?(nil)
            case .failure(let error):
                print("Firestore delete error (\(path)): \(error.localizedDescription)")
                completion?(error)
            }
        }
    }

    /// Gets one document. The result is nil when the document does not exist.
    static func get(_ path: String, completion: @escaping (Result<FirestoreDocument?, Error>) -> Void) {
        send(method: "GET", path: path) { result in
            switch result {
            case .success(let json):
                guard let json = json else {
                    completion(.success(nil))
                    return
                }
                completion(.success(document(from: json)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Lists the documents in a collection. onlyFields limits which fields are returned.
    static func list(
        _ path: String,
        onlyFields: [String]? = nil,
        completion: @escaping (Result<[FirestoreDocument], Error>) -> Void
    ) {
        var query = [URLQueryItem(name: "pageSize", value: "300")]
        if let onlyFields = onlyFields {
            query += onlyFields.map { URLQueryItem(name: "mask.fieldPaths", value: $0) }
        }
        send(method: "GET", path: path, query: query) { result in
            switch result {
            case .success(let json):
                let items = json?["documents"] as? [[String: Any]] ?? []
                completion(.success(items.compactMap { document(from: $0) }))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Sends a request. The completion runs on the main thread.
    /// Success with nil means the document was not found (HTTP 404).
    private static func send(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        completion: @escaping (Result<[String: Any]?, Error>) -> Void
    ) {
        func finish(_ result: Result<[String: Any]?, Error>) {
            DispatchQueue.main.async {
                completion(result)
            }
        }

        guard let config = config else {
            finish(.failure(FirestoreError(message: "GoogleService-Info.plist is missing from the app.")))
            return
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "firestore.googleapis.com"
        components.path = "/v1/projects/\(config.projectID)/databases/(default)/documents/\(path)"
        components.queryItems = query + [URLQueryItem(name: "key", value: config.apiKey)]

        guard let url = components.url else {
            finish(.failure(FirestoreError(message: "Invalid Firestore address.")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        // Firebase API keys can be limited to this app's bundle ID; this header identifies the app.
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                finish(.failure(error))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]

            if status == 404 {
                finish(.success(nil))
            } else if (200..<300).contains(status) {
                finish(.success(json ?? [:]))
            } else {
                let message = (json?["error"] as? [String: Any])?["message"] as? String
                    ?? "Server returned status \(status)."
                finish(.failure(FirestoreError(message: message)))
            }
        }.resume()
    }

    // MARK: - Reading values

    private static func document(from json: [String: Any]) -> FirestoreDocument? {
        guard let name = json["name"] as? String else { return nil }
        let id = (name as NSString).lastPathComponent
        let rawFields = json["fields"] as? [String: Any] ?? [:]
        var fields: [String: Any] = [:]
        for (key, value) in rawFields {
            if let value = value as? [String: Any], let decoded = decode(value) {
                fields[key] = decoded
            }
        }
        return FirestoreDocument(id: id, fields: fields)
    }

    private static func decode(_ value: [String: Any]) -> Any? {
        if let string = value["stringValue"] as? String {
            return string
        }
        if let number = value["doubleValue"] as? NSNumber {
            return number.doubleValue
        }
        if let integerText = value["integerValue"] as? String, let integer = Int(integerText) {
            return integer
        }
        if let bool = value["booleanValue"] as? Bool {
            return bool
        }
        if let text = value["timestampValue"] as? String {
            return parseDate(text)
        }
        if let point = value["geoPointValue"] as? [String: Any] {
            let latitude = (point["latitude"] as? NSNumber)?.doubleValue ?? 0
            let longitude = (point["longitude"] as? NSNumber)?.doubleValue ?? 0
            return GeoPoint(latitude: latitude, longitude: longitude)
        }
        if let base64 = value["bytesValue"] as? String {
            return Data(base64Encoded: base64)
        }
        return nil
    }

    private static let writeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Firestore returns times like 2026-10-24T23:00:00.123456Z. The fraction is dropped before parsing.
    private static func parseDate(_ text: String) -> Date? {
        if let date = plainFormatter.date(from: text) {
            return date
        }
        if let dotIndex = text.firstIndex(of: "."), let zIndex = text.lastIndex(of: "Z"), dotIndex < zIndex {
            let trimmed = String(text[..<dotIndex]) + "Z"
            return plainFormatter.date(from: trimmed)
        }
        return nil
    }
}

/// Runs a closure now and then every few seconds on the main run loop.
final class Poller {
    private var timer: Timer?

    func start(every seconds: TimeInterval, _ action: @escaping () -> Void) {
        stop()
        action()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in
            action()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
