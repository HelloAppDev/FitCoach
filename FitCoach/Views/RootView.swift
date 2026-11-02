import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        if let profile = profiles.first {
            MainTabView(profile: profile)
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    let profile: UserProfile

    var body: some View {
        TabView {
            HomeView(profile: profile)
                .tabItem { Label("Сегодня", systemImage: "house.fill") }
            MealsView(profile: profile)
                .tabItem { Label("Питание", systemImage: "fork.knife") }
            WorkoutsView(profile: profile)
                .tabItem { Label("Зал", systemImage: "dumbbell.fill") }
            ChatView(profile: profile)
                .tabItem { Label("Коуч", systemImage: "bubble.left.and.bubble.right.fill") }
            ProfileView(profile: profile)
                .tabItem { Label("Профиль", systemImage: "person.fill") }
        }
    }
}
