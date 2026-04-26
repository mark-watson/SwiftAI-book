import XCTest
@testable import SparqlQuery_swift

final class SparqlQueryTests: XCTestCase {

    func testDBpediaQuery() async throws {
        let query = """
        SELECT ?population WHERE {
          <http://dbpedia.org/resource/Sedona,_Arizona>
          <http://dbpedia.org/ontology/populationTotal>
          ?population
        }
        """
        let results = try await sparqlDBpedia(query: query)
        print("DBpedia results:", results)
        XCTAssertFalse(results.isEmpty, "Expected at least one result from DBpedia")
        XCTAssertNotNil(results.first?["population"])
    }
}
