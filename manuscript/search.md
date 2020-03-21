Using the Microsoft Bing Search APIs in Swift



{lang="swift",linenos=on}
~~~~~~~~
import Foundation

let endpoint = "https://api.cognitive.microsoft.com/bing/v7.0/search"
let apiKey = "???" value of BING_SEARCH_V7_SUBSCRIPTION_KEY

public func searchText(query: String, completionHandler: @escaping (String) -> Void) {
    print("+ entering searchText: ", query)
    var components = URLComponents(string: endpoint)!
    components.queryItems = [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "count", value: "2")
    ]

    var request = URLRequest(url: components.url!)
    request.addValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")

    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
        if let error = error {
            fatalError(error.localizedDescription)
        }

        guard let data = data else {
            fatalError("Empty response")
        }
        let str = String(decoding: data, as: UTF8.self)
        print("+   str:", str)
        let json = try? JSONSerialization.jsonObject(with: data, options: [])
        if let json2 = json as! Optional<Dictionary<String, Any?>> {
            if let head = json2["webPages"] as? Dictionary<String, Any> {
                if let xvars = head["value"] as! NSArray? {
                    print(xvars)
                    for x in xvars {
                        print(x)
                        if let d1: Dictionary<String, Any> = x as? Dictionary<String, Any> {
                            if let u = d1["displayUrl"] {
                               print("displayUrl", u)
                            }
                        }
                    }
                }
            }
        }
        completionHandler(str)
    }

    task.resume()
}

//PlaygroundPage.current.needsIndefiniteExecution = true

~~~~~~~~
