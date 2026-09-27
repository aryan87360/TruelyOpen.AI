//
//  WebSearchService.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import Foundation
import Combine

public struct WebSearchToolCall: Codable, Equatable {
    public let name: String
    public let arguments: WebSearchArguments
}

public struct WebSearchArguments: Codable, Equatable {
    public let query: String
}

public struct WebSearchToolResult: Codable, Equatable {
    public let results: [WebSearchResult]
}

public final class WebSearchService: ObservableObject {
    public static let shared = WebSearchService()

    @Published public var isSearching: Bool = false
    @Published public var lastQuery: String = ""

    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 7.0
        config.timeoutIntervalForResource = 10.0
        return URLSession(configuration: config)
    }()

    private init() {}

    public static let toolDefinition = """
    {
        "name": "web_search",
        "description": "Search the web for current information. Use this when you need up-to-date facts, recent events, or information not in your training data.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "The search query. Be specific and concise."
                }
            },
            "required": ["query"]
        }
    }
    """

    public func search(query: String) async -> [WebSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        await MainActor.run {
            self.isSearching = true
            self.lastQuery = trimmed
        }

        defer {
            Task { @MainActor in
                self.isSearching = false
            }
        }

        async let ddgInstantResults = fetchDuckDuckGoInstantAnswer(query: trimmed)
        async let ddgHtmlResults = fetchDuckDuckGoHTML(query: trimmed)
        async let wikiResults = fetchWikipediaResults(query: trimmed)

        let (instant, html, wiki) = await (ddgInstantResults, ddgHtmlResults, wikiResults)

        var combined: [WebSearchResult] = []
        var seenUrls = Set<String>()

        for res in instant {
            if !seenUrls.contains(res.url) {
                seenUrls.insert(res.url)
                combined.append(res)
            }
        }

        for res in html {
            if !seenUrls.contains(res.url) && combined.count < 5 {
                seenUrls.insert(res.url)
                combined.append(res)
            }
        }

        for res in wiki {
            if !seenUrls.contains(res.url) && combined.count < 5 {
                seenUrls.insert(res.url)
                combined.append(res)
            }
        }

        return combined
    }

    public func executeToolCall(_ call: WebSearchToolCall) async -> WebSearchToolResult {
        let results = await search(query: call.arguments.query)
        return WebSearchToolResult(results: results)
    }

    // MARK: - DuckDuckGo Instant Answer

    private func fetchDuckDuckGoInstantAnswer(query: String) async -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

            var results: [WebSearchResult] = []

            if let abstract = json["AbstractText"] as? String, !abstract.isEmpty,
               let abstractURL = json["AbstractURL"] as? String, !abstractURL.isEmpty {
                let source = (json["AbstractSource"] as? String) ?? "DuckDuckGo"
                let heading = (json["Heading"] as? String) ?? query
                results.append(WebSearchResult(
                    title: heading,
                    url: abstractURL,
                    snippet: abstract,
                    sourceName: source
                ))
            }

            if let related = json["RelatedTopics"] as? [[String: Any]] {
                for item in related.prefix(2) {
                    if let text = item["Text"] as? String, !text.isEmpty,
                       let firstURL = item["FirstURL"] as? String, !firstURL.isEmpty {
                        let host = URL(string: firstURL)?.host ?? "Web"
                        results.append(WebSearchResult(
                            title: String(text.prefix(40)),
                            url: firstURL,
                            snippet: text,
                            sourceName: host
                        ))
                    }
                }
            }

            return results
        } catch {
            return []
        }
    }

    // MARK: - DuckDuckGo HTML Search

    private func fetchDuckDuckGoHTML(query: String) async -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let htmlString = String(data: data, encoding: .utf8) else { return [] }

            return parseDuckDuckGoHTML(htmlString)
        } catch {
            return []
        }
    }

    private func parseDuckDuckGoHTML(_ html: String) -> [WebSearchResult] {
        var results: [WebSearchResult] = []

        let snippetRegex = try? NSRegularExpression(
            pattern: #"class="result__snippet"[^>]*href="(?<href>[^"]+)"[^>]*>(?<text>.*?)</a>"#,
            options: [.dotMatchesLineSeparators]
        )

        let titleRegex = try? NSRegularExpression(
            pattern: #"class="result__title">.*?<a[^>]*class="result__url"[^>]*href="(?<href>[^"]+)"[^>]*>(?<title>.*?)</a>"#,
            options: [.dotMatchesLineSeparators]
        )

        let nsString = html as NSString
        let matches = snippetRegex?.matches(in: html, range: NSRange(location: 0, length: nsString.length)) ?? []

        for match in matches.prefix(6) {
            let hrefRange = match.range(withName: "href")
            let textRange = match.range(withName: "text")

            if hrefRange.location != NSNotFound, textRange.location != NSNotFound {
                var rawHref = nsString.substring(with: hrefRange)
                let rawText = nsString.substring(with: textRange)

                if let uddgRange = rawHref.range(of: "uddg=") {
                    let encodedUrl = String(rawHref[uddgRange.upperBound...]).components(separatedBy: "&").first ?? ""
                    if let decoded = encodedUrl.removingPercentEncoding {
                        rawHref = decoded
                    }
                } else if rawHref.hasPrefix("//") {
                    rawHref = "https:" + rawHref
                }

                let cleanSnippet = cleanHTML(rawText)
                if !cleanSnippet.isEmpty && rawHref.hasPrefix("http") {
                    let host = URL(string: rawHref)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Web"
                    results.append(WebSearchResult(
                        title: host.capitalized,
                        url: rawHref,
                        snippet: cleanSnippet,
                        sourceName: host
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Wikipedia Search

    private func fetchWikipediaResults(query: String) async -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&format=json&utf8=1") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let queryDict = json["query"] as? [String: Any],
                  let searchArray = queryDict["search"] as? [[String: Any]] else {
                return []
            }

            var results: [WebSearchResult] = []
            for item in searchArray.prefix(2) {
                if let title = item["title"] as? String,
                   let snippet = item["snippet"] as? String {
                    let cleanSnippet = cleanHTML(snippet)
                    let articleURL = "https://en.wikipedia.org/wiki/" + (title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)
                    results.append(WebSearchResult(
                        title: "\(title) - Wikipedia",
                        url: articleURL,
                        snippet: cleanSnippet,
                        sourceName: "Wikipedia"
                    ))
                }
            }

            return results
        } catch {
            return []
        }
    }

    // MARK: - Helpers

    private func cleanHTML(_ html: String) -> String {
        var str = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        str = str.replacingOccurrences(of: "&", with: "&")
        str = str.replacingOccurrences(of: "\u{201C}", with: "\"")
        str = str.replacingOccurrences(of: "\u{201D}", with: "\"")
        str = str.replacingOccurrences(of: "\u{2018}", with: "'")
        str = str.replacingOccurrences(of: "\u{2019}", with: "'")
        str = str.replacingOccurrences(of: "<", with: "<")
        str = str.replacingOccurrences(of: ">", with: ">")
        str = str.replacingOccurrences(of: "&nbsp;", with: " ")
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Agentic Requirement & Intent Evaluation

    public func evaluateRequirement(for userText: String, mode: AgenticSearchMode) -> AgenticDecision {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AgenticDecision(requiresSearch: false, searchQuery: nil, reason: "Empty input.")
        }

        switch mode {
        case .off:
            return AgenticDecision(requiresSearch: false, searchQuery: nil, reason: "Web search disabled by user.")

        case .on:
            let query = cleanAndFormulateQuery(from: trimmed)
            return AgenticDecision(requiresSearch: true, searchQuery: query, reason: "Web search forced by user mode.")

        case .auto:
            let lower = trimmed.lowercased()

            // 1. Direct Negative Rules: Obvious non-search queries
            // A. Programming & Technical implementation
            let codeKeywords = [
                "write a function", "write code", "implement", "create a class", "create a struct",
                "how to write", "syntax for", "debug", "error in code", "regex", "sql query",
                "swift code", "python code", "javascript code", "typescript", "c++ code", "algorithm"
            ]
            if codeKeywords.contains(where: { lower.contains($0) }) || trimmed.contains("```") || trimmed.hasPrefix("func ") || trimmed.hasPrefix("def ") || trimmed.hasPrefix("class ") {
                return AgenticDecision(requiresSearch: false, searchQuery: nil, reason: "Code generation / technical request answered directly from internal knowledge.")
            }

            // B. Creative writing & brainstorming
            let creativeKeywords = [
                "write a poem", "write a story", "write an essay", "tell me a joke", "write a haiku",
                "brainstorm", "write lyrics", "draft an email", "rewrite this", "summarize this",
                "roleplay", "pretend you are", "write a speech"
            ]
            if creativeKeywords.contains(where: { lower.contains($0) }) {
                return AgenticDecision(requiresSearch: false, searchQuery: nil, reason: "Creative request generated directly.")
            }

            // C. Chit-Chat / Greetings / Persona
            let chatKeywords = [
                "hello", "hi there", "hey", "how are you", "who are you", "what is your name",
                "what can you do", "good morning", "good evening", "good afternoon", "thank you",
                "thanks", "bye", "goodbye"
            ]
            if chatKeywords.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ",") }) {
                return AgenticDecision(requiresSearch: false, searchQuery: nil, reason: "Conversational greeting handled directly.")
            }

            // D. Pure Math & Logic
            let mathKeywords = [
                "solve", "calculate", "derivative", "integral", "what is 2 +", "what is 2+",
                "multiplied by", "divided by", "square root of"
            ]
            if mathKeywords.contains(where: { lower.contains($0) }) {
                return AgenticDecision(requiresSearch: false, searchQuery: nil, reason: "Math/Logic computation performed directly.")
            }

            // 2. Direct Positive Rules: Explicit or Strong Recency / Live Information Requirement
            // A. Explicit search command
            let explicitSearch = [
                "search for", "search the web", "search online", "google", "look up online",
                "find online", "browse the web", "check the internet"
            ]
            if explicitSearch.contains(where: { lower.contains($0) }) {
                let query = cleanAndFormulateQuery(from: trimmed)
                return AgenticDecision(requiresSearch: true, searchQuery: query, reason: "User explicitly requested live web search.")
            }

            // B. Recency / Real-Time markers
            let recencyMarkers = [
                "today", "yesterday", "tonight", "this morning", "this week", "this month",
                "current", "currently", "latest", "recent", "recently", "newest", "upcoming",
                "right now", "breaking news", "released yet", "latest release", "happening now",
                "schedule today", "who won", "score of", "match result"
            ]
            if recencyMarkers.contains(where: { lower.contains($0) }) {
                let query = cleanAndFormulateQuery(from: trimmed)
                return AgenticDecision(requiresSearch: true, searchQuery: query, reason: "Real-time or recency requirement detected.")
            }

            // C. Temporal year indicators for current/future events
            let yearMarkers = ["2024", "2025", "2026", "2027"]
            if yearMarkers.contains(where: { lower.contains($0) }) {
                let query = cleanAndFormulateQuery(from: trimmed)
                return AgenticDecision(requiresSearch: true, searchQuery: query, reason: "Current/recent year reference requires factual grounding.")
            }

            // D. Live dynamic data domains
            let liveDomains = [
                "weather in", "temperature in", "forecast for",
                "stock price", "share price", "crypto price", "market cap", "bitcoin price", "ethereum price",
                "election", "president of", "prime minister of", "ceo of", "who is the current"
            ]
            if liveDomains.contains(where: { lower.contains($0) }) {
                let query = cleanAndFormulateQuery(from: trimmed)
                return AgenticDecision(requiresSearch: true, searchQuery: query, reason: "Live domain entity state requires real-time facts.")
            }

            // Default for general knowledge / reasoning: Answer directly
            return AgenticDecision(requiresSearch: false, searchQuery: nil, reason: "General knowledge answered directly from internal training data.")
        }
    }

    // MARK: - Query Formulator

    public func cleanAndFormulateQuery(from userText: String) -> String {
        var query = userText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove conversational filler and search commands
        let prefixesToRemove = [
            "can you search the web and tell me",
            "can you search the web for",
            "can you search online for",
            "can you search for",
            "can you look up",
            "can you tell me",
            "search the web for",
            "search the web and find",
            "search online for",
            "search for",
            "look up online",
            "look up",
            "please find",
            "please search",
            "google",
            "what is the latest",
            "what is the current",
            "what are the latest",
            "what are the current",
            "tell me about the latest",
            "tell me about"
        ]

        for prefix in prefixesToRemove {
            if query.lowercased().hasPrefix(prefix) {
                query = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Clean trailing punctuation
        while query.hasSuffix("?") || query.hasSuffix("!") || query.hasSuffix(".") {
            query.removeLast()
            query = query.trimmingCharacters(in: .whitespaces)
        }

        // If query is too short after cleaning, fall back to user text
        if query.count < 3 {
            query = userText
        }

        return query
    }
}