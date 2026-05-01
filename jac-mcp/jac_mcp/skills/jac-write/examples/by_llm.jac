"""MTP patterns: constrained output via enum, structured output via obj + sem.

The function signature IS the prompt. Types constrain the output.

Run with: export ANTHROPIC_API_KEY=... && jac by_llm.jac
Type-check only (no key needed): jac check by_llm.jac
"""

import from byllm.lib { Model }

glob llm = Model(model_name="claude-sonnet-4-20250514");

# ---- Pattern 1: enum output -- LLM must pick ONE of the defined values ----
enum Category { WORK, PERSONAL, SHOPPING, HEALTH, OTHER }

def categorize(title: str) -> Category by llm();
sem categorize = "Categorize a task based on its title";

# ---- Pattern 2: structured output -- obj schema + sem hints on ambiguous fields ----
enum Unit { PIECE, LB, OZ, CUP, TBSP, TSP, BUNCH }

obj Ingredient {
    has name: str,
        quantity: float,
        unit: Unit,
        cost: float,
        carby: bool;
}

sem Ingredient.cost = "Estimated cost in USD";
sem Ingredient.carby = "True if this ingredient is high in carbohydrates";

def shopping_list(meal: str) -> list[Ingredient] by llm();
sem shopping_list = "Generate a shopping list of ingredients needed for a described meal";

# Uncomment once ANTHROPIC_API_KEY is set:
# c = categorize("Buy groceries for the week");
# print(c);  # Category.SHOPPING
#
# items = shopping_list("chicken stir fry for 4");
# for i in items {
#     print(f"{i.quantity} {i.unit} {i.name} -- ${i.cost:.2f}");
# }
with entry {
    print(
        "by_llm.jac compiled. Set ANTHROPIC_API_KEY and uncomment the with-entry block to run."
    );
}
