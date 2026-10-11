import AppKit
import PlantUMLCore
import StudioDesign
import SwiftUI

struct SemanticRow: View {
  let node: SemanticNode
  @ObservedObject var document: StudioDocument
  var body: some View {
    HStack(alignment: .top, spacing: 2) {
      if !node.children.isEmpty {
        Button {
          if document.collapsedSemanticNodes.contains(node.id) {
            document.collapsedSemanticNodes.remove(node.id)
          } else {
            document.collapsedSemanticNodes.insert(node.id)
          }
        } label: {
          Image(
            systemName: document.collapsedSemanticNodes.contains(node.id)
              && document.constructorQuery.isEmpty ? "chevron.right" : "chevron.down"
          )
          .font(.system(size: 10)).frame(width: 10, height: 24)
        }.buttonStyle(.plain).help("Свернуть / развернуть")
      } else {
        Color.clear.frame(width: 10, height: 24)
      }
      label
    }.id(node.id).contextMenu {
      if let identifier = node.implicitIdentifier {
        Button("Объявить и редактировать участника") { document.declareParticipant(identifier) }
          .disabled(!document.canEdit)
      } else {
        Button("Редактировать свойства") {
          document.selectObject(node.element, navigate: false)
          document.propertiesCollapsed = false
        }
        Button("Перейти к коду") { document.selectObject(node.element) }.disabled(
          document.parsed.source != document.source)
        if ["entity", "block", "branch"].contains(node.element.kind) {
          Button(node.element.kind == "entity" ? "Добавить атрибут" : "Добавить сообщение") {
            document.edit {
              let text =
                node.element.kind == "entity"
                ? "field : text"
                : "\(SemanticStructure.value("from", of: document.parsed.elements.first { $0.kind == "message" } ?? node.element, in: document.parsed)) -> \(SemanticStructure.value("to", of: document.parsed.elements.first { $0.kind == "message" } ?? node.element, in: document.parsed)) : Сообщение"
              if node.initialBranch {
                return try SemanticOperations.insertIntoFirstBranch(
                  text, block: node.element, in: document.parsed)
              }
              if node.element.kind == "branch" {
                return try SemanticOperations.insert(
                  text, intoBranch: node.element, in: document.parsed)
              }
              return try ConstructorOperations.insertInside(
                text, element: node.element, document: document.parsed)
            }
          }.disabled(
            !document.canEdit
              || node.element.kind != "entity"
                && !document.parsed.elements.contains { $0.kind == "message" }
          )
        }
        if !node.initialBranch {
          if node.element.kind == "message" {
            Button("Ответное сообщение") {
              document.edit { try QuickOperations.reply(to: node.element, in: document.parsed) }
            }.disabled(!document.canEdit)
            ForEach(["alt", "opt", "loop"], id: \.self) { type in
              Button("Обернуть в \(type.uppercased())") {
                document.edit {
                  try QuickOperations.wrap([node.element], with: type, in: document.parsed)
                }
              }.disabled(!document.canEdit)
            }
          }
          if ["message", "block", "entity"].contains(node.element.kind) {
            Button("Дублировать") {
              document.edit { try QuickOperations.duplicate(node.element, in: document.parsed) }
            }.disabled(!document.canEdit)
          }
          Button("Переместить вверх") {
            document.edit {
              try ConstructorOperations.move(node.element, up: true, in: document.parsed)
            }
          }.disabled(!canMove(up: true))
          Button("Переместить вниз") {
            document.edit {
              try ConstructorOperations.move(node.element, up: false, in: document.parsed)
            }
          }.disabled(!canMove(up: false))
          Button("Удалить", role: .destructive) { document.requestDelete(node.element) }.disabled(
            !document.canEdit || ["unsupported"].contains(node.element.kind))
        }
      }
    }
  }
  var label: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: node.icon).frame(width: 15).foregroundStyle(DesignToken.accent.color)
      VStack(alignment: .leading, spacing: 2) {
        Text(node.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
        if !node.subtitle.isEmpty {
          Text(node.subtitle).font(.system(size: 10)).foregroundStyle(
            DesignToken.secondaryText.color
          ).lineLimit(2)
        }
      }
      Spacer(minLength: 0)
      if let color = node.color {
        Circle().fill(displayColor(color)).frame(width: 8, height: 8).overlay(
          Circle().stroke(DesignToken.border.color)
        ).help(color)
      }
    }.padding(5).frame(maxWidth: .infinity, alignment: .leading)
      .background(
        (node.implicitIdentifier != nil
          ? node.implicitIdentifier == document.selectedImplicitParticipant
          : document.multiSelection.contains(node.element.id)
            && node.initialBranch == document.selectionFirstBranch)
          ? DesignToken.accent.color.opacity(0.14) : Color.clear
      )
      .clipShape(RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle()).help(
        node.title + (node.subtitle.isEmpty ? "" : "\n" + node.subtitle)
      )
      .onTapGesture {
        if let identifier = node.implicitIdentifier {
          document.selectImplicitParticipant(identifier, reference: node.element)
        } else {
          document.selectObject(
            node.element, additive: NSApp.currentEvent?.modifierFlags.contains(.command) == true)
          document.selectionFirstBranch = node.initialBranch
        }
      }
  }
  func canMove(up: Bool) -> Bool {
    document.canEdit && ConstructorOperations.canMove(node.element, up: up, in: document.parsed)
  }
  func displayColor(_ value: String) -> Color {
    let value = String(value.dropFirst())
    if value.count == 6, let rgb = UInt32(value, radix: 16) {
      return Color(
        red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
        blue: Double(rgb & 255) / 255)
    }
    return [
      "red": Color.red, "green": .green, "blue": .blue, "lightblue": .cyan, "white": .white,
      "black": .black, "yellow": .yellow, "orange": .orange, "pink": .pink, "purple": .purple,
      "gray": .gray,
    ][value.lowercased()] ?? DesignToken.secondaryText.color
  }
}
