import SwiftUI

struct HTTPInspectorToolView: View {
    let navigateBack: () -> Void

    @State private var urlString = "https://apple.com"
    @State private var method = "GET"
    @State private var followRedirects = true
    @State private var output = ""
    @State private var isLoading = false

    private static let methods = ["GET", "HEAD", "OPTIONS"]

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "HTTP Inspector",
                subtitle: "Fetches a URL and shows the status, timing, headers, and a body preview.",
                icon: "network.badge.shield.half.filled",
                isBusy: isLoading,
                navigateBack: navigateBack
            ) {
                Button("Send", systemImage: "paperplane") {
                    Task { await send() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }

            SectionCard("Request", icon: "arrow.up.circle") {
                FormField(label: "URL", text: $urlString, prompt: "https://example.com") {
                    Task { await send() }
                }

                HStack(spacing: Layout.control) {
                    Picker("Method", selection: $method) {
                        ForEach(Self.methods, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)

                    Toggle("Follow redirects", isOn: $followRedirects)

                    Spacer()
                }
            }

            OutputConsole(
                text: output,
                title: "Response",
                isRunning: isLoading,
                minHeight: 340,
                onClear: { output = "" }
            )
        }
    }

    private func send() async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            output = "Enter a full URL including https://"
            return
        }

        isLoading = true
        output = "Requesting \(trimmed)…"
        defer { isLoading = false }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(
            configuration: configuration,
            delegate: followRedirects ? nil : NoRedirectDelegate(),
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        let clock = ContinuousClock()
        let start = clock.now

        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = start.duration(to: clock.now)
            let millis = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000

            guard let http = response as? HTTPURLResponse else {
                output = "The server did not return an HTTP response."
                return
            }

            let headers = http.allHeaderFields
                .map { "\($0.key): \($0.value)" }
                .sorted()
                .joined(separator: "\n")

            let bodyPreview: String
            if method == "HEAD" {
                bodyPreview = "(no body for a HEAD request)"
            } else if data.isEmpty {
                bodyPreview = "(empty body)"
            } else {
                let preview = String(decoding: data.prefix(2000), as: UTF8.self)
                bodyPreview = data.count > 2000
                    ? preview + "\n\n… \(data.count - 2000) more bytes"
                    : preview
            }

            output = """
            \(method) \(trimmed)

            Status:  \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
            Time:    \(millis) ms
            Size:    \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary))
            Final:   \(http.url?.absoluteString ?? trimmed)

            ### Headers
            \(headers)

            ### Body preview
            \(bodyPreview)
            """
        } catch {
            output = "Request failed.\n\(error.localizedDescription)"
        }
    }
}

/// Reports redirects without following them, so the inspector can show the
/// first response rather than the final one.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
