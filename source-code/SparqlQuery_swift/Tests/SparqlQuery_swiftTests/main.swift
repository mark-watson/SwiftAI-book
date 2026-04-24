import XCTest
@testable import SparqlQuery_swift

final class TempLibTests: XCTestCase {
    
    func testQueryCheck() {
        let z = sparqlDbPedia(query: "select * where { ?s ?p \"Steve Jobs\"@en } limit 5")
        print(z)
        //dump(z)
    }
}
