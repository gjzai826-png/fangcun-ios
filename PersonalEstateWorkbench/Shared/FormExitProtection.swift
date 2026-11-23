import SwiftUI

struct FormExitProtection: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    var isDirty: Bool
    @State private var confirm = false

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(isDirty)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        if isDirty { confirm = true } else { dismiss() }
                    }
                }
            }
            .confirmationDialog("放弃未保存的更改？", isPresented: $confirm, titleVisibility: .visible) {
                Button("放弃更改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            } message: {
                Text("已填写的内容会丢失。")
            }
    }
}

extension View {
    func formExitProtection(isDirty: Bool) -> some View {
        modifier(FormExitProtection(isDirty: isDirty))
    }
}
