import Foundation

struct PhoneCountry: Decodable, Identifiable, Hashable {
    let id: String
    let dialingCode: String
    let nationalLengths: [Int]
    let nationalPrefix: String
    let example: String

    var name: String { Locale.current.localizedString(forRegionCode: id) ?? id }

    var placeholder: String {
        dialingCode == "1" ? "(201) 555-0123" : example
    }

    static let unitedStates = PhoneCountry(
        id: "US", dialingCode: "1", nationalLengths: [10], nationalPrefix: "1", example: "2015550123"
    )

    // Dialing codes and possible lengths from Google's libphonenumber metadata.
    // https://github.com/google/libphonenumber/blob/master/resources/PhoneNumberMetadata.xml
    // See Libphonenumber-LICENSE.txt for the Apache 2.0 license.
    static let all: [PhoneCountry] = {
        guard let url = Bundle.main.url(forResource: "PhoneCountries", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let countries = try? JSONDecoder().decode([PhoneCountry].self, from: data) else {
            assertionFailure("Missing phone country metadata")
            return [.unitedStates]
        }
        return countries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    func formatted(_ input: String) -> String {
        var digits = input.filter { $0.isASCII && $0.isNumber }
        if input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+") {
            guard digits.hasPrefix(dialingCode) else { return "+" + digits }
            digits = String(digits.dropFirst(dialingCode.count))
        }
        guard dialingCode == "1" else { return digits }
        if digits.count == 11 && digits.first == "1" { digits.removeFirst() }
        guard digits.count > 3 && digits.count <= 10 else { return digits }
        let area = digits.prefix(3)
        let rest = digits.dropFirst(3)
        if rest.count <= 3 { return "(\(area)) \(rest)" }
        return "(\(area)) \(rest.prefix(3))-\(rest.dropFirst(3))"
    }

    func nationalDigits(in input: String) -> String? {
        var digits = input.filter { $0.isASCII && $0.isNumber }
        if input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+") {
            guard digits.hasPrefix(dialingCode) else { return nil }
            digits = String(digits.dropFirst(dialingCode.count))
        }
        if !nationalPrefix.isEmpty && digits.hasPrefix(nationalPrefix) {
            let withoutPrefix = String(digits.dropFirst(nationalPrefix.count))
            if nationalLengths.contains(withoutPrefix.count) { digits = withoutPrefix }
        }
        return digits
    }

    func isPossibleNumber(_ input: String) -> Bool {
        guard let digits = nationalDigits(in: input) else { return false }
        // Length is an input check; SMS verification still proves ownership.
        return nationalLengths.contains(digits.count) && dialingCode.count + digits.count <= 15
    }
}
