cl def:pub app -> JsxElement {
    has tasks: list = [];

    can with entry {
        tasks = await get_tasks();
    }

    return
        <div>
            <h1>Day Planner</h1>
        </div>;
}
