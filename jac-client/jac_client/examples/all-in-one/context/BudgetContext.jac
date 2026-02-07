# Budget Context for global state management
# Demonstrates: createContext, useContext, Context.Provider
cl import from react {
    createContext,
    useContext
}
cl import from ..hooks.useBudget { useBudget }

cl {
    glob:pub BudgetContext = createContext(None);
    # Create the context - demonstrates glob for context

    # Provider component - wraps app and provides budget state
    def:pub BudgetProvider(children: any) -> JsxElement {
        budget = useBudget();

        return
            <BudgetContext.Provider value={budget}>
                {children}
            </BudgetContext.Provider>;
    }

    # Custom hook to access budget context
    def:pub useBudgetContext -> dict {
        context = useContext(BudgetContext);
        if context == None {
            console.error("useBudgetContext must be used within BudgetProvider");
        }
        return context;
    }
}
