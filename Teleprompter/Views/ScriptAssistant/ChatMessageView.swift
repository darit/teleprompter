import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            Text(message.content)
                .font(.system(size: 13))
                .lineSpacing(4)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(message.role == .user
                              ? Color.accentColor.opacity(0.08)
                              : Color.primary.opacity(0.04))
                }
                .frame(maxWidth: 500, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

#Preview("Assistant message") {
    ChatMessageView(message: ChatMessage(role: .assistant, content: "I've reviewed your slides. Let me ask about Slide 1: Introduction. What key points do you want to emphasize?"))
        .padding()
}

#Preview("User message") {
    ChatMessageView(message: ChatMessage(role: .user, content: "I want to mention the team growth from 5 to 12 engineers."))
        .padding()
}
