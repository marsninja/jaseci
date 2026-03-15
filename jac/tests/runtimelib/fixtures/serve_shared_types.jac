"""Test fixture for shared type serialization and deserialization."""

obj UserProfile {
    has name: str, age: int;
}

obj Address {
    has street: str, city: str;
}

obj FullUser {
    has profile: UserProfile, address: Address;
}

def:pub get_user(id: str) -> UserProfile {
    return UserProfile(name="Alice", age=30);
}

def:pub get_full_user() -> FullUser {
    return FullUser(
        profile=UserProfile(name="Bob", age=25),
        address=Address(street="123 Main St", city="NYC")
    );
}

def:pub get_data() -> dict {
    return {"key": "value", "count": 42};
}

walker FetchUser {
    can enter with Root entry {
        report UserProfile(name="Charlie", age=40);
    }
}

cl {
    async def:pub app() -> Any {
        user = await get_user("1");
        full = await get_full_user();
        return <div>{user.name} - {full.profile.name}</div>;
    }
}
