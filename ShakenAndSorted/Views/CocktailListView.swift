import SwiftUI
import SwiftData

struct CocktailListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Cocktail.createdAt, order: .reverse) private var cocktails: [Cocktail]
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if cocktails.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Shaken & Sorted")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add cocktail")
                }
            }
            .sheet(isPresented: $showingAdd) {
                CocktailEditorView(mode: .add)
            }
        }
        .tint(AppTheme.accent)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wineglass")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text("No drinks yet")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
            Text("Log what you drank and what was in it.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showingAdd = true
            } label: {
                Text("Add your first")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 48)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var listContent: some View {
        List {
            ForEach(cocktails) { cocktail in
                NavigationLink {
                    CocktailDetailView(cocktail: cocktail)
                } label: {
                    CocktailRowView(cocktail: cocktail)
                }
                .listRowBackground(AppTheme.card)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(cocktails[index])
        }
    }
}
