// SparqlQuery_swift.swift
// Copyright 2022-2026 Mark Watson. All rights reserved.
//
// Swift library for querying SPARQL endpoints (DBpedia, Wikidata, etc.)
// Uses async/await and Codable — no external dependencies required.

import Foundation

// MARK: - Codable response model

private struct SPARQLResponse: Codable {
    let head: Head
    let results: Results

    struct Head: Codable {
        let vars: [String]
    }

    struct Results: Codable {
        let bindings: [Binding]
    }

    // Each binding is a dictionary of variable name → { type, value }
    struct Binding: Codable {
        let values: [String: BoundValue]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            values = try container.decode([String: BoundValue].self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(values)
        }
    }

    struct BoundValue: Codable {
        let type: String
        let value: String
    }
}

// MARK: - Public async API

/// Query the DBpedia SPARQL endpoint and return results as an array of
/// `[variableName: value]` dictionaries.
public func sparqlDBpedia(query: String) async throws -> [[String: String]] {
    let endpoint = "https://dbpedia.org/sparql?query="
    return try await sparqlEndpoint(query: query, endpointURI: endpoint)
}

/// Query the Wikidata SPARQL endpoint and return results as an array of
/// `[variableName: value]` dictionaries.
public func sparqlWikidata(query: String) async throws -> [[String: String]] {
    let endpoint = "https://query.wikidata.org/bigdata/namespace/wdq/sparql?query="
    return try await sparqlEndpoint(query: query, endpointURI: endpoint)
}

/// Generic SPARQL endpoint query. Pass any standards-compliant SPARQL 1.1
/// endpoint URI (with the `query=` parameter already appended).
public func sparqlEndpoint(
    query: String,
    endpointURI: String
) async throws -> [[String: String]] {
    guard let encoded = query.addingPercentEncoding(
        withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: endpointURI + encoded + "&format=json")
    else {
        throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")

    let (data, response) = try await URLSession.shared.data(for: request)

    if let httpResponse = response as? HTTPURLResponse,
       !(200...299).contains(httpResponse.statusCode) {
        throw URLError(.badServerResponse)
    }

    let sparqlResponse = try JSONDecoder().decode(SPARQLResponse.self, from: data)
    let vars = sparqlResponse.head.vars

    return sparqlResponse.results.bindings.compactMap { binding in
        var row = [String: String]()
        for variable in vars {
            if let bound = binding.values[variable] {
                row[variable] = bound.value
            }
        }
        return row.isEmpty ? nil : row
    }
}
