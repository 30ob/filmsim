import SwiftUI
import UIKit

// MARK: - 拨盘条目

struct DialItem: Identifiable, Hashable {
    let id: String
    let title: String
    let caption: String
}

// MARK: - 胶片机风格刻度拨盘

/// 手指左右拖动，刻度一格格滑过中心指针，带触碰反馈。
struct TactileDial: View {
    let items: [DialItem]
    @Binding var selectedID: String
    var accent: Color = .white
    var spacing: CGFloat = 68
    var dialHeight: CGFloat = 56

    @State private var dragOffset: CGFloat = 0
    @State private var lastTranslation: CGFloat = 0
    @State private var haptics = UISelectionFeedbackGenerator()

    private var selectedIndex: Int {
        items.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        tick(item: item, index: index)
                            .frame(width: spacing)
                            .contentShape(Rectangle())
                            .onTapGesture { select(index: index) }
                    }
                }
                .offset(x: width / 2 - spacing / 2 - CGFloat(selectedIndex) * spacing + dragOffset)
                .frame(width: width, height: geo.size.height, alignment: .topLeading)
                .clipped()

                Triangle()
                    .fill(accent)
                    .frame(width: 10, height: 6)
                    .position(x: width / 2, y: 7)
            }
            .frame(width: width, height: geo.size.height, alignment: .topLeading)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .frame(height: dialHeight)
    }

    private func tick(item: DialItem, index: Int) -> some View {
        let isSelected = index == selectedIndex
        return VStack(spacing: 2) {
            Rectangle()
                .fill(isSelected ? accent : Color.white.opacity(0.32))
                .frame(width: isSelected ? 2 : 1, height: isSelected ? 15 : 8)
            Text(item.title)
                .font(.system(size: isSelected ? 15 : 12,
                              weight: isSelected ? .semibold : .regular,
                              design: .monospaced))
                .foregroundStyle(isSelected ? accent : Color.white.opacity(0.55))
                .lineLimit(1)
                .fixedSize()
            Text(item.caption)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(isSelected ? accent.opacity(0.75) : Color.white.opacity(0.25))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 12)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let delta = value.translation.width - lastTranslation
                lastTranslation = value.translation.width
                dragOffset += delta

                var index = selectedIndex
                var offset = dragOffset
                while offset > spacing / 2, index > 0 {
                    offset -= spacing
                    index -= 1
                    apply(index: index)
                }
                while offset < -spacing / 2, index < items.count - 1 {
                    offset += spacing
                    index += 1
                    apply(index: index)
                }
                dragOffset = offset
            }
            .onEnded { _ in
                lastTranslation = 0
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    dragOffset = 0
                }
            }
    }

    private func apply(index: Int) {
        guard index >= 0, index < items.count else { return }
        if selectedID != items[index].id {
            selectedID = items[index].id
            haptics.selectionChanged()
        }
    }

    private func select(index: Int) {
        guard index >= 0, index < items.count else { return }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            dragOffset = 0
            apply(index: index)
        }
    }
}

// MARK: - 小三角（拨盘指针）

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 胶片选择条

struct FilmStockStrip: View {
    @Binding var selection: FilmStock

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmStock.allCases) { stock in
                        chip(stock)
                            .id(stock.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .onAppear {
                proxy.scrollTo(selection.id, anchor: .center)
            }
            .onChange(of: selection) { _, newValue in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(newValue.id, anchor: .center)
                }
            }
        }
    }

    private func chip(_ stock: FilmStock) -> some View {
        let isSelected = stock == selection
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selection = stock
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(stock.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                Text(stock.chineseName)
                    .font(.system(size: 9))
                    .opacity(0.7)
            }
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? stock.accent : Color.white.opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.35) : Color.white.opacity(0.10),
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 小胶囊信息块

struct InfoChip: View {
    let title: String
    let value: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.4))
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }
}
