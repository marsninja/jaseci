nd MyNode {
    has foo: str = "";
}

nd Session {
    can generate_result with AgentVisitor entry {
        conn = self ++> MyNode();
        other = conn ++> MyNode();
        other ++> MyNode();
    }
}
