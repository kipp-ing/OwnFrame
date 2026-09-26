//
//  ImmichTestUpload.swift
//  OwnFrameUITests
//
//  Server-side writes for the "a new server photo appears" device test (310 resilience smoke,
//  FR-310-06): upload one fresh photo into the device-test album, and delete it again.
//
//  Only ever against the test user's album that `.claude/scripts/immich-test-album.sh` created
//  on frame.kippings.de — never Jan's libraries. The key arrives via TEST_RUNNER_IMMICH_UPLOAD_KEY
//  (read from the login Keychain by device-accept.sh) and is never logged. The runner process
//  has no Local Network permission; frame.kippings.de resolves to its public address, so that
//  is not needed.
//

import UIKit
import XCTest

enum ImmichTestUpload {
    struct Failure: Error, CustomStringConvertible { let description: String }

    /// Uploads a unique flat-colour JPEG (unique pixels, so Immich never dedupes it) and adds it
    /// to `albumID`. Returns the new asset id.
    static func uploadNewPhoto(server: URL, key: String, albumID: String) throws -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 1500, height: 1000)).jpegData(withCompressionQuality: 0.9) { ctx in
            UIColor(hue: .random(in: 0...1), saturation: 0.35, brightness: 0.7, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1500, height: 1000))
            ("OwnFrame arrival test · " + stamp as NSString).draw(
                at: CGPoint(x: 40, y: 920),
                withAttributes: [.font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.white])
        }

        let boundary = "ownframe-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("fileCreatedAt", stamp)
        field("fileModifiedAt", stamp)
        field("filename", "arrival-\(stamp).jpg")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"assetData\"; filename=\"arrival.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var upload = request(server, "assets", key: key, method: "POST")
        upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        upload.httpBody = body
        guard let id = try send(upload)["id"] as? String else { throw Failure(description: "upload returned no id") }

        var add = request(server, "albums/\(albumID)/assets", key: key, method: "PUT")
        add.setValue("application/json", forHTTPHeaderField: "Content-Type")
        add.httpBody = try JSONSerialization.data(withJSONObject: ["ids": [id]])
        _ = try send(add)
        return id
    }

    /// Removes the asset for good (no trash), so the album stays at its seed photos.
    static func delete(server: URL, key: String, assetID: String) {
        var req = request(server, "assets", key: key, method: "DELETE")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["ids": [assetID], "force": true])
        _ = try? send(req)
    }

    private static func request(_ server: URL, _ path: String, key: String, method: String) -> URLRequest {
        var req = URLRequest(url: server.appendingPathComponent("api/\(path)"), timeoutInterval: 60)
        req.httpMethod = method
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        return req
    }

    /// Synchronous on purpose: the XCTest body is synchronous and the calls are few.
    private static func send(_ req: URLRequest) throws -> [String: Any] {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<(Data, HTTPURLResponse), Error> = .failure(Failure(description: "timed out"))
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { result = .failure(error) }
            else if let http = response as? HTTPURLResponse { result = .success((data ?? Data(), http)) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 90)
        let (data, http) = try result.get()
        guard (200..<300).contains(http.statusCode) else {
            throw Failure(description: "\(req.httpMethod ?? "") \(req.url?.path ?? "") → HTTP \(http.statusCode)")
        }
        // Album PUT returns an array; only the upload's object is read.
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
