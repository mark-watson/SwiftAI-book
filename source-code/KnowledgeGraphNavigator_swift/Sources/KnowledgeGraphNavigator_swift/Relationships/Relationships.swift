// relationships between DBPedia entities

import SparqlQuery_swift

let relSparql =  """
SELECT DISTINCT ?p {  <e1> ?p <e2> . FILTER (!regex(str(?p), 'wikiPage', 'i')) } LIMIT 5
"""

public func dbpediaGetRelationships(entity1Uri: String, entity2Uri: String) -> [String] {
    var ret: [String] = []
    let sparql1 = relSparql.replacingOccurrences(of: "<e1>", with: entity1Uri).replacingOccurrences(of: "<e2>", with: entity2Uri)
    let r1 = sparqlDbPedia(query: sparql1)
    r1.forEach { result in
        if let relName = result["p"] {
            let rdfStatement = entity1Uri + " <" + relName + "> " + entity2Uri + " ."
            print(rdfStatement)
            ret.append(rdfStatement)
        }
    }
    let sparql2 = relSparql.replacingOccurrences(of: "<e1>", with: entity2Uri).replacingOccurrences(of: "<e2>", with: entity1Uri)
    let r2 = sparqlDbPedia(query: sparql2)
    r2.forEach { result in
        if let relName = result["p"] {
            let rdfStatement = entity2Uri + " <" + relName + "> " + entity1Uri + " ."
            print(rdfStatement)
            ret.append(rdfStatement)
        }
    }
    return Array(Set(ret))
}

public func uriToPrintName(_ uri: String) -> String {
    let slashIndex = uri.lastIndex(of: "/")
    if slashIndex == nil { return uri }
//    var s = String(uri[slashIndex!...])
    var s = uri[slashIndex!...]
    s = s.dropFirst()
    if s.count > 0 { s.removeLast() }
    return String(s).replacingOccurrences(of: "_", with: " ")
    //return uri.substringFromIndex(slashIndex + 1).removeLast()
}

public func relationshipsoEnglish(rs: [String]) -> String {
    var ret = ""
    for r in rs {
        let triples = r.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        print(triples)
        if triples.count > 2 {
            ret += uriToPrintName(String(triples[0])) + " " + uriToPrintName(String(triples[1])) + " " + uriToPrintName(String(triples[2])) + "\n"
        } else {
            ret += r + "\n"
        }
    }
    return ret
}
