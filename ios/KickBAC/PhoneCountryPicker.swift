import SwiftUI

struct PhoneCountryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: PhoneCountry
    @State private var search = ""

    private var countries: [PhoneCountry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return PhoneCountry.all.filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
                || $0.id.localizedStandardContains(query)
                || ("+" + $0.dialingCode).contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(countries) { country in
                Button {
                    selection = country
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(country.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("+" + country.dialingCode)
                            .foregroundStyle(.secondary)
                        Image("OnboardingCheck")
                            .resizable().scaledToFit()
                            .frame(width: 16, height: 16)
                            .opacity(country.id == selection.id ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(country.id == selection.id ? .isSelected : [])
                .accessibilityIdentifier("phoneCountry-" + country.id)
            }
            .overlay {
                if countries.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Country or code")
            .navigationTitle("Country code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(.black)
        .preferredColorScheme(.light)
    }
}
