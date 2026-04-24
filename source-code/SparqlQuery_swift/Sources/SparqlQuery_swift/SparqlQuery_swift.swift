import Foundation

public func sparqlDbPedia(query: String) -> Array<Dictionary<String,String>> {
    return SparqlEndpointHelpter(query: query, endPointUri: "https://dbpedia.org/sparql?query=") }

public func sparqlWikidata(query: String) -> Array<Dictionary<String,String>> {
    return SparqlEndpointHelpter(query: query, endPointUri: "https://query.wikidata.org/bigdata/namespace/wdq/sparql?query=") }

public func SparqlEndpointHelpter(query: String, endPointUri: String) -> Array<Dictionary<String,String>> {
    var ret = Set<Dictionary<String,String>>();
    var content = "{}"

    let maybeString = cacheLookupQuery7(key: query)
    if maybeString?.count ?? 0 > 0 {
        content = maybeString ?? ""
    } else {
        let requestUrl = URL(string: String(endPointUri + query.addingPercentEncoding(withAllowedCharacters:     .urlHostAllowed)!) + "&format=json")!
        do { content = try String(contentsOf: requestUrl) } catch let error { print(error) }
    }
    let json = try? JSONSerialization.jsonObject(with: Data(content.utf8), options: [])
    if let json2 = json as! Optional<Dictionary<String, Any?>> {
        if let head = json2["head"] as? Dictionary<String, Any> {
            if let xvars = head["vars"] as! NSArray? {
                if let results = json2["results"] as? Dictionary<String, Any> {
                    if let bindings = results["bindings"] as! NSArray? {
                        if bindings.count > 0 {
                            for i in 0...(bindings.count-1) {
                                if let first_binding = bindings[i] as? Dictionary<String, Dictionary<String,String>> {
                                    var ret2 = Dictionary<String,String>();
                                    for key in xvars {
                                        let key2 : String = key as! String
                                        if let vals = (first_binding[key2]) {
                                            let vv : String = vals["value"] ?? "err2"
                                            ret2[key2] = vv } }
                                    if ret2.count > 0 {
                                        ret.insert(ret2)
                                    }}}}}}}}}
    return Array(ret) }

