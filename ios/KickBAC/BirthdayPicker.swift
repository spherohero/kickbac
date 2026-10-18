import SwiftUI
import UIKit

// A single native picker keeps the selection band continuous across all three wheels.
struct BirthdayPicker: UIViewRepresentable {
    @Binding var selection: Date
    @ScaledMetric(relativeTo: .title) private var fontSize: CGFloat = 32

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        picker.reloadAllComponents()
        for (index, component) in [Calendar.Component.day, .month, .year].enumerated() {
            let value = calendar.component(component, from: selection)
            picker.selectRow(value - (component == .year ? 1900 : 1), inComponent: index, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewAccessibilityDelegate {
        var parent: BirthdayPicker

        init(_ parent: BirthdayPicker) { self.parent = parent }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 3 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            switch component {
            case 0: parent.calendar.range(of: .day, in: .month, for: parent.selection)?.count ?? 31
            case 1: 12
            default: parent.calendar.component(.year, from: .now) - 1900 + 1
            }
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            max(44, parent.fontSize * 1.35)
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            pickerView.bounds.width * (component == 2 ? 0.4 : 0.3)
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            switch component {
            case 0: String(row + 1)
            case 1: parent.calendar.shortMonthSymbols[row]
            default: String(row + 1900)
            }
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = view as? UILabel ?? UILabel()
            let font = UIFont.systemFont(ofSize: parent.fontSize, weight: .medium)
            label.font = UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: parent.fontSize)
            label.textAlignment = .center
            label.textColor = .label
            label.text = self.pickerView(pickerView, titleForRow: row, forComponent: component)
            return label
        }

        func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
            ["Day", "Month", "Year"][component]
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            var parts = parent.calendar.dateComponents([.year, .month, .day], from: parent.selection)
            let field = [Calendar.Component.day, .month, .year][component]
            parts.setValue(row + (component == 2 ? 1900 : 1), for: field)
            let day = parts.day ?? 1
            parts.day = 1
            guard let month = parent.calendar.date(from: parts),
                  let days = parent.calendar.range(of: .day, in: .month, for: month) else { return }
            parts.day = min(day, days.count)
            if let date = parent.calendar.date(from: parts) { parent.selection = date }
        }
    }
}
