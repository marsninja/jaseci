# Edge reference chain with subscripted start expression
nd Person {
    has name: str;
}

edge Knows;

glob people = root ++> Person(name="Alice"),
     friends = [people[0]->:Knows:->(?:Person)];
