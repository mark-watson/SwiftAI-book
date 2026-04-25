//  AppSparql.swift
//  Created by ML Watson on 7/18/21.

import Foundation
import Nlp_swift
import SparqlQuery_swift

let detailSparql = """
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
select ?entity ?label ?description ?comment where {
    ?entity rdfs:label "<name>"@en .
    ?entity schema:description ?description .
    filter (lang(?description) = 'en') .
    filter(!regex(?description,"Wikimedia disambiguation page")) .
 } limit 5000
"""

let personSparql = """
  select ?uri ?comment {
      ?uri <http://xmlns.com/foaf/0.1/name> "<name>"@en .
      ?uri <http://www.w3.org/2000/01/rdf-schema#comment>
              ?comment .
          FILTER  (lang(?comment) = 'en') .
  }
"""


let personDetailSparql = """
SELECT DISTINCT ?label ?comment
 (GROUP_CONCAT(DISTINCT ?birthplace; SEPARATOR=' | ')
      AS ?birthplace)
 (GROUP_CONCAT(DISTINCT ?almamater; SEPARATOR=' | ')
      AS ?almamater)
 (GROUP_CONCAT(DISTINCT ?spouse; SEPARATOR=' | ')
      AS ?spouse) {
 <name> <http://www.w3.org/2000/01/rdf-schema#comment>
         ?comment .
       FILTER  (lang(?comment) = 'en') .
 OPTIONAL {
     <name> <http://dbpedia.org/ontology/birthPlace>
             ?birthplace } .
 OPTIONAL {
     <name> <http://dbpedia.org/ontology/almaMater>
             ?almamater } .
 OPTIONAL {
     <name> <http://dbpedia.org/ontology/spouse>
             ?spouse } .
 OPTIONAL {
     <name> <http://www.w3.org/2000/01/rdf-schema#label>
             ?label .
     FILTER  (lang(?label) = 'en') }
} LIMIT 10
"""

let placeSparql = """
SELECT DISTINCT ?uri ?comment WHERE {
       ?uri rdfs:label "<name>"@en .
       ?uri <http://www.w3.org/2000/01/rdf-schema#comment>
               ?comment .
       FILTER (lang(?comment) = 'en') .
       ?place <http://www.w3.org/1999/02/22-rdf-syntax-ns#type>
              <http://schema.org/Place> .
} LIMIT 80
"""

let organizationSparql = """
SELECT DISTINCT ?uri ?comment WHERE {
       ?uri rdfs:label "<name>"@en .
       ?uri <http://www.w3.org/2000/01/rdf-schema#comment>
               ?comment .
       FILTER (lang(?comment) = 'en') .
       ?uri <http://www.w3.org/1999/02/22-rdf-syntax-ns#type>
            <http://schema.org/Organization> .
} LIMIT 80
"""

func entityDetail(
    name: String
) -> [Dictionary<String, String>] {
    var ret: [Dictionary<String, String>] = []
    let sparql = detailSparql
        .replacingOccurrences(of: "<name>", with: name)
    print(sparql)
    let r = sparqlDbPedia(query: sparql)
    r.forEach { result in
        print(result)
        ret.append(result)
    }
    return ret
}

func personDetail(
    name: String
) -> [Dictionary<String, String>] {
    var ret: [Dictionary<String, String>] = []
    let sparql = personSparql
        .replacingOccurrences(of: "<name>", with: name)
    print(sparql)
    let r = sparqlDbPedia(query: sparql)
    r.forEach { result in
        print(result)
        ret.append(result)
    }
    return ret
}

func placeDetail(
    name: String
) -> [Dictionary<String, String>] {
    var ret: [Dictionary<String, String>] = []
    let sparql = placeSparql
        .replacingOccurrences(of: "<name>", with: name)
    print(sparql)
    let r = sparqlDbPedia(query: sparql)
    r.forEach { result in
        print(result)
        ret.append(result)
    }
    return ret
}

func organizationDetail(
    name: String
) -> [Dictionary<String, String>] {
    var ret: [Dictionary<String, String>] = []
    let sparql = organizationSparql
        .replacingOccurrences(of: "<name>", with: name)
    print(sparql)
    let r = sparqlDbPedia(query: sparql)
    r.forEach { result in
        print(result)
        ret.append(result)
    }
    return ret
}

public func processEntities(
    inputString: String
) -> [(name: String, type: String, uri: String, comment: String)] {
    let entities = getEntities(for: inputString)
    var augmentedEntities:
        [(name: String, type: String,
          uri: String, comment: String)] = []
    for (entityName, entityType) in entities {
        print("** entityName:", entityName,
              "entityType:", entityType)
        if entityType == "PersonalName" {
            let data = personDetail(name: entityName)
            print("** person data:", data)
            for d in data {
                augmentedEntities.append((
                    name: entityName,
                    type: entityType,
                    uri: "<" + d["uri"]! + ">",
                    comment: "<" + d["comment"]! + ">"))
            }
        }
        if entityType == "OrganizationName" {
            let data = organizationDetail(name: entityName)
            print("** organization data:", data)
            for d in data {
                augmentedEntities.append((
                    name: entityName,
                    type: entityType,
                    uri: "<" + d["uri"]! + ">",
                    comment: "<" + d["comment"]! + ">"))
            }
        }
        if entityType == "PlaceName" {
            let data = placeDetail(name: entityName)
            print("** place data:", data)
            for d in data {
                augmentedEntities.append((
                    name: entityName,
                    type: entityType,
                    uri: "<" + d["uri"]! + ">",
                    comment: "<" + d["comment"]! + ">"))
            }
        }
    }
    return augmentedEntities
}


extension Array where Element: Hashable {
    func uniqueValuesHelper() -> [Element] {
        var addedDict = [Element: Bool]()
        return filter {
            addedDict.updateValue(true, forKey: $0) == nil
        }
    }
    mutating func uniqueValues() {
        self = self.uniqueValuesHelper()
    }
}


func getAllRelationships(inputString: String) -> [String] {
    let augmentedEntities = processEntities(
        inputString: inputString)
    var relationshipTriples: [String] = []
    for ae1 in augmentedEntities {
        for ae2 in augmentedEntities {
            if ae1 != ae2 {
                let er1 = dbpediaGetRelationships(
                    entity1Uri: ae1.uri,
                    entity2Uri: ae2.uri)
                print("+++++++ er1:", er1,
                      "ae1.uri:", ae1.uri, "ae2.uri:", ae2.uri)
                relationshipTriples.append(contentsOf: er1)
                let er2 = dbpediaGetRelationships(
                    entity1Uri: ae2.uri,
                    entity2Uri: ae1.uri)
                print("+++++++ er2:", er2,
                      "ae1.uri:", ae1.uri, "ae2.uri:", ae2.uri)
                relationshipTriples.append(contentsOf: er2)
            }
        }
    }
    relationshipTriples.uniqueValues()
    relationshipTriples.sort()
    return relationshipTriples
}
