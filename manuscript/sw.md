# Linked Data and the Semantic Web

Tim Berners Lee, James Hendler, and Ora Lassila wrote in 2001 an article for Scientific American where they introduced the term Semantic Web. Here I do not capitalize semantic web and use the similar term linked data somewhat interchangeably with semantic web.

In the same way that the web allows links between related web pages, linked data supports linking associated data on the web together. I view linked data as a relatively simple way to specify relationships between data sources on the web while the semantic web has a much larger vision: the semantic web has the potential to be the entirety of human knowledge represented as data on the web in a form that software agents can work with to answer questions, perform research, and to infer new data from existing data.

While the "web" describes information for human readers, the semantic web is meant to provide structured data for ingestion by software agents. This distinction will be clear as we compare WikiPedia, made for human readers, with DBPedia which uses the info boxes on WikiPedia topics to automatically extract RDF data describing WikiPedia topics. Let's look at the WikiPedia topic for the town I live in Sedona, Arizona, and show how the info box on the English version of the [WikiPedia topic page for Sedona https://en.wikipedia.org/wiki/Sedona,_Arizona](https://en.wikipedia.org/wiki/Sedona,_Arizona) maps to the [DBPedia page http://dbpedia.org/page/Sedona,_Arizona](http://dbpedia.org/page/Sedona,_Arizona). Please open both of these WikiPedia and DBPedia URIs in two browser tabs and keep them open for reference.

I assume that the format of the WikiPedia page is familiar so let's look at the DBPedia page for Sedona that in human readble form shows the RDF statements with Sedona Arizona as the subject. RDF is used to model and represent data. RDF is defined by three values so an instance of an RDF statement is called a *triple* with three parts:

- subject: a URI (also referred to as a "Resource")
- property: a URI (also referred to as a "Resource")
- value: a URI (also referred to as a "Resource") or a literal value (like a string or a number with optional units)

The subject for each Sedona related triple is the above URI for the DBPedia human readable page. The subject and property references in an RDF triple will almost always be a URI that can ground an entity to information on the web. The human readable page for Sedona lists several properties and the values of these properties. One of the properties is "dbo:areaCode" where "dbo" is a name space reference (in this case for a [DatatypeProperty](http://www.w3.org/2002/07/owl#DatatypeProperty)).

The following two figures show an abstract representation of linked data and then a sample of linked data with actual web URIs for resources and properties:

{width=50%}
![Abstract RDF representation with 2 Resources, 2 literal values, and 3 Properties](images/rdf1.png)

{width=75%}
![Concrete example using RDF seen in last chapter showing the RDF representation with 2 Resources, 2 literal values, and 3 Properties](images/rdf2.png)

We will use the SPARQL query language (SPARQL for RDF data is similar to SQL for relational database queries). Let's look at an example using the RDF in the last figure:

        "select ?v where { <http://markwatson.com/index.rdf#Sun_ONE>
                           <http://www.ontoweb.org/ontology/1#booktitle>
                           ?v }

This query should return the result "Sun ONE Services - J2EE". If you wanted to query for all URI resources that are books with the literal value of their titles, then you can use:

        "select ?s ?v where { ?s
                              <http://www.ontoweb.org/ontology/1#booktitle>
                              ?v }


Note that **?s** and **?v** are arbitrary query variable names, here standing for "subject" and "value". You can use more descriptive variable names like:

        "select ?bookURI ?bookTitle where 
            { ?bookURI
              <http://www.ontoweb.org/ontology/1#booktitle>
              ?bookTitle }


We will be diving a little deeper into RDF examples in the next chapter when we write a tool for using RDF data from DBPedia to find information about entities (e.g., people, places, organizations) and the relationships between entities.  For now I want you to understand the idea of RDF statements represented as triples, that web URIs represent things, properties, and sometimes values, and that URIs can be followed manually (often called "dereferencing") to see what they reference in human readable form.

## Understanding the Resource Description Framework (RDF)

Text data on the web has some structure in the form of HTML elements like headers, page titles, anchor links, etc. but this structure is too imprecise for general use by software agents. RDF is a method for encoding structured data in a more precise way.

RDF specifies graph structures and can be serialized for storage  or for service calls in XML, Turtle, N3, and other formats. I like the Turtle format and suggest that you pause reading this book for a few minutes and look at this World Wide Web Consortium Turtle RDF primer at [https://www.w3.org/2007/02/turtle/primer/](https://www.w3.org/2007/02/turtle/primer/).


## Frequently Used Resource Namespaces

The following standard namespaces are frequently used:

- RDF       [https://www.w3.org/TR/rdf-syntax-grammar/](https://www.w3.org/TR/rdf-syntax-grammar/)
- RDFS      [https://www.w3.org/TR/rdf-schema/](https://www.w3.org/TR/rdf-schema/)
- OWL       [http://www.w3.org/2002/07/owl#](http://www.w3.org/2002/07/owl#)
- XSD       [http://www.w3.org/2001/XMLSchema#](http://www.w3.org/2001/XMLSchema#)
- FOAF      [http://xmlns.com/foaf/0.1/](http://xmlns.com/foaf/0.1/)
- SKOS      [http://www.w3.org/2004/02/skos/core#](http://www.w3.org/2004/02/skos/core#)
- DOAP      [http://usefulinc.com/ns/doap#](http://usefulinc.com/ns/doap#)
- DC        [http://purl.org/dc/elements/1.1/](http://purl.org/dc/elements/1.1/)
- DCTERMS   [http://purl.org/dc/terms/](http://purl.org/dc/terms/)
- VOID      [http://rdfs.org/ns/void#](http://rdfs.org/ns/void#)

Let's look into the Friend of a Friend (FOAF) namespace. Click on the above link for FOAF [http://xmlns.com/foaf/0.1/](http://xmlns.com/foaf/0.1/) and find the definitions for the FOAF Core:

        Agent
        Person
        name
        title
        img
        depiction (depicts)
        familyName
        givenName
        knows
        based_near
        age
        made (maker)
        primaryTopic (primaryTopicOf)
        Project
        Organization
        Group
        member
        Document
        Image

and for the Social Web:

    mbox
    homepage
    weblog
    openid
    jabberID
    mbox_sha1sum
    interest
    topic_interest
    topic (page)
    workplaceHomepage
    workInfoHomepage
    schoolHomepage
    publications
    currentProject
    pastProject
    account
    OnlineAccount
    accountName
    accountServiceHomepage
    PersonalProfileDocument
    tipjar
    sha1
    thumbnail
    logo

You now have seen a few common Schemas for RDF data. Another Schema that is widely used for annotating web sites that we won't need for our examples here, is [schema.org](https://schema.org).

## Understanding the SPARQL Query Language

For the purposes of the material in this book, the two sample SPARQL queries here are sufficient for you to get started using my SPARQL library [https://github.com/mark-watson/SparqlQuery_swift](https://github.com/mark-watson/SparqlQuery_swift) with arbitrary RDF data sources and simple queries.

{width: "90%"}
![My Swift SPARQL library open in Xcode](images/xcode_sparql.png)


The Apache Foundation has a [good introduction to SPARQL](https://jena.apache.org/tutorials/sparql.html) that I refer you to for more information.


## Semantic Web and Linked Data Wrap Up

In the next chapter we will use natural language processing to extract structured information from raw text from SPARQL queries. We will be using my Swift SPARQL library [https://github.com/mark-watson/SparqlQuery_swift](https://github.com/mark-watson/SparqlQuery_swift) as well as two pre-trained CoreML deep learning models.

