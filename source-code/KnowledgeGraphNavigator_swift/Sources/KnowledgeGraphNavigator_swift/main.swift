
func testE1() {
    let x = processEntities(inputString: "Bill Gates was at Microsoft with Melinda Gates. He knew Steve Jobs in California")
    print("testE1: x=", x)
    for y in x {
        print(y.name, "\t", y.uri)
    }
}

testE1()

func testE2() {
    let relationships = getAllRelationships(inputString: "Bill Gates was at Microsoft with Melinda Gates and helped Steve Jobs save Apple Computer")
    print("====== relationships:")
    for r in relationships {
        print(r)
    } 
}

testE2()

func test1() {
    print("\n** entity detail:\n")
    let z = entityDetail(name:"Microsoft")
    print(z)
    
    print("\n** organizationDetail:\n")
    let z1 = organizationDetail(name:"Microsoft")
    print(z1)
    
    print("\n** person detail:\n")
    let x = personDetail(name:"Bill Gates")
    print(x)
    print("\n** place detal:\n")
    let y = placeDetail(name:"California")
    print(y)
    for place in y {
        print(type(of: place))
        print(place["uri"]!)
    }
    
    print("\n** Entity relationships:\n", y)
    let er = dbpediaGetRelationships(entity1Uri: "<http://dbpedia.org/resource/Bill_Gates>",
                                     entity2Uri: "<http://dbpedia.org/resource/Microsoft>")
    print(er)
}

test1()

print(uriToPrintName("<http://dbpedia.org/resource/Bill_Gates>"))
print(uriToPrintName("<http://dbpedia.org/ontology/knownFor>"))
print(uriToPrintName("<http://dbpedia.org/resource/"))

let er = dbpediaGetRelationships(entity1Uri: "<http://dbpedia.org/resource/Bill_Gates>",
                                 entity2Uri: "<http://dbpedia.org/resource/Microsoft>")

print(relationshipsoEnglish(rs: er))

