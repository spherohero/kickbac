import Foundation

// Run from the repository root:
// swiftc ios/KickBAC/PhoneCountry.swift ios/checks/PhoneInputChecks.swift -o /tmp/kickbac-phone-input-checks
// /tmp/kickbac-phone-input-checks ios/KickBAC/PhoneCountries.json
@main
struct PhoneInputChecks {
    @MainActor
    static func main() throws {
        let data = try Data(contentsOf: URL(filePath: CommandLine.arguments[1]))
        let countries = try JSONDecoder().decode([PhoneCountry].self, from: data)
        precondition(Set(countries.map(\.id)).count == countries.count)

        for country in countries {
            precondition(country.isPossibleNumber(country.example), country.id)
            let international = "+" + country.dialingCode + country.example
            precondition(country.isPossibleNumber(international), country.id)
            precondition(country.isPossibleNumber(country.formatted(international)), country.id)
            precondition(!country.isPossibleNumber(""), country.id)
            precondition(!country.isPossibleNumber("12"), country.id)
            precondition(!country.isPossibleNumber(String(repeating: "9", count: 16)), country.id)
        }

        let us = PhoneCountry.unitedStates
        precondition(us.formatted("+1 201 555 0123") == "(201) 555-0123")
        precondition(us.formatted("12015550123") == "(201) 555-0123")
        precondition(!us.isPossibleNumber("201555012"))
        precondition(!us.isPossibleNumber("+44 7400 123456"))

        let uk = countries.first { $0.id == "GB" }!
        precondition(uk.dialingCode == "44")
        precondition(uk.nationalDigits(in: "07400123456") == "7400123456")
        precondition(uk.isPossibleNumber("07400123456"))
        precondition(uk.formatted("+44 7400 123456") == "7400123456")
        precondition(uk.formatted(us.formatted("2015550123")) == "2015550123")
        precondition(us.formatted(uk.formatted("2015550123")) == "(201) 555-0123")

        let italy = countries.first { $0.id == "IT" }!
        precondition(italy.nationalDigits(in: "0212345678") == "0212345678")

        print("Phone input checks passed for \(countries.count) countries and territories.")
    }
}
